import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'constants/woo_constants.dart';

/// Pure-Dart security and platform routing helpers for `neom_woo`.
class WooSecurityUtils {
  WooSecurityUtils._();

  static final RegExp unsafeUrlControlChars = RegExp(
    r'[\x00-\x1F\x7F-\x9F\u061C\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060-\u2069\uFEFF]',
  );
  static final RegExp _rawEncodedTraversalOrBidi = RegExp(
    r'(?:^|/)\.\.(?:/|$|\?|#)|%2e%2e|%2e\.|\.%2e|%2f|%5c|%25|%00|%(?:c2%[89][0-9a-f]|d8%9c|e2%80%(?:8[b-f]|a[8-e])|e2%81%a[0-9]|ef%bb%bf)',
    caseSensitive: false,
  );
  static final RegExp _idnDotHomoglyphs = RegExp(r'[\u3002\uFF0E\uFF61]');
  static const Set<String> _prototypePollutionKeys = <String>{
    '__proto__',
    'constructor',
    'prototype',
  };
  static final RegExp _internalTagBlockPattern = RegExp(
    r'<\|(?:channel|turn)\s*>\s*thought[\s\S]*?(?:<(?:channel|turn)\|>|$)|<\|tool_call\s*>[\s\S]*?(?:<tool_call\|>|$)|<\s*(think|thought|thinking|memory_recall|auto_memory|system_context)\b[^>]*>[\s\S]*?(?:<\s*/\s*\1\s*>|$)|\[\s*(BIOCHIP|MEMORY_RECALL|AUTO_MEMORY|SYSTEM_CONTEXT)\s*\](?:(?!\[\s*\2\s*\])[\s\S])*?\[\s*/\s*\2\s*\]',
    caseSensitive: false,
  );
  static final RegExp _orphanInternalTagPattern = RegExp(
    r'<\s*/?\s*(?:think|thought|thinking|memory_recall|auto_memory|system_context)\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _contentCloseBreakoutPattern = RegExp(
    r'<\s*/\s*content\s*>',
    caseSensitive: false,
  );
  static final RegExp _turnDelimiterPattern = RegExp(
    r'<\|/?(?:turn|channel|tool_call|im_start|im_end|eot_id|eot)\|?>?|<(?:turn|channel|tool_call|eot)\|>|<end_of_turn>',
    caseSensitive: false,
  );
  static final RegExp _biochipPattern = RegExp(
    r'\[\s*/?\s*(?:BIOCHIP(?:\s*:[^\]]*)?|MEMORY_RECALL|AUTO_MEMORY|SYSTEM_CONTEXT)\s*\]',
    caseSensitive: false,
  );
  static final RegExp _windowsReservedBasenameRe = RegExp(
    r'^(?:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|CLOCK\$|COM[1-9]|LPT[1-9]|__PROTO__|CONSTRUCTOR|PROTOTYPE)(?:\..*)?$',
    caseSensitive: false,
  );

  static const Set<String> trustedPaymentDomains = {
    'paypal.com',
    'paypalobjects.com',
    'stripe.com',
    'stripe.network',
    'hcaptcha.com',
    'recaptcha.net',
    'mercadopago.com',
    'mercadopago.com.mx',
    'mercadolibre.com',
  };

  /// True on Web and Desktop platforms (`macOS`/`Windows`/`Linux`) where
  /// `webview_flutter` lacks an embedded platform implementation and throws
  /// `UnimplementedError`.
  static bool shouldUseExternalBrowser({
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
  }) {
    if (isWeb) return true;
    final effective = platform ?? defaultTargetPlatform;
    return effective == TargetPlatform.macOS ||
        effective == TargetPlatform.windows ||
        effective == TargetPlatform.linux;
  }

  static bool hostMatchesDomain(String host, String domain) {
    if (host.isEmpty || domain.isEmpty) return false;
    return host == domain || host.endsWith('.$domain');
  }

