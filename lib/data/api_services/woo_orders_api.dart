import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:neom_core/app_config.dart';
import 'package:neom_core/utils/neom_error_logger.dart';
import 'package:neom_core/app_properties.dart';
import 'package:neom_core/cloud_properties.dart';
import 'package:neom_core/domain/model/app_user.dart';

import '../../domain/model/order/woo_billing.dart';
import '../../domain/model/order/woo_order.dart';
import '../../domain/model/order/woo_order_line_item.dart';
import '../../domain/model/order/woo_shipping.dart';
import '../../utils/enums/woo_order_status.dart';
import '../../utils/enums/woo_payment_method.dart';
import 'woo_products_api.dart';

/// WooCommerce Orders API.
/// In secure mode (web), routes through Cloud Functions wooProxy.
/// On mobile, calls WooCommerce directly with credentials.
class WooOrdersAPI {

  /// Central helper for WooCommerce order calls.
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
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    };

    late http.Response response;
    switch (method.toUpperCase()) {
      case 'POST':
        response = await http.post(Uri.parse(url), headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      default:
        response = await http.get(Uri.parse(url), headers: headers);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }

    AppConfig.logger.e('Woo order error (${response.statusCode}): ${response.body}');
    return null;
  }

  static Future<String> createOrder(String email, List<WooOrderLineItem> orderLineItems, {
    String? customerId, WooBilling? billingAddress, WooShipping? shippingAddress, WooOrderStatus orderStatus = WooOrderStatus.processing}) async {

    WooOrder newOrder = WooOrder(
      paymentMethod: WooPaymentMethod.bacs.name,
      paymentMethodTitle: WooPaymentMethod.bacs.name,
      status: orderStatus.value,
      lineItems: orderLineItems,
      billing: billingAddress,
      shipping: shippingAddress,
    );

    String orderId = '';

    try {
      final responseData = await _callWoo(path: '/orders', method: 'POST', body: newOrder.toJson());

      if (responseData != null) {
        AppConfig.logger.i('Order created successfully!');
        orderId = responseData['id'].toString();
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'createOrder');
    }

    return orderId;
  }

  static Future<List<WooOrder>> getOrders({perPage = 25, page = 1, WooOrderStatus? status}) async {
    AppConfig.logger.i('getOrders');

    String path = '/orders?page=$page&per_page=$perPage';
    if(status != null) path = '$path&status=${status.name}';

    List<WooOrder> wooOrders = [];

    try {
      final data = await _callWoo(path: path);

      if (data is List) {
        for (var json in data) {
          WooOrder wooOrder = WooOrder.fromJson(json);
          wooOrders.add(wooOrder);
        }
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'getOrders');
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
