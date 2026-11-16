import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:neom_core/app_config.dart';
import 'package:neom_core/app_properties.dart';
import 'package:neom_core/cloud_properties.dart';
import 'package:neom_core/domain/model/app_user.dart';
import 'package:neom_core/utils/neom_error_logger.dart';

import '../../domain/model/order/woo_billing.dart';
import '../../domain/model/order/woo_order.dart';
import '../../domain/model/order/woo_order_line_item.dart';
import '../../domain/model/order/woo_shipping.dart';
import '../../utils/enums/woo_order_status.dart';
import '../../utils/enums/woo_payment_method.dart';
import '../../utils/woo_security_utils.dart';
import 'woo_products_api.dart';

/// WooCommerce Orders API.
/// In secure mode (web), routes through Cloud Functions wooProxy.
/// On mobile, calls WooCommerce directly with credentials.
class WooOrdersAPI {
  static const Duration _httpTimeout = Duration(seconds: 20);
  static const int maxResponseBytes = 5 * 1024 * 1024;

  /// Central helper for WooCommerce order calls.
  static Future<dynamic> _callWoo({
    required String path,
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (!WooSecurityUtils.isSafeApiPath(path)) {
      AppConfig.logger.w('WooOrdersAPI: rejected unsafe API path "$path"');
      return null;
    }
    if (CloudProperties.isSecureMode || kIsWeb) {
      // Web: ALWAYS proxy — WooCommerce credentials are server-side only.
      return CloudProperties.wooProxy(path: path, method: method, body: body);
    }

    final baseUrl = AppProperties.getWooUrl().trim();
    if (baseUrl.isEmpty) {
      AppConfig.logger.w('WooOrdersAPI: empty Woo base URL');
      return null;
    }

    final fullUrl = '$baseUrl$path';
    if (!WooSecurityUtils.isSafePublicHttpsUrl(fullUrl)) {
      AppConfig.logger.w('WooOrdersAPI: rejected non-public or non-HTTPS Woo URL');
      return null;
    }

    // Mobile only: direct call
    final uri = Uri.parse(fullUrl);
    final credentials = base64Encode(
      utf8.encode('${CloudProperties.getWooClientKey()}:${CloudProperties.getWooClientSecret()}'),
    );
    final headers = <String, String>{
      'Authorization': 'Basic $credentials',
      'Content-Type': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    };

    final upperMethod = method.toUpperCase();
    final encodedBody =
        (upperMethod == 'POST' && body != null) ? jsonEncode(body) : null;
    final client = http.Client();
    late final int statusCode;
    late final List<int> bodyBytes;
    try {
      final request = http.Request(
        upperMethod == 'POST' ? 'POST' : 'GET',
        uri,
      )
        ..followRedirects = false
        ..headers.addAll(headers);
      if (encodedBody != null) {
        request.body = encodedBody;
      }
      final streamed = await client.send(request).timeout(_httpTimeout);
      statusCode = streamed.statusCode;
      if (streamed.contentLength != null &&
          streamed.contentLength! > maxResponseBytes) {
        AppConfig.logger.e('Woo order response exceeded $maxResponseBytes bytes');
        return null;
      }
      final chunks = <int>[];
      await for (final chunk in streamed.stream.timeout(_httpTimeout)) {
        chunks.addAll(chunk);
        if (chunks.length > maxResponseBytes) {
          AppConfig.logger.e('Woo order response exceeded $maxResponseBytes bytes');
          return null;
        }
      }
      bodyBytes = chunks;
    } finally {
      client.close();
    }

    if (statusCode >= 200 && statusCode < 300) {
      return jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
    }

    AppConfig.logger.e(
      'Woo order error ($statusCode, ${bodyBytes.length} bytes)',
    );
    return null;
  }

  static Future<String> createOrder(String email, List<WooOrderLineItem> orderLineItems, {
    String? customerId, WooBilling? billingAddress, WooShipping? shippingAddress, WooOrderStatus orderStatus = WooOrderStatus.processing}) async {
    if (orderLineItems.isEmpty) return '';

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

      if (responseData is Map && responseData['id'] != null) {
        AppConfig.logger.i('Order created successfully!');
        orderId = responseData['id'].toString();
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'createOrder');
    }

    return orderId;
  }

  static Future<List<WooOrder>> getOrders({int perPage = 25, int page = 1, WooOrderStatus? status}) async {
    AppConfig.logger.i('getOrders');

    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(1, 100);
    String path = '/orders?page=$safePage&per_page=$safePerPage';
    if (status != null) path = '$path&status=${Uri.encodeComponent(status.name)}';

    List<WooOrder> wooOrders = [];

    try {
      final data = await _callWoo(path: path);

      if (data is List) {
        for (var json in data) {
          if (json is Map) {
            WooOrder wooOrder = WooOrder.fromJson(Map<String, dynamic>.from(json));
            wooOrders.add(wooOrder);
          }
        }
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'getOrders');
    }

    return wooOrders;
  }

  static Future<String> createSessionOrder(AppUser user, String itemName, int quantity, {bool isNupale = false}) async {
    final trimmedName = itemName.trim();
    if (trimmedName.isEmpty || quantity <= 0) return '';
    AppConfig.logger.d('Processing Session Order of $quantity for $trimmedName');

    String orderId = '';
    String variationId = isNupale
        ? await WooProductsAPI.getNupaleVariationId(trimmedName)
        : await WooProductsAPI.getCaseteVariationId(trimmedName);

    final rawProductId = isNupale
        ? AppProperties.getWooNupaleProdutId()
        : AppProperties.getWooCaseteProdutId();
    final parsedProductId = int.tryParse(rawProductId.trim());
    final parsedVariationId = int.tryParse(variationId.trim());

    if (parsedProductId != null &&
        parsedProductId > 0 &&
        parsedVariationId != null &&
        parsedVariationId > 0) {
      List<WooOrderLineItem> lineItems = [
        WooOrderLineItem(
          productId: parsedProductId,
          variationId: parsedVariationId,
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

      orderId = await createOrder(
        user.email,
        lineItems,
        billingAddress: billingAddress,
        orderStatus: WooOrderStatus.nupaleSession,
      );
    }

    return orderId;
  }
}