  /// True only when [rawUrl] is an HTTPS URL on [siteHost] with zero control or
  /// Bidi spoofing characters and empty `userInfo`.
  static bool isAllowedSiteUrl(String rawUrl, {required String siteHost}) {
    if (unsafeUrlControlChars.hasMatch(rawUrl) ||
        unsafeUrlControlChars.hasMatch(siteHost) ||
        _idnDotHomoglyphs.hasMatch(rawUrl) ||
        _idnDotHomoglyphs.hasMatch(siteHost) ||
        _rawEncodedTraversalOrBidi.hasMatch(rawUrl)) {
      return false;
    }
    final trimmed = rawUrl.trim();
    final cleanHost = siteHost.trim().toLowerCase();
    if (trimmed.isEmpty ||
        cleanHost.isEmpty ||
        trimmed.contains(r'\') ||
        unsafeUrlControlChars.hasMatch(trimmed)) {
      return false;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return false;
    }
    return hostMatchesDomain(uri.host.toLowerCase(), cleanHost);
  }

  /// Strict HTTPS host-based navigation gate: allows only [siteHost] or trusted
  /// external payment/captcha provider domains.
  static bool isAllowedNavigationUrl(
    String rawUrl, {
    required String siteHost,
  }) {
    if (unsafeUrlControlChars.hasMatch(rawUrl) ||
        _idnDotHomoglyphs.hasMatch(rawUrl) ||
        _rawEncodedTraversalOrBidi.hasMatch(rawUrl)) {
      return false;
    }
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty ||
        trimmed.contains(r'\') ||
        unsafeUrlControlChars.hasMatch(trimmed)) {
      return false;
    }
    if (isAllowedSiteUrl(trimmed, siteHost: siteHost)) return true;
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (host == 'files.stripe.com' || host.endsWith('.files.stripe.com')) {
      return false;
    }
    return trustedPaymentDomains.any((d) => hostMatchesDomain(host, d));
  }

  /// Safely extracts `(orderId, orderKey)` from a WooCommerce `orden-recibida` URL.
  static (String, String) parseOrderConfirmation(String rawUrl) {
    if (unsafeUrlControlChars.hasMatch(rawUrl) ||
        _idnDotHomoglyphs.hasMatch(rawUrl) ||
        rawUrl.toLowerCase().contains('%00')) {
      return ('', '');
    }
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty || unsafeUrlControlChars.hasMatch(trimmed)) {
      return ('', '');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return ('', '');
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final idx = segments.indexOf(WooConstants.ordenRecibida);
    if (idx < 0 || idx + 1 >= segments.length) return ('', '');
    final rawCandidateId = segments[idx + 1];
    if (unsafeUrlControlChars.hasMatch(rawCandidateId)) return ('', '');
    final candidateId = rawCandidateId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(candidateId) ||
        _prototypePollutionKeys.contains(candidateId.toLowerCase()) ||
        (candidateId.startsWith('__') && candidateId.endsWith('__'))) {
      return ('', '');
    }
    final rawKeyParam = uri.queryParameters['key'] ?? '';
    final rawKey = rawKeyParam.trim();
    final isSafeKey = !unsafeUrlControlChars.hasMatch(rawKeyParam) &&
        RegExp(r'^[A-Za-z0-9_.-]{0,128}$').hasMatch(rawKey) &&
        !_prototypePollutionKeys.contains(rawKey.toLowerCase()) &&
        !(rawKey.startsWith('__') && rawKey.endsWith('__'));
    final orderKey = isSafeKey ? rawKey : '';
    return (candidateId, orderKey);
  }

  static int? _parseIpv4Component(String token, int maxVal) {
    if (token.isEmpty) return null;
    int? parsed;
    if (token.startsWith('0x') || token.startsWith('0X')) {
      if (token.length <= 2) return null;
      parsed = int.tryParse(token.substring(2), radix: 16);
    } else if (token.length > 1 && token.startsWith('0')) {
      parsed = int.tryParse(token.substring(1), radix: 8);
    } else {
      parsed = int.tryParse(token, radix: 10);
    }
    if (parsed == null || parsed < 0 || parsed > maxVal) return null;
    return parsed;
  }

  /// Parses standard, shorthand (`127.1`, `169.254.43518`), octal (`0177.0.0.1`),
  /// hex (`0x7f.0.0.1`), and single-integer (`2130706433`) IPv4 literals using
  /// 53-bit JS-safe arithmetic (`* 0x1000000` instead of `<< 24`).
  static int? _tryParseIpv4Uint32(String host) {
    if (host.isEmpty || host.contains(':')) return null;
    final parts = host.split('.');
    if (parts.isEmpty || parts.length > 4) return null;
    if (parts.any((p) => p.isEmpty)) return null;
    if (parts.length == 1) {
      return _parseIpv4Component(parts[0], 0xFFFFFFFF);
    }
    if (parts.length == 2) {
      final a = _parseIpv4Component(parts[0], 0xFF);
      final rest = _parseIpv4Component(parts[1], 0xFFFFFF);
      if (a == null || rest == null) return null;
      return a * 0x1000000 + rest;
    }
    if (parts.length == 3) {
      final a = _parseIpv4Component(parts[0], 0xFF);
      final b = _parseIpv4Component(parts[1], 0xFF);
      final rest = _parseIpv4Component(parts[2], 0xFFFF);
      if (a == null || b == null || rest == null) return null;
      return a * 0x1000000 + b * 0x10000 + rest;
    }
    final a = _parseIpv4Component(parts[0], 0xFF);
    final b = _parseIpv4Component(parts[1], 0xFF);
    final c = _parseIpv4Component(parts[2], 0xFF);
    final d = _parseIpv4Component(parts[3], 0xFF);
    if (a == null || b == null || c == null || d == null) return null;
    return a * 0x1000000 + b * 0x10000 + c * 0x100 + d;
  }

