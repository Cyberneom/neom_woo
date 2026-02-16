import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:neom_core/app_config.dart';
import 'package:neom_core/app_properties.dart';
import 'package:neom_core/domain/use_cases/woo_media_service.dart';

import '../../utils/constants/woo_constants.dart';

class WooMediaAPI implements WooMediaService {

  /// Sanitizes a filename for use in HTTP headers by removing non-ASCII characters
  /// and replacing accented characters with their ASCII equivalents.
  String _sanitizeFilename(String filename) {
    // Map of accented characters to their ASCII equivalents
    const Map<String, String> accentMap = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
      'Á': 'A', 'À': 'A', 'Ä': 'A', 'Â': 'A', 'Ã': 'A', 'Å': 'A',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'É': 'E', 'È': 'E', 'Ë': 'E', 'Ê': 'E',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Î': 'I',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', 'ø': 'o',
      'Ó': 'O', 'Ò': 'O', 'Ö': 'O', 'Ô': 'O', 'Õ': 'O', 'Ø': 'O',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'Ú': 'U', 'Ù': 'U', 'Ü': 'U', 'Û': 'U',
      'ñ': 'n', 'Ñ': 'N',
      'ç': 'c', 'Ç': 'C',
    };

    String sanitized = filename;
    accentMap.forEach((accented, replacement) {
      sanitized = sanitized.replaceAll(accented, replacement);
    });

    // Remove any remaining non-ASCII characters
    sanitized = sanitized.replaceAll(RegExp(r'[^\x00-\x7F]'), '');

    // Replace spaces with underscores for safety
    sanitized = sanitized.replaceAll(' ', '_');

    return sanitized;
  }

  @override
  Future<String> uploadMediaToWordPress(File file, {String fileName = ''}) async {
    AppConfig.logger.i("Uploading media file to WordPress");

    String url = '${AppProperties.getSiteUrl()}/wp-json/wp/v2/media';
    String mediaUrl = '';

    try {
      // Get the original file extension from the actual file path
      String originalFilePath = file.path.split('/').last;
      String fileExtension = '';
      if (originalFilePath.contains('.')) {
        fileExtension = '.${originalFilePath.split('.').last}';
      }

      // Sanitize filename for HTTP headers (remove accents and special characters)
      String rawFilename = fileName.isNotEmpty ? fileName : originalFilePath;
      String sanitizedFilename = _sanitizeFilename(rawFilename);

      // Ensure the sanitized filename has the correct extension
      if (fileExtension.isNotEmpty && !sanitizedFilename.toLowerCase().endsWith(fileExtension.toLowerCase())) {
        sanitizedFilename = '$sanitizedFilename$fileExtension';
      }

      AppConfig.logger.d("Sanitized filename: $rawFilename -> $sanitizedFilename");

      // Crea una solicitud de subida multipart
      var request = http.MultipartRequest('POST', Uri.parse(url));

      // Añadir el archivo al cuerpo de la solicitud
      request.files.add(http.MultipartFile(
        'file',
        file.readAsBytes().asStream(),
        file.lengthSync(),
        filename: sanitizedFilename,
      ));

      // Añade las cabeceras necesarias
      String jwtToken = await getJwtToken();
      request.headers['Authorization'] = 'Bearer $jwtToken';
      request.headers['Content-Disposition'] = 'attachment; filename="$sanitizedFilename"';

      // Envía la solicitud
      var response = await request.send();

      if (response.statusCode == 201) {
        // Obtiene la respuesta y decodifica
        var responseData = await response.stream.bytesToString();
        var jsonData = jsonDecode(responseData);
        mediaUrl = jsonData['source_url'];
        AppConfig.logger.i('Media uploaded successfully: $mediaUrl');
      } else {
        AppConfig.logger.e('Failed to upload media: ${response.statusCode}');
        AppConfig.logger.e('Response: ${await response.stream.bytesToString()}');
      }
    } catch (e) {
      AppConfig.logger.e('Error uploading media: $e');
    }

    return mediaUrl;
  }

  @override
  Future<String> getJwtToken() async {
    String url = '${AppProperties.getSiteUrl()}${WooConstants.jwtTokenUrl}';

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        WooConstants.username: AppProperties.getWooAccount(),
        WooConstants.password: AppProperties.getWooPass(),
      }),
    );

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      return responseData['token'];  // Retorna el token JWT
    } else {
      throw Exception('Failed to obtain JWT token. Status Code ${response.statusCode}');
    }
  }

}
