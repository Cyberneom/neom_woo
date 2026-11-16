import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:neom_core/app_config.dart';
import 'package:neom_core/app_properties.dart';
import 'package:neom_core/cloud_properties.dart';
import 'package:neom_core/utils/neom_error_logger.dart';

import '../../domain/model/woo_product.dart';
import '../../domain/model/woo_product_attribute.dart';
import '../../utils/constants/woo_attribute_constants.dart';
import '../../utils/constants/woo_constants.dart';
import '../../utils/enums/woo_product_status.dart';
import '../../utils/woo_security_utils.dart';

/// WooCommerce Products API.
/// In secure mode (web), routes through Cloud Functions wooProxy.
/// On mobile, calls WooCommerce directly with credentials.
class WooProductsAPI {
  static const Duration _httpTimeout = Duration(seconds: 20);
  static const int maxResponseBytes = 5 * 1024 * 1024;

  /// Central helper for WooCommerce API calls.
  /// In secure mode: proxies through Cloud Functions.
  /// On mobile: direct HTTP with Basic auth.
  static Future<dynamic> _callWoo({
    required String path,
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (!WooSecurityUtils.isSafeApiPath(path)) {
      throw StateError('WooProductsAPI: unsafe API path');
    }
    if (CloudProperties.isSecureMode || kIsWeb) {
      // Web: ALWAYS proxy — WooCommerce credentials are server-side only.
      return CloudProperties.wooProxy(path: path, method: method, body: body);
    }

    final baseUrl = AppProperties.getWooUrl().trim();
    if (baseUrl.isEmpty) {
      throw StateError('WooProductsAPI: empty Woo base URL');
    }
    final fullUrl = '$baseUrl$path';
    if (!WooSecurityUtils.isSafePublicHttpsUrl(fullUrl)) {
      throw StateError('WooProductsAPI: invalid or non-public HTTPS Woo URL');
    }
    final uri = Uri.parse(fullUrl);

    // Mobile only: direct call
    final credentials = base64Encode(
      utf8.encode('${CloudProperties.getWooClientKey()}:${CloudProperties.getWooClientSecret()}'),
    );
    final headers = <String, String>{
      'Authorization': 'Basic $credentials',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    };

    final upperMethod = switch (method.toUpperCase()) {
      'POST' => 'POST',
      'PUT' => 'PUT',
      _ => 'GET',
    };
    final encodedBody =
        ((upperMethod == 'POST' || upperMethod == 'PUT') && body != null)
            ? jsonEncode(body)
            : null;
    final client = http.Client();
    late final int statusCode;
    late final Map<String, String> responseHeaders;
    late final List<int> bodyBytes;
    try {
      final request = http.Request(upperMethod, uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      if (encodedBody != null) {
        request.body = encodedBody;
      }
      final streamed = await client.send(request).timeout(_httpTimeout);
      statusCode = streamed.statusCode;
      responseHeaders = streamed.headers;
      if (streamed.contentLength != null &&
          streamed.contentLength! > maxResponseBytes) {
        throw Exception('Respuesta WooCommerce excede límite de $maxResponseBytes bytes');
      }
      final chunks = <int>[];
      await for (final chunk in streamed.stream.timeout(_httpTimeout)) {
        chunks.addAll(chunk);
        if (chunks.length > maxResponseBytes) {
          throw Exception('Respuesta WooCommerce excede límite de $maxResponseBytes bytes');
        }
      }
      bodyBytes = chunks;
    } finally {
      client.close();
    }

    final decodedBody = utf8.decode(bodyBytes, allowMalformed: true);
    if (statusCode >= 200 && statusCode < 300) {
      return jsonDecode(decodedBody);
    }

    final contentType = responseHeaders['content-type'] ?? '';
    if (!contentType.contains('application/json') || decodedBody.trim().startsWith('<')) {
      AppConfig.logger.e('Woo response invalid ($statusCode)');
      throw Exception('Respuesta bloqueada por seguridad del servidor');
    }

    AppConfig.logger.e(
      'Woo error ($statusCode, ${bodyBytes.length} bytes)',
    );
    throw Exception('Error WooCommerce: $statusCode');
  }

  static Future<List<WooProduct>> getProducts({int perPage = 25, int page = 1,
    WooProductStatus status = WooProductStatus.publish, List<String> categoryIds = const []}) async {

    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(1, 100);
    String path = '/products?page=$safePage&per_page=$safePerPage&status=${Uri.encodeComponent(status.name)}';
    final cleanCategories = categoryIds
        .map((c) => c.trim())
        .where((c) => RegExp(r'^\d+$').hasMatch(c))
        .toList();
    if (cleanCategories.isNotEmpty) {
      path = '$path&category=${cleanCategories.join(',')}';
    }

    List<WooProduct> products = [];

    try {
      final data = await _callWoo(path: path);

      if (data is List) {
        for (var item in data) {
          WooProduct product = WooProduct.fromJSON(item);
          AppConfig.logger.t('Product ${product.id} with name ${product.name}');
          products.add(product);
        }
        AppConfig.logger.d('${products.length} Products retrieved');
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'getProducts');
    }
    return products;
  }

  /// Creates a new WooCommerce product and returns the created product with its ID and permalink
  static Future<WooProduct?> createProduct(WooProduct product) async {
    try {
      final data = await _callWoo(path: '/products', method: 'POST', body: product.toJSON());

      if (data != null) {
        AppConfig.logger.i('WooProduct created successfully');
        return WooProduct.fromJSON(data);
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'createProduct');
    }
    return null;
  }

  static Future<void> addAttributesToProduct(String productId, List<WooProductAttribute> attributes, {bool isNew = false}) async {
    final trimmedId = productId.trim();
    if (trimmedId.isEmpty) return;
    int position = 0;
    try {
      final remaining = List<WooProductAttribute>.from(attributes);
      List<WooProductAttribute> totalAttributes = [];
      if (!isNew) {
        WooProduct? currentProduct = await getProduct(trimmedId);
        if (currentProduct?.attributes?.isNotEmpty ?? false) {
          for (var attribute in remaining) {
            if (currentProduct!.attributes!.containsKey(attribute.name)) {
              currentProduct.attributes![attribute.name] = attribute;
              attribute.position = position;
              totalAttributes.add(attribute);
              position++;
            }
          }
          totalAttributes.addAll(currentProduct!.attributes!.values);
          for (var attribute in totalAttributes) {
            remaining.removeWhere((atr) => atr.name == attribute.name);
          }

          position = currentProduct.attributes?.length ?? 0;
        }
      }

      for (var attribute in remaining) {
        attribute.position = position;
        totalAttributes.add(attribute);
        position++;
      }

      final data = await _callWoo(
        path: '/products/${Uri.encodeComponent(trimmedId)}',
        method: 'PUT',
        body: {
          WooConstants.attributes: totalAttributes.map((attribute) => attribute.toJSON()).toList(),
        },
      );

      if (data != null) {
        AppConfig.logger.i('Atributos agregados exitosamente');
      } else {
        AppConfig.logger.i('Error al agregar atributos');
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'addAttributesToProduct');
    }
  }

  static Future<WooProduct?> getProduct(String productId) async {
    final trimmedId = productId.trim();
    if (trimmedId.isEmpty) return null;
    WooProduct? product;
    try {
      final data = await _callWoo(path: '/products/${Uri.encodeComponent(trimmedId)}');

      if (data != null) {
        product = WooProduct.fromJSON(data);
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'getProduct');
    }

    return product;
  }

  static Future<List<WooProduct>> getVariations(int productId, {int perPage = 100, int page = 1, String searchParam = ''}) async {
    if (productId <= 0) return [];
    List<WooProduct> productVariations = [];
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(1, 100);

    try {
      final data = await _callWoo(
        path: '/products/$productId/variations?page=$safePage&per_page=$safePerPage&search=${Uri.encodeComponent(searchParam)}',
      );

      if (data is List) {
        productVariations = data.map((variation) => WooProduct.fromJSON(variation)).toList();
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'getVariations');
    }

    return productVariations;
  }

  // Crear una nueva variación si no existe
  static Future<String> createVariation(String productId, String attributeName, String optionValue, {String sku = ''}) async {
    final trimmedId = productId.trim();
    if (trimmedId.isEmpty || attributeName.trim().isEmpty || optionValue.trim().isEmpty) {
      return '';
    }
    try {
      final data = await _callWoo(
        path: '/products/${Uri.encodeComponent(trimmedId)}/variations',
        method: 'POST',
        body: {
          'attributes': [
            {
              'name': attributeName,
              'option': optionValue,
            },
          ],
          'sku': Uri.encodeComponent('$trimmedId-${optionValue.toUpperCase()}'),
          'virtual': true,
          'regular_price': '0.00',
        },
      );

      if (data is Map && data['id'] != null) {
        AppConfig.logger.i('Variation was created');
        return data['id'].toString();
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'createVariation');
    }
    return '';
  }

  static Future<String> getNupaleVariationId(String itemName) async {
    WooProduct? nupaleProduct = await getProduct(AppProperties.getWooNupaleProdutId());
    if (nupaleProduct == null || nupaleProduct.id <= 0) return '';
    List<WooProduct> variations = await getVariations(nupaleProduct.id, searchParam: itemName.toLowerCase());
    String variationId = '';

    if (variations.isNotEmpty) {
      variationId = variations.first.id.toString();
    }

    if (variationId.isEmpty) {
      variationId = await createNupaleVariation(nupaleProduct, itemName);
    }

    return variationId;
  }

  static Future<String> createNupaleVariation(WooProduct nupaleProduct, String itemName) async {
    WooProductAttribute? currentAttribute = nupaleProduct.attributes?[WooAttributeConstants.itemName];
    if (currentAttribute != null) {
      currentAttribute.options.add(itemName);
      currentAttribute.variation = true;
    } else {
      currentAttribute = WooProductAttribute(
        name: WooAttributeConstants.itemName,
        options: [itemName],
        variation: true,
      );
    }
    await WooProductsAPI.addAttributesToProduct(nupaleProduct.id.toString(), [currentAttribute]);
    return WooProductsAPI.createVariation(
      nupaleProduct.id.toString(),
      WooAttributeConstants.itemName,
      itemName,
    );
  }

  static Future<String> getCaseteVariationId(String itemName) async {
    WooProduct? caseteProduct = await getProduct(AppProperties.getWooCaseteProdutId());
    if (caseteProduct == null || caseteProduct.id <= 0) return '';
    List<WooProduct> variations = await getVariations(caseteProduct.id, searchParam: itemName.toLowerCase());
    String variationId = '';

    if (variations.isNotEmpty) {
      variationId = variations.first.id.toString();
    }

    if (variationId.isEmpty) {
      variationId = await createCaseteVariation(caseteProduct, itemName);
    }

    return variationId;
  }

  /// Fetches all product categories from WooCommerce
  static Future<List<Map<String, dynamic>>> getCategories({int perPage = 100}) async {
    final safePerPage = perPage.clamp(1, 100);
    try {
      final data = await _callWoo(path: '/products/categories?per_page=$safePerPage');

      if (data is List) {
        return data
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'getCategories');
    }
    return [];
  }

  /// Creates a new product category in WooCommerce
  /// Returns the created category data with its ID
  static Future<Map<String, dynamic>?> createCategory(String name, String slug) async {
    try {
      final data = await _callWoo(
        path: '/products/categories',
        method: 'POST',
        body: {'name': name, 'slug': slug},
      );

      if (data is Map) {
        AppConfig.logger.i('Category "$name" created successfully');
        return Map<String, dynamic>.from(data);
      }
    } catch (e, st) {
      // Check if category already exists
      final errorStr = e.toString();
      if (errorStr.contains('term_exists')) {
        AppConfig.logger.i('Category "$name" already exists');
      } else {
        NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'createCategory');
      }
    }
    return null;
  }

  /// Resolves a list of category names to WooProductCategory with valid IDs.
  /// Fetches existing categories first, creates any that don't exist.
  static Future<List<Map<String, dynamic>>> resolveCategories(List<String> categoryNames, List<String> categorySlugs) async {
    if (categoryNames.isEmpty) return [];

    // Fetch all existing categories
    final existingCategories = await getCategories();
    final Map<String, int> slugToId = {};
    for (final cat in existingCategories) {
      slugToId[(cat['slug'] as String? ?? '').toLowerCase()] =
          (cat['id'] as num?)?.toInt() ?? 0;
    }

    final List<Map<String, dynamic>> resolvedCategories = [];

    for (int i = 0; i < categoryNames.length; i++) {
      final name = categoryNames[i];
      final slug = i < categorySlugs.length ? categorySlugs[i] : name.toLowerCase().replaceAll(' ', '-');

      final existingId = slugToId[slug.toLowerCase()];
      if (existingId != null && existingId > 0) {
        // Category exists — use its ID
        resolvedCategories.add({'id': existingId, 'name': name, 'slug': slug});
        AppConfig.logger.t('Category "$name" resolved to existing ID: $existingId');
      } else {
        // Category doesn't exist — create it
        final created = await createCategory(name, slug);
        if (created != null) {
          resolvedCategories.add(created);
        }
      }
    }

    return resolvedCategories;
  }

  static Future<String> createCaseteVariation(WooProduct caseteProduct, String itemName) async {
    /// Variación no existe, crear variación y luego orden
    WooProductAttribute? currentAttribute = caseteProduct.attributes?[WooAttributeConstants.itemName];
    if(currentAttribute != null) {
      currentAttribute.options.add(itemName);
      currentAttribute.variation = true;
    } else {
      currentAttribute = WooProductAttribute(
        name: WooAttributeConstants.itemName,
        options: [itemName],
        variation: true,
      );
    }
    await WooProductsAPI.addAttributesToProduct(caseteProduct.id.toString(), [currentAttribute]);
    String variationId = '';
    variationId = await WooProductsAPI.createVariation(caseteProduct.id.toString(), WooAttributeConstants.itemName, itemName);

    return variationId;
  }


}