  static bool _isReservedIpv4Uint32(int ip) {
    final a = (ip ~/ 0x1000000) & 0xFF;
    final b = (ip ~/ 0x10000) & 0xFF;
    final c = (ip ~/ 0x100) & 0xFF;
    if (a == 0 || a == 10 || a == 127) return true;
    if (a == 100 && b >= 64 && b <= 127) return true;
    if (a == 169 && b == 254) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 0 && (c == 0 || c == 2)) return true;
    if (a == 192 && b == 168) return true;
    if (a == 198 && (b == 18 || b == 19)) return true;
    if (a == 198 && b == 51 && c == 100) return true;
    if (a == 203 && b == 0 && c == 113) return true;
    if (a >= 224) return true;
    return false;
  }

  static List<int>? _tryParseIpv6Bytes(String host) {
    if (!host.contains(':')) return null;
    if ('::'.allMatches(host).length > 1) return null;

    var working = host;
    int? embeddedIpv4;
    final lastColon = working.lastIndexOf(':');
    if (lastColon >= 0 && working.substring(lastColon + 1).contains('.')) {
      embeddedIpv4 = _tryParseIpv4Uint32(working.substring(lastColon + 1));
      if (embeddedIpv4 == null) return null;
      final hi = (embeddedIpv4 ~/ 0x10000) & 0xFFFF;
      final lo = embeddedIpv4 & 0xFFFF;
      working =
          '${working.substring(0, lastColon + 1)}${hi.toRadixString(16)}:${lo.toRadixString(16)}';
    }

    final words = <int>[];
    if (working.contains('::')) {
      final halves = working.split('::');
      if (halves.length != 2) return null;
      final left =
          halves[0].isEmpty ? const <String>[] : halves[0].split(':');
      final right =
          halves[1].isEmpty ? const <String>[] : halves[1].split(':');
      if (left.length + right.length >= 8) return null;
      for (final seg in left) {
        if (seg.isEmpty || seg.length > 4) return null;
        final v = int.tryParse(seg, radix: 16);
        if (v == null || v < 0 || v > 0xFFFF) return null;
        words.add(v);
      }
      final zeros = 8 - left.length - right.length;
      for (var i = 0; i < zeros; i++) {
        words.add(0);
      }
      for (final seg in right) {
        if (seg.isEmpty || seg.length > 4) return null;
        final v = int.tryParse(seg, radix: 16);
        if (v == null || v < 0 || v > 0xFFFF) return null;
        words.add(v);
      }
    } else {
      final segs = working.split(':');
      if (segs.length != 8) return null;
      for (final seg in segs) {
        if (seg.isEmpty || seg.length > 4) return null;
        final v = int.tryParse(seg, radix: 16);
        if (v == null || v < 0 || v > 0xFFFF) return null;
        words.add(v);
      }
    }
    if (words.length != 8) return null;
    final bytes = <int>[];
    for (final w in words) {
      bytes.add((w >> 8) & 0xFF);
      bytes.add(w & 0xFF);
    }
    return bytes;
  }

  static bool _isReservedIpv6Bytes(List<int> b) {
    final allZeroPrefix10 = b.sublist(0, 10).every((x) => x == 0);
    // Unspecified ::/128 and Loopback ::1/128 (including expanded forms)
    if (allZeroPrefix10 && b[10] == 0 && b[11] == 0) {
      final tail32 =
          b[12] * 0x1000000 + b[13] * 0x10000 + b[14] * 0x100 + b[15];
      if (tail32 == 0 || tail32 == 1) return true;
      // IPv4-compatible ::w.x.y.z
      return _isReservedIpv4Uint32(tail32);
    }
    // IPv4-mapped ::ffff:0:0/96 (including expanded 0:0:0:0:0:ffff:...)
    if (allZeroPrefix10 && b[10] == 0xFF && b[11] == 0xFF) {
      final mapped =
          b[12] * 0x1000000 + b[13] * 0x10000 + b[14] * 0x100 + b[15];
      return _isReservedIpv4Uint32(mapped);
    }
    // NAT64 well-known prefix 64:ff9b::/96 & local 64:ff9b:1::/48
    if (b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xFF && b[3] == 0x9B) {
      return true;
    }
    // Unique local fc00::/7, Link-local fe80::/10, Multicast ff00::/8
    if ((b[0] & 0xFE) == 0xFC) return true;
    if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) return true;
    if (b[0] == 0xFF) return true;
    // 6to4 2002::/16 (embeds IPv4 in bytes 2..5)
    if (b[0] == 0x20 && b[1] == 0x02) return true;
    // Teredo 2001:0000::/32, Benchmarking 2001:0002::/48, Documentation 2001:db8::/32
    if (b[0] == 0x20 && b[1] == 0x01) {
      if (b[2] == 0x00 && b[3] == 0x00) return true;
      if (b[2] == 0x00 && b[3] == 0x02 && b[4] == 0x00 && b[5] == 0x00) {
        return true;
      }
      if (b[2] == 0x0D && b[3] == 0xB8) return true;
    }
    return false;
  }

  /// True if [rawHost] is loopback, RFC1918 private LAN, CGNAT, link-local,
  /// cloud metadata (`169.254.169.254`, `100.100.100.200`, `*.internal`), or
  /// IPv6 ULA/link-local/mapped/NAT64/6to4 private address.
  static bool isPrivateOrReservedHost(String rawHost) {
    if (unsafeUrlControlChars.hasMatch(rawHost) ||
        _idnDotHomoglyphs.hasMatch(rawHost)) {
      return true;
    }
    var bare = rawHost.trim().toLowerCase();
    if (bare.startsWith('[') && bare.endsWith(']')) {
      bare = bare.substring(1, bare.length - 1);
    }
    while (bare.endsWith('.')) {
      bare = bare.substring(0, bare.length - 1);
    }
    if (bare.isEmpty ||
        bare == 'null' ||
        bare.contains('%') ||
        bare.contains(r'\') ||
        unsafeUrlControlChars.hasMatch(bare) ||
        bare == 'localhost' ||
        bare.endsWith('.localhost') ||
        bare.endsWith('.local') ||
        bare.endsWith('.internal') ||
        bare.endsWith('.corp') ||
        bare.endsWith('.lan') ||
        bare.endsWith('.home.arpa') ||
        bare.endsWith('.ts.net') ||
        bare.endsWith('.invalid') ||
        bare.endsWith('.onion') ||
        bare == 'metadata' ||
        bare == 'instance-data' ||
        bare == 'metadata.goog' ||
        bare.endsWith('.metadata.goog') ||
        bare == 'metadata.google.internal' ||
        bare.endsWith('.metadata.google.internal') ||
        bare == 'metadata.azure.com' ||
        bare == 'metadata.azure.internal' ||
        bare.endsWith('.metadata.azure.com')) {
      return true;
    }
    if (bare.contains(':')) {
      final ipv6Bytes = _tryParseIpv6Bytes(bare);
      if (ipv6Bytes == null) return true;
      return _isReservedIpv6Bytes(ipv6Bytes);
    }
    final ipv4 = _tryParseIpv4Uint32(bare);
    if (ipv4 != null) {
      return _isReservedIpv4Uint32(ipv4);
    }
    final lastLabel = bare.split('.').last;
    if (RegExp(r'^[0-9]+$').hasMatch(lastLabel) ||
        lastLabel.startsWith('0x')) {
      return true;
    }
    return false;
  }

  /// Validates that [rawUrl] is a well-formed public `https://` URL without
  /// credentials, control/Bidi chars, or private/loopback/metadata hosts.
  static bool isSafePublicHttpsUrl(String rawUrl) {
    if (unsafeUrlControlChars.hasMatch(rawUrl) ||
        _idnDotHomoglyphs.hasMatch(rawUrl) ||
        _rawEncodedTraversalOrBidi.hasMatch(rawUrl)) {
      return false;
    }
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 2048 ||
        trimmed.contains(r'\') ||
        unsafeUrlControlChars.hasMatch(trimmed)) {
      return false;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty) {
      return false;
    }
    if (!uri.host.contains('.')) return false;
    return !isPrivateOrReservedHost(uri.host);
  }

  /// Validates a relative WooCommerce REST API path (must start with `/`,
  /// contain no `..` traversal, percent-encoded dot-segments, authority `//`,
  /// backslashes, or control chars).
  static bool isSafeApiPath(String rawPath) {
    if (unsafeUrlControlChars.hasMatch(rawPath) ||
        _idnDotHomoglyphs.hasMatch(rawPath) ||
        _rawEncodedTraversalOrBidi.hasMatch(rawPath)) {
      return false;
    }
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 1024 ||
        !trimmed.startsWith('/') ||
        trimmed.startsWith('//') ||
        trimmed.contains(r'\') ||
        trimmed.contains('://') ||
        unsafeUrlControlChars.hasMatch(trimmed)) {
      return false;
    }
    // Inspect raw & percent-decoded path segments BEFORE Uri.tryParse applies
    // RFC 3986 remove_dot_segments (which would otherwise escape /wp-json/wc/v3).
    final qIdx = trimmed.indexOf('?');
    final hIdx = trimmed.indexOf('#');
    var endIdx = trimmed.length;
    if (qIdx >= 0 && qIdx < endIdx) endIdx = qIdx;
    if (hIdx >= 0 && hIdx < endIdx) endIdx = hIdx;
    final rawPathOnly = trimmed.substring(0, endIdx);
    for (final rawSeg in rawPathOnly.split('/')) {
      if (rawSeg.isEmpty) continue;
      if (rawSeg == '.' || rawSeg == '..') return false;
      String decoded;
      try {
        decoded = Uri.decodeComponent(rawSeg);
      } catch (_) {
        return false;
      }
      if (decoded == '.' ||
          decoded == '..' ||
          decoded.contains('/') ||
          decoded.contains(r'\') ||
          unsafeUrlControlChars.hasMatch(decoded)) {
        return false;
      }
    }
    final uri = Uri.tryParse('https://woo.local$trimmed');
    if (uri == null || uri.host != 'woo.local') return false;
    return true;
  }

  static String sanitizeOrderDescription(String raw) {
    final cleaned = raw
        .replaceAll(_internalTagBlockPattern, '')
        .replaceAll(_orphanInternalTagPattern, '')
        .replaceAll(_turnDelimiterPattern, '')
        .replaceAll(_biochipPattern, '')
        .replaceAll(_contentCloseBreakoutPattern, '[content_end]')
        .replaceAll(unsafeUrlControlChars, '')
        .trim();
    if (cleaned.runes.length > 160) {
      return String.fromCharCodes(cleaned.runes.take(160));
    }
    return cleaned;
  }

  /// Sanitizes a filename for safe use in HTTP `Content-Disposition` headers and
  /// multipart uploads, stripping path traversal (`..`, `/`, `\`), Bidi/control
  /// characters, quotes, and leading dots.
  static String sanitizeMediaFilename(
    String filename, {
    String fallbackExtension = '',
  }) {
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

    final normalized = filename.replaceAll('\\', '/').trim();
    final segments = normalized
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList();
    String sanitized = segments.isNotEmpty ? segments.last : '';

    accentMap.forEach((accented, replacement) {
      sanitized = sanitized.replaceAll(accented, replacement);
    });

    sanitized = sanitized
        .replaceAll(unsafeUrlControlChars, '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'_+'), '_');

    while (sanitized.startsWith('.') || sanitized.startsWith('_')) {
      sanitized = sanitized.substring(1);
    }
    while (sanitized.endsWith('.') || sanitized.endsWith('_')) {
      sanitized = sanitized.substring(0, sanitized.length - 1);
    }
    if (sanitized.length > 96) {
      sanitized = sanitized.substring(0, 96);
      while (sanitized.endsWith('.') || sanitized.endsWith('_')) {
        sanitized = sanitized.substring(0, sanitized.length - 1);
      }
    }
    if (sanitized.isEmpty) {
      sanitized = 'media_${DateTime.now().millisecondsSinceEpoch}';
    }
    if (_windowsReservedBasenameRe.hasMatch(sanitized)) {
      sanitized = 'safe_$sanitized';
    }

    final cleanExt = fallbackExtension
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9.]'), '');
    if (cleanExt.startsWith('.') &&
        cleanExt.length > 1 &&
        cleanExt.length <= 10 &&
        !sanitized.toLowerCase().endsWith(cleanExt.toLowerCase())) {
      sanitized = '$sanitized$cleanExt';
    }
    if (_windowsReservedBasenameRe.hasMatch(sanitized)) {
      sanitized = 'safe_$sanitized';
    }
    return sanitized;
  }
}
