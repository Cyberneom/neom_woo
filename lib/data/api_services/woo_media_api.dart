import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:neom_core/app_config.dart';
import 'package:neom_core/app_properties.dart';
import 'package:neom_core/cloud_properties.dart';
import 'package:neom_core/domain/use_cases/woo_media_service.dart';
import 'package:neom_core/utils/neom_error_logger.dart';
import 'package:neom_core/utils/platform/core_io.dart';

import '../../utils/constants/woo_constants.dart';
import '../../utils/woo_security_utils.dart';

class WooMediaAPI implements WooMediaService {
  /// Maximum allowed upload size for WordPress media (`25 MiB`).
  static const int maxUploadBytes = 25 * 1024 * 1024;

  /// Maximum allowed JSON response size for WordPress media upload (`2 MiB`).
  static const int maxJsonResponseBytes = 2 * 1024 * 1024;

  /// Maximum allowed JWT token response size (`512 KiB`).
  static const int maxJwtResponseBytes = 512 * 1024;

  static final RegExp _unsafeUrlControls = WooSecurityUtils.unsafeUrlControlChars;
  static final RegExp _unsafeHeaderChars = RegExp(r'[\r\n\x00]');

  static Future<String?> _readBoundedUtf8(
    Stream<List<int>> stream,
    int maxBytes,
  ) async {
    final chunks = <int>[];
    await for (final chunk in stream.timeout(const Duration(seconds: 15))) {
      chunks.addAll(chunk);
      if (chunks.length > maxBytes) {
        return null;
      }
    }
    return utf8.decode(chunks, allowMalformed: true);
  }

  /// Sanitizes a filename for safe use in HTTP `Content-Disposition` headers and
  /// multipart uploads, stripping path traversal (`..`, `/`, `\`), Bidi/control
  /// characters, quotes, and leading dots.
  static String sanitizeMediaFilename(
    String filename, {
    String fallbackExtension = '',
  }) =>
      WooSecurityUtils.sanitizeMediaFilename(
        filename,
        fallbackExtension: fallbackExtension,
      );

  @override
  Future<String> uploadMediaToWordPress(File file, {String fileName = ''}) async {
    if (CloudProperties.isSecureMode || kIsWeb) {
      AppConfig.logger.w('uploadMediaToWordPress skipped in secure mode — use wooMediaProxy');
      return '';
    }
    final siteUrl = AppProperties.getSiteUrl().trim();
    if (siteUrl.isEmpty || _unsafeUrlControls.hasMatch(siteUrl)) return '';
    final targetUrl = '$siteUrl/wp-json/wp/v2/media';
    if (!WooSecurityUtils.isSafePublicHttpsUrl(targetUrl)) {
      return '';
    }
    final uri = Uri.parse(targetUrl);

    AppConfig.logger.i("Uploading media file to WordPress");
    String mediaUrl = '';

    try {
      // Block UNC paths, symlinks, missing files, empty files, and oversized payloads before reading.
      final rawFilePath = file.path.trim();
      if (rawFilePath.isEmpty ||
          rawFilePath.startsWith('//') ||
          rawFilePath.startsWith(r'\\') ||
          _unsafeUrlControls.hasMatch(rawFilePath)) {
        AppConfig.logger.w('uploadMediaToWordPress rejected unsafe file path');
        return '';
      }
      final entityType =
          FileSystemEntity.typeSync(file.path, followLinks: false);
      final parentType =
          FileSystemEntity.typeSync(file.parent.path, followLinks: false);
      if (entityType != FileSystemEntityType.file ||
          parentType == FileSystemEntityType.link) {
        AppConfig.logger.w('uploadMediaToWordPress rejected non-regular or symlinked file');
        return '';
      }
      final fileBytes = file.lengthSync();
      if (fileBytes <= 0 || fileBytes > maxUploadBytes) {
        AppConfig.logger.w(
          'uploadMediaToWordPress rejected invalid file size ($fileBytes bytes)',
        );
        return '';
      }

      String jwtToken = await getJwtToken();
      if (jwtToken.isEmpty) return '';

      String originalFilePath = file.path.replaceAll('\\', '/').split('/').last;
      String fileExtension = '';
      if (originalFilePath.contains('.')) {
        fileExtension = '.${originalFilePath.split('.').last}';
      }

      String rawFilename = fileName.isNotEmpty ? fileName : originalFilePath;
      String sanitizedFilename = sanitizeMediaFilename(
        rawFilename,
        fallbackExtension: fileExtension,
      );

      AppConfig.logger.d("Sanitized filename: $sanitizedFilename");

      var request = http.MultipartRequest('POST', uri)
        ..followRedirects = false;
      request.files.add(http.MultipartFile(
        'file',
        file.openRead(),
        fileBytes,
        filename: sanitizedFilename,
      ));

      request.headers['Authorization'] = 'Bearer $jwtToken';
      request.headers['Content-Disposition'] = 'attachment; filename="$sanitizedFilename"';
      request.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

      var response = await request.send().timeout(const Duration(seconds: 30));

      if (response.statusCode == 201) {
        final responseData =
            await _readBoundedUtf8(response.stream, maxJsonResponseBytes);
        if (responseData == null) {
          AppConfig.logger.w(
            'uploadMediaToWordPress rejected oversized media response',
          );
          return '';
        }
        final jsonData = jsonDecode(responseData);
        if (jsonData is Map && jsonData['source_url'] != null) {
          final candidateUrl = jsonData['source_url'].toString().trim();
          if (WooSecurityUtils.isSafePublicHttpsUrl(candidateUrl)) {
            mediaUrl = candidateUrl;
            AppConfig.logger.i('Media uploaded successfully: $mediaUrl');
          }
        }
      } else {
        await response.stream.drain<void>().catchError((_) {});
        AppConfig.logger.e('Failed to upload media: HTTP ${response.statusCode}');
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'uploadMediaToWordPress');
    }

    return mediaUrl;
  }

