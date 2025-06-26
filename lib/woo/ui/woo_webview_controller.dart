import 'dart:core';

import 'package:get/get.dart';
import 'package:neom_commons/commons/ui/theme/app_color.dart';
import 'package:neom_commons/commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/commons/utils/external_utilities.dart';
import 'package:neom_core/core/app_config.dart';
import 'package:neom_core/core/data/firestore/order_firestore.dart';
import 'package:neom_core/core/data/firestore/transaction_firestore.dart';
import 'package:neom_core/core/data/implementations/user_controller.dart';
import 'package:neom_core/core/domain/model/app_order.dart';
import 'package:neom_core/core/domain/model/app_product.dart';
import 'package:neom_core/core/domain/model/app_profile.dart';
import 'package:neom_core/core/domain/model/app_release_item.dart';
import 'package:neom_core/core/domain/model/app_transaction.dart';
import 'package:neom_core/core/utils/enums/app_currency.dart';
import 'package:neom_core/core/utils/enums/transaction_status.dart';
import 'package:neom_core/core/utils/enums/transaction_type.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/use_cases/woo_webview_service.dart';
import '../utils/constants/woo_constants.dart';

class WooWebViewController extends GetxController implements WooWebViewService {

  final userController = Get.find<UserController>();

  AppProfile profile = AppProfile();
  AppReleaseItem releaseItem = AppReleaseItem();

  WebViewController webViewController = WebViewController();
  bool isLoading = true;
  bool canPopWebView = false;

  bool clearCache = true;
  bool clearCookies = true;
  String url = '';
  String loadingSubtitle = 'Cargando plataforma de compra';

  bool isDigital = true;

  @override
  void onInit() async {
    super.onInit();
    AppConfig.logger.i("WooWebView Controller Init");


    if(clearCache) webViewController.clearCache();
    if(clearCookies) await ExternalUtilities.clearWebViewCookies();

    try {
      profile = userController.user.profiles.first;

      if(Get.arguments != null && Get.arguments.isNotEmpty) {
        if (Get.arguments[0] is String) {
          url = Get.arguments[0];
        }

        if(Get.arguments[1] != null && Get.arguments[1] is AppReleaseItem) {
          releaseItem = Get.arguments[1];
          isDigital = releaseItem.physicalPrice == null;
        }
      }

      webViewController.setBackgroundColor(AppColor.main50);
      webViewController.loadRequest(Uri.parse(url));
    } catch (e) {
      AppConfig.logger.e(e.toString());
    }

  }

  @override
  void onReady() async {
    super.onReady();

    webViewController.setJavaScriptMode(JavaScriptMode.unrestricted);
    webViewController.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (String url) {
          isLoading = true;
          if(url.contains('carrito')) {
            loadingSubtitle = 'Dirigiendo a Carrito';
          } else if(url.contains(WooConstants.checkout)) {
            loadingSubtitle = 'Dirigiendo a Detalles de Facturación y Envío';
          } else if(url.contains(WooConstants.ordenRecibida)) {
            loadingSubtitle = '¡Orden creada satisfactoriamente!\nDirigiendo a detalles del pedido';
          }

          update([AppPageIdConstants.wooWebView]);
        },
        onPageFinished: (String url) async {
          try {
            await webViewController.runJavaScript(
                "document.getElementById('masthead').style.display = 'none';"
                "document.querySelector('.cross-sells').style.display = 'none';"
                "document.querySelector('.actions').style.display = 'none';"
                "document.querySelector('.product-quantity').style.display = 'none';"
            );

            if(url.contains(WooConstants.checkout)) {
              await webViewController.runJavaScript(
                "document.getElementById('billing_email').value = '${userController.user.email}';"

              );
            }
            isLoading = false;
            update([AppPageIdConstants.wooWebView]);
          } catch(e) {
            AppConfig.logger.e(e.toString());
          }

        },
        onHttpError: (HttpResponseError error) {
          AppConfig.logger.e(error.toString());
        },
        onWebResourceError: (WebResourceError error) {
          AppConfig.logger.e(error.toString());
        },
        onNavigationRequest: (NavigationRequest request) async {
          AppConfig.logger.d('Navigation Request for URL: ${request.url}');
          if (request.url == url || WooConstants.allowedUrls.any((allowedUrl) => request.url.contains(allowedUrl))) {
            canPopWebView = false;
            update([AppPageIdConstants.wooWebView]);

            if(request.url.contains(WooConstants.ordenRecibida) && !request.url.contains(WooConstants.paypal)) {
              url = request.url;
              String wooOrderId = await createInternalOrder();
              userController.addOrderId(wooOrderId);
              if(isDigital) userController.addBoughtItem(releaseItem.id);
            }

            AppConfig.logger.d('Navigating URL: ${request.url}');
            return NavigationDecision.navigate;
          } else {
            // Navigator.pop(context);
            AppConfig.logger.d('Preventing URL: ${request.url}');
            return NavigationDecision.prevent;
          }
        },
      ),
    );

    // update([AppPageIdConstants.wooWebView]);
  }

  @override
  void setCanPopWebView(bool canPop) {
    canPopWebView = canPop;
    update([AppPageIdConstants.wooWebView]);
  }

  @override
  Future<String> createInternalOrder() async {

    String orderId = '';
    String orderKey ='' ;

    List<String> parts = url.split('/');
    orderId = parts[parts.indexOf(WooConstants.ordenRecibida) + 1];

    String queryString = url.split('?').last;
    List<String> queryParams = queryString.split('&');
    for (var param in queryParams) {
      if (param.startsWith('key=')) {
        orderKey = param.split('=').last;
        break;
      }
    }

    if(orderId.isNotEmpty) {
      AppOrder order = AppOrder(
        id: orderId,
        description: releaseItem.name,
        url: url,
        createdTime: DateTime.now().millisecondsSinceEpoch,
        customerEmail: userController.user.email,
        product: AppProduct.fromReleaseItem(releaseItem),
        invoiceIds: [url],
      );

      String successfulOrderId = await OrderFirestore().insert(order);
      if(successfulOrderId.isNotEmpty) {
        AppTransaction transaction = AppTransaction(
            type: TransactionType.purchase,
            orderId: orderId,
            createdTime: DateTime.now().millisecondsSinceEpoch,
            senderId: userController.user.email,
            status: TransactionStatus.completed,
            amount: releaseItem.salePrice?.amount ?? 0,
            currency: releaseItem.salePrice?.currency ?? AppCurrency.appCoin,
            secretKey: orderKey,
        );

        TransactionFirestore().insert(transaction);
      }

    }

    return orderId;
  }

}
