import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:neom_core/app_config.dart';
import 'package:neom_core/app_properties.dart';

import '../../domain/model/woo_product.dart';
import '../../domain/model/woo_product_attribute.dart';
import '../../utils/constants/woo_attribute_constants.dart';
import '../../utils/constants/woo_constants.dart';
import '../../utils/enums/woo_product_status.dart';

class WooProductsAPI {

  static Future<List<WooProduct>> getProducts({int perPage = 25, int page = 1,
    WooProductStatus status = WooProductStatus.publish, List<String> categoryIds = const []}) async {
    
    String url = '${AppProperties.getWooUrl()}/products?page=$page&per_page=$perPage&status=${status.name}';
    if (categoryIds.isNotEmpty) {
      String categoryParam = categoryIds.join(','); // Une los IDs con comas
      url = '$url&category=$categoryParam';
    }
    String credentials = base64Encode(utf8.encode('${AppProperties.getWooClientKey()}:${AppProperties.getWooClientSecret()}'));
    List<WooProduct> products = [];

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Basic $credentials'
        },
      );

      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        for(var item in data.asMap().values) {
          WooProduct product = WooProduct.fromJSON(item);
          AppConfig.logger.t('Product ${product.id} with name ${product.name}');
          products.add(product);
        }
        
        AppConfig.logger.d('${products.length} Products retrieved');
      } else {
        AppConfig.logger.w(response.body.toString());
        jsonDecode(response.body);
        throw Exception('Error al cargar productos');
      }
    } catch (e) {
      AppConfig.logger.e(e.toString());
    }
    return products;
  }

  static Future<void> createProduct(WooProduct product) async {

    String url = '${AppProperties.getWooUrl()}/products';
    String credentials = base64Encode(utf8.encode('${AppProperties.getWooClientKey()}:${AppProperties.getWooClientSecret()}'));

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(product.toJSON()),
    );

    if (response.statusCode == 201) {
      AppConfig.logger.i('Producto creado correctamente');
    } else {
      AppConfig.logger.i('Error al crear el producto: ${response.body}');
    }
  }

  static Future<void> addAttributesToProduct(String productId, List<WooProductAttribute> attributes, {bool isNew = false}) async {

    String url = '${AppProperties.getWooUrl()}/products';
    String credentials = base64Encode(utf8.encode('${AppProperties.getWooClientKey()}:${AppProperties.getWooClientSecret()}'));
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
      final response = await http.put(
        Uri.parse('$url/$productId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $credentials',
        },
        body: jsonEncode({
          WooConstants.attributes: totalAttributes.map((attribute) => attribute.toJSON()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        AppConfig.logger.i('Atributos agregados exitosamente');
      } else {
        AppConfig.logger.i('Error al agregar atributos: ${response.statusCode}');
      }
    } catch (e) {
      AppConfig.logger.e(e.toString());
    }
  }

  static Future<WooProduct?> getProduct(String productId) async {

    String url = '${AppProperties.getWooUrl()}/products';
    String credentials = base64Encode(utf8.encode('${AppProperties.getWooClientKey()}:${AppProperties.getWooClientSecret()}'));

    WooProduct? product;
    try {
      final response = await http.get(
        Uri.parse('$url/$productId'),
        headers: {
          'Authorization': 'Basic $credentials',
        },
      );

      if (response.statusCode == 200) {
        product = WooProduct.fromJSON(jsonDecode(response.body));
      } else {
        AppConfig.logger.i('Error al obtener atributos: ${response.statusCode}');
      }
    } catch (e) {
      AppConfig.logger.e(e.toString());
    }

    return product;
  }

  static Future<List<WooProduct>> getVariations(int productId, {int perPage = 100, int page = 1, String searchParam = ''}) async {

    String url = '${AppProperties.getWooUrl()}/products';
    String credentials = base64Encode(utf8.encode('${AppProperties.getWooClientKey()}:${AppProperties.getWooClientSecret()}'));
    List<WooProduct> productVariations = [];

    final response = await http.get(
      Uri.parse('$url/$productId/variations?page=$page&per_page=$perPage&search=${Uri.encodeComponent(searchParam)}'),
      headers: {
        'Authorization': 'Basic $credentials',
      },
    );

    if (response.statusCode == 200) {
      List variations = json.decode(response.body);
      productVariations = variations.map((variation) => WooProduct.fromJSON(variation)).toList();
    }

    return productVariations;
  }

  // Crear una nueva variación si no existe
  static Future<String> createVariation(String productId, String attributeName, String optionValue, {String sku = ''}) async {

    String url = '${AppProperties.getWooUrl()}/products';
    String credentials = base64Encode(utf8.encode('${AppProperties.getWooClientKey()}:${AppProperties.getWooClientSecret()}'));

    final response = await http.post(
      Uri.parse('$url/$productId/variations'),
      headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'attributes': [
          {
            'name': attributeName,
            'option': optionValue,
          },
        ],
        'sku': Uri.encodeComponent('$productId-${optionValue.toUpperCase()}'),
        'virtual': true,
        'regular_price': '0.00', // Establece el precio si es necesario
      }),
    );

    if (response.statusCode == 201) {
      AppConfig.logger.i('Variation was created');
      final variation = json.decode(response.body);
      return variation['id'].toString();
    } else {
      AppConfig.logger.e('Error creating variation: ${response.statusCode}');
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