  @override
  Future<String> getJwtToken() async {
    if (CloudProperties.isSecureMode || kIsWeb) {
      AppConfig.logger.w('getJwtToken skipped in secure mode — use wooMediaProxy');
      return '';
    }

    final siteUrl = AppProperties.getSiteUrl().trim();
    if (siteUrl.isEmpty) return '';
    final jwtEndpoint = '$siteUrl${WooConstants.jwtTokenUrl}';
    if (!WooSecurityUtils.isSafePublicHttpsUrl(jwtEndpoint)) {
      throw StateError('Invalid WordPress JWT endpoint');
    }
    final uri = Uri.parse(jwtEndpoint);

    final client = http.Client();
    late final int statusCode;
    late final String? rawBody;
    try {
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Content-Type': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        })
        ..body = jsonEncode({
          WooConstants.username: CloudProperties.getWooAccount(),
          WooConstants.password: CloudProperties.getWooPass(),
        });
      final streamed =
          await client.send(request).timeout(const Duration(seconds: 15));
      statusCode = streamed.statusCode;
      if (statusCode == 200) {
        if (streamed.contentLength != null &&
            streamed.contentLength! > maxJwtResponseBytes) {
          await streamed.stream.drain<void>().catchError((_) {});
          throw StateError('WordPress JWT response exceeded size limit');
        }
        rawBody = await _readBoundedUtf8(streamed.stream, maxJwtResponseBytes);
      } else {
        await streamed.stream.drain<void>().catchError((_) {});
        rawBody = null;
      }
    } finally {
      client.close();
    }

    if (statusCode == 200) {
      if (rawBody == null) {
        throw StateError('WordPress JWT response exceeded size limit');
      }
      final responseData = jsonDecode(rawBody);
      if (responseData is Map && responseData['token'] is String) {
        final sanitizedToken = (responseData['token'] as String)
            .replaceAll(_unsafeHeaderChars, '')
            .trim();
        if (sanitizedToken.isEmpty) {
          throw StateError('Empty JWT token in WordPress response');
        }
        return sanitizedToken;
      }
      throw StateError('Missing JWT token in WordPress response');
    } else {
      throw Exception('Failed to obtain JWT token. Status Code $statusCode');
    }
  }

}
