import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:neom_core/app_config.dart';
import 'package:neom_core/app_properties.dart';
import 'package:neom_core/cloud_properties.dart';

import '../../domain/model/woo_product.dart';
import '../../domain/model/woo_product_attribute.dart';
import '../../utils/constants/woo_attribute_constants.dart';
import '../../utils/constants/woo_constants.dart';
import '../../utils/enums/woo_product_status.dart';

/// WooCommerce Products API.
/// In secure mode (web), routes through Cloud Functions wooProxy.
/// On mobile, calls WooCommerce directly with credentials.
class WooProductsAPI {

  /// Central helper for WooCommerce API calls.
  /// In secure mode: proxies through Cloud Functions.
  /// On mobile: direct HTTP with Basic auth.
  static Future<dynamic> _callWoo({
    required String path,
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (CloudProperties.isSecureMode || kIsWeb) {
      // Web: ALWAYS proxy — WooCommerce credentials are server-side only.
      return CloudProperties.wooProxy(path: path, method: method, body: body);
    }

    // Mobile only: direct call
    final url = '${AppProperties.getWooUrl()}$path';
    final credentials = base64Encode(
      utf8.encode('${CloudProperties.getWooClientKey()}:${CloudProperties.getWooClientSecret()}'),
    );
    final headers = <String, String>{
      'Authorization': 'Basic $credentials',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    };

    late http.Response response;
    switch (method.toUpperCase()) {
      case 'POST':
        response = await http.post(Uri.parse(url), headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PUT':
        response = await http.put(Uri.parse(url), headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      default:
        response = await http.get(Uri.parse(url), headers: headers);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('application/json') || response.body.trim().startsWith('<')) {
      AppConfig.logger.e('Woo response invalid (${response.statusCode})');
      throw Exception('Respuesta bloqueada por seguridad del servidor');
    }

    AppConfig.logger.e('Woo error (${response.statusCode}): ${response.body}');
    throw Exception('Error WooCommerce: ${response.statusCode}');
  }

  static Future<List<WooProduct>> getProducts({int perPage = 25, int page = 1,
    WooProductStatus status = WooProductStatus.publish, List<String> categoryIds = const []}) async {

    String path = '/products?page=$page&per_page=$perPage&status=${status.name}';
    if (categoryIds.isNotEmpty) {
      path = '$path&category=${categoryIds.join(',')}';
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
    } catch (e) {
      AppConfig.logger.e(e.toString());
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
    } catch (e) {
      AppConfig.logger.e('Exception creating WooProduct: $e');
    }
    return null;
  }

  static Future<void> addAttributesToProduct(String productId, List<WooProductAttribute> attributes, {bool isNew = false}) async {
    int position = 0;
    try {
      List<WooProductAttribute> totalAttributes = [];
      if(!isNew) {
        WooProduct? currentProduct = await getProduct(productId);
        if(currentProduct?.attributes?.isNotEmpty ?? false) {
          for(var attribute in attributes) {
            if(currentProduct!.attributes!.containsKey(attribute.name)) {
              currentProduct.attributes![attribute.name] = attribute;
              attribute.position = position;
              totalAttributes.add(attribute);
              position++;
            }
          }
          totalAttributes.addAll(currentProduct!.attributes!.values);
          for(var attribute in totalAttributes) {
            attributes.removeWhere((atr) => atr.name == attribute.name);
          }

          position = currentProduct.attributes?.length ?? 0;
        }

      }

      for(var attribute in attributes) {
        attribute.position = position;
        totalAttributes.add(attribute);
        position++;
      }

      final data = await _callWoo(
        path: '/products/$productId',
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
    } catch (e) {
      AppConfig.logger.e(e.toString());
    }
  }

  static Future<WooProduct?> getProduct(String productId) async {
    WooProduct? product;
    try {
      final data = await _callWoo(path: '/products/$productId');

      if (data != null) {
        product = WooProduct.fromJSON(data);
      }
    } catch (e) {
      AppConfig.logger.e(e.toString());
    }

    return product;
  }

  static Future<List<WooProduct>> getVariations(int productId, {int perPage = 100, int page = 1, String searchParam = ''}) async {
    List<WooProduct> productVariations = [];

    try {
      final data = await _callWoo(
        path: '/products/$productId/variations?page=$page&per_page=$perPage&search=${Uri.encodeComponent(searchParam)}',
      );

      if (data is List) {
        productVariations = data.map((variation) => WooProduct.fromJSON(variation)).toList();
      }
    } catch (e) {
      AppConfig.logger.e(e.toString());
    }

    return productVariations;
  }

  // Crear una nueva variación si no existe
  static Future<String> createVariation(String productId, String attributeName, String optionValue, {String sku = ''}) async {
    try {
      final data = await _callWoo(
        path: '/products/$productId/variations',
        method: 'POST',
        body: {
          'attributes': [
            {
              'name': attributeName,
              'option': optionValue,
            },
          ],
          'sku': Uri.encodeComponent('$productId-${optionValue.toUpperCase()}'),
          'virtual': true,
          'regular_price': '0.00',
        },
      );

      if (data != null) {
        AppConfig.logger.i('Variation was created');
        return data['id'].toString();
      }
    } catch (e) {
      AppConfig.logger.e('Error creating variation: $e');
    }
    return '';
  }

  static Future<String> getNupaleVariationId(String itemName) async {

    WooProduct? nupaleProduct = await getProduct(AppProperties.getWooNupaleProdutId());
    List<WooProduct> variations = await getVariations(nupaleProduct!.id, searchParam: itemName.toLowerCase());
    String variationId = '';

    if(variations.isNotEmpty) {
      if(variations.length == 1) {
        AppConfig.logger.d('A Single Product Variation was retrieved.');
      } else {
        AppConfig.logger.d('${variations.length} Product Variations were retrieved.');
      }
      variationId = variations.first.id.toString();
    } else {
      AppConfig.logger.d('Product Variations are empty');
    }

    if (variationId.isEmpty) {
      AppConfig.logger.d('VariationId is empty');
      variationId = await createNupaleVariation(nupaleProduct, itemName);
    }

    return variationId;
  }

  static Future<String> createNupaleVariation(WooProduct nupaleProduct, String itemName) async {
    /// Variación no existe, crear variación y luego orden
    WooProductAttribute? currentAttribute = nupaleProduct.attributes?[WooAttributeConstants.itemName];
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
    await WooProductsAPI.addAttributesToProduct(nupaleProduct.id.toString(), [currentAttribute]);
    String variationId = '';
    variationId = await WooProductsAPI.createVariation(nupaleProduct.id.toString(), WooAttributeConstants.itemName, itemName);

    return variationId;
  }

  static Future<String> getCaseteVariationId(String itemName) async {

    WooProduct? caseteProduct = await getProduct(AppProperties.getWooCaseteProdutId());
    List<WooProduct> variations = await getVariations(caseteProduct!.id, searchParam: itemName.toLowerCase());
    String variationId = '';

    if(variations.isNotEmpty) {
      if(variations.length == 1) {
        AppConfig.logger.d('A Single Product Variation was retrieved.');
      } else {
        AppConfig.logger.d('${variations.length} Product Variations were retrieved.');
      }
      variationId = variations.first.id.toString();
    } else {
      AppConfig.logger.d('Product Variations are empty');
    }

    if (variationId.isEmpty) {
      AppConfig.logger.d('VariationId is empty');
      variationId = await createCaseteVariation(caseteProduct, itemName);
    }

    return variationId;
  }

  /// Fetches all product categories from WooCommerce
  static Future<List<Map<String, dynamic>>> getCategories({int perPage = 100}) async {
    try {
      final data = await _callWoo(path: '/products/categories?per_page=$perPage');

      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      AppConfig.logger.e('Exception fetching categories: $e');
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

      if (data != null) {
        AppConfig.logger.i('Category "$name" created successfully');
        return data as Map<String, dynamic>;
      }
    } catch (e) {
      // Check if category already exists
      final errorStr = e.toString();
      if (errorStr.contains('term_exists')) {
        AppConfig.logger.i('Category "$name" already exists');
      } else {
        AppConfig.logger.e('Exception creating category "$name": $e');
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
      slugToId[(cat['slug'] as String? ?? '').toLowerCase()] = cat['id'] as int? ?? 0;
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
