import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:neom_core/app_config.dart';
import 'package:neom_core/app_properties.dart';
import 'package:neom_core/domain/model/app_user.dart';

import '../../domain/model/order/woo_billing.dart';
import '../../domain/model/order/woo_order.dart';
import '../../domain/model/order/woo_order_line_item.dart';
import '../../domain/model/order/woo_shipping.dart';
import '../../utils/enums/woo_order_status.dart';
import '../../utils/enums/woo_payment_method.dart';
import 'woo_products_api.dart';

class WooOrdersAPI {

  static Future<String> createOrder(String email, List<WooOrderLineItem> orderLineItems, {
    String? customerId, WooBilling? billingAddress, WooShipping? shippingAddress, WooOrderStatus orderStatus = WooOrderStatus.processing}) async {

    String url = '${AppProperties.getWooUrl()}/orders';
    String credentials = base64Encode(utf8.encode('${AppProperties.getWooClientKey()}:${AppProperties.getWooClientSecret()}'));


    WooOrder newOrder = WooOrder(
      paymentMethod: WooPaymentMethod.bacs.name,
      paymentMethodTitle: WooPaymentMethod.bacs.name,
      status: orderStatus.value,
      lineItems: orderLineItems,
      billing: billingAddress,
      shipping: shippingAddress,
    );

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(newOrder.toJson()),
    );

    String orderId = '';

    if (response.statusCode == 201) {
      AppConfig.logger.i('Order created successfully!');
      // Decodifica la respuesta JSON
      final responseData = jsonDecode(response.body);
      // Obtén el orderId de la respuesta
      orderId = responseData['id'].toString();
    } else {
      AppConfig.logger.e('Failed to create order: ${response.statusCode}');
      AppConfig.logger.e('Response: ${response.body}');
    }

    return orderId;
  }

  static Future<List<WooOrder>> getOrders({perPage = 25, page = 1, WooOrderStatus? status}) async {
    AppConfig.logger.i('getOrders');

    String url = '${AppProperties.getWooUrl()}/orders?page=$page&per_page=$perPage';
    if(status != null) url = '$url&status=${status.name}';
    String credentials = base64Encode(utf8.encode('${AppProperties.getWooClientKey()}:${AppProperties.getWooClientSecret()}'));

    List<WooOrder> wooOrders = [];

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> ordersJson = jsonDecode(response.body);
      AppConfig.logger.i(ordersJson.toString());
      for (var json in ordersJson) {
        WooOrder wooOrder = WooOrder.fromJson(json);
        if(json['id'].toString() == '6364') {
          AppConfig.logger.i("");
        }
        AppConfig.logger.i(json.toString());
        wooOrders.add(wooOrder);
      }
      // return ordersJson.map((orderJson) => WooOrder.fromJSON(orderJson)).toList();
    } else {
      AppConfig.logger.e('Failed to fetch orders: ${response.statusCode}');
      AppConfig.logger.e('Response: ${response.body}');
    }

    return wooOrders;
  }

  static Future<String> createSessionOrder(AppUser user, String itemName, int quantity,{bool isNupale = false}) async {
    AppConfig.logger.d('Processing Nupale Session Order of $quantity for $itemName');

    String orderId = '';
    String variationId = isNupale ? await WooProductsAPI.getNupaleVariationId(itemName) :  await WooProductsAPI.getCaseteVariationId(itemName);

    if(variationId.isNotEmpty) {
      List<WooOrderLineItem> lineItems = [
        WooOrderLineItem(
          productId: int.parse(AppProperties.getWooNupaleProdutId()),
          variationId: int.parse(variationId),
          quantity: quantity,
        )
      ];

      WooBilling billingAddress = WooBilling(
          firstName: user.name,
          lastName: user.lastName,
          address1: '',
          city: user.homeTown,
          postcode: '',
          country: user.countryCode,
          email: user.email,
          phone: user.phoneNumber);

      orderId = await createOrder(user.email, lineItems, billingAddress: billingAddress, orderStatus: WooOrderStatus.nupaleSession);

    }

    return orderId;
  }

}
