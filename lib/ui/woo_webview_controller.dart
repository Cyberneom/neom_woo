import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, kIsWeb;
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/utils/external_utilities.dart';
import 'package:neom_core/app_config.dart';
import 'package:neom_core/app_properties.dart';
import 'package:neom_core/data/firestore/order_firestore.dart';
import 'package:neom_core/data/firestore/transaction_firestore.dart';
import 'package:neom_core/domain/model/app_order.dart';
import 'package:neom_core/domain/model/app_product.dart';
import 'package:neom_core/domain/model/app_profile.dart';
import 'package:neom_core/domain/model/app_release_item.dart';
import 'package:neom_core/domain/model/app_transaction.dart';
import 'package:neom_core/domain/use_cases/user_service.dart';
import 'package:neom_core/utils/enums/app_currency.dart';
import 'package:neom_core/utils/enums/transaction_status.dart';
import 'package:neom_core/utils/enums/transaction_type.dart';
import 'package:neom_core/utils/neom_error_logger.dart';
import 'package:sint/sint.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/use_cases/woo_webview_service.dart';
import '../utils/constants/woo_constants.dart';
import '../utils/woo_security_utils.dart';

class WooWebViewController extends SintController implements WooWebViewService {
  final String? _siteUrlOverride;
  final bool? _forceExternalBrowser;

  WooWebViewController({
    String? siteUrlOverride,
    bool? forceExternalBrowser,
  })  : _siteUrlOverride = siteUrlOverride,
        _forceExternalBrowser = forceExternalBrowser;

  /// True on Web and Desktop platforms (`macOS`/`Windows`/`Linux`) where
  /// `webview_flutter` lacks an embedded platform implementation and throws
  /// `UnimplementedError`.
  static bool shouldUseExternalBrowser({
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
  }) =>
      WooSecurityUtils.shouldUseExternalBrowser(
        isWeb: isWeb,
        platform: platform,
      );

  bool get usesExternalBrowser =>
      _forceExternalBrowser ?? shouldUseExternalBrowser();

  UserService? get _userService =>
      Sint.isRegistered<UserService>() ? Sint.find<UserService>() : null;
  UserService get userServiceImpl => Sint.find<UserService>();

  AppProfile profile = AppProfile();
  AppReleaseItem releaseItem = AppReleaseItem();

  WebViewController? _webViewController;
  WebViewController? get maybeWebViewController => _webViewController;
  WebViewController get webViewController =>
      _webViewController ??= WebViewController();
  set webViewController(WebViewController value) => _webViewController = value;

  final Set<String> _createdOrderIds = <String>{};
  bool _creatingOrder = false;

  bool isLoading = true;
  bool canPopWebView = false;
  bool launchedExternally = false;

  bool clearCache = true;
  bool clearCookies = true;
  String url = '';
  String loadingSubtitle = 'Cargando plataforma de compra';

  bool isDigital = true;

  String get _configuredSiteHost {
    final raw = (_siteUrlOverride ?? AppProperties.getSiteUrl()).trim();
    if (raw.isEmpty) return '';
    return Uri.tryParse(raw)?.host.toLowerCase().trim() ?? '';
  }

  @override
  void onInit() async {
    super.onInit();
    AppConfig.logger.i("WooWebView Controller Init");

    try {
      const String userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

      final us = _userService;
      if (us != null) {
        profile = us.user.profiles.isNotEmpty
            ? us.user.profiles.first
            : us.profile;
      }

      final args = Sint.arguments;
      if (args is List && args.isNotEmpty) {
        if (args[0] is String) {
          url = (args[0] as String).trim();
        }

        if (args.length > 1 && args[1] is AppReleaseItem) {
          releaseItem = args[1] as AppReleaseItem;
          isDigital = releaseItem.physicalPrice == null;
        }
      }

      if (url.isEmpty || !isAllowedNavigationUrl(url)) {
        AppConfig.logger.w('WooWebView blocked invalid initial URL');
        isLoading = false;
        update([AppPageIdConstants.wooWebView]);
        return;
      }

      if (usesExternalBrowser) {
        isLoading = false;
        canPopWebView = true;
        launchedExternally = true;
        update([AppPageIdConstants.wooWebView]);
        ExternalUtilities.launchURL(url, openInApp: false);
        return;
      }

      webViewController.setBackgroundColor(AppColor.surfaceCard);
      await webViewController.loadRequest(
        Uri.parse(url),
        headers: {'User-Agent': userAgent},
      );

      if (clearCache) webViewController.clearCache();
      if (clearCookies) webViewController.clearLocalStorage();
      if (clearCookies) await ExternalUtilities.clearWebViewCookies();
    } catch (e, st) {
      isLoading = false;
      update([AppPageIdConstants.wooWebView]);
      NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'onInit');
    }
  }

  @override
  void onReady() async {
    super.onReady();
    if (usesExternalBrowser) return;

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

            if (isAllowedSiteUrl(url) && url.contains(WooConstants.checkout)) {
              final email = _userService?.user.email ?? '';
              if (email.isNotEmpty) {
                await webViewController.runJavaScript(
                  "document.getElementById('billing_email').value = ${jsonEncode(email)};",
                );
              }
            }
            isLoading = false;
            update([AppPageIdConstants.wooWebView]);
          } catch (e, st) {
            NeomErrorLogger.recordError(e, st, module: 'neom_woo', operation: 'onPageFinished');
          }
        },
        onHttpError: (HttpResponseError error) {
          AppConfig.logger.e(error.toString());
        },
        onWebResourceError: (WebResourceError error) {
          AppConfig.logger.e(error.toString());
        },
        onNavigationRequest: (NavigationRequest request) async {
          AppConfig.logger.d('Navigation Request received');
          if (isAllowedNavigationUrl(request.url)) {
            canPopWebView = false;
            update([AppPageIdConstants.wooWebView]);

            if (isTrustedOrderConfirmationUrl(request.url)) {
              url = request.url;
              String wooOrderId = await createInternalOrder();
              final us = _userService;
              if (wooOrderId.isNotEmpty && us != null) {
                us.addOrderId(wooOrderId);
                if (isDigital && releaseItem.id.isNotEmpty) {
                  us.addBoughtItem(releaseItem.id);
                }
              }
            } else if (request.url.contains(WooConstants.captcha)) {
              webViewController.setBackgroundColor(AppColor.white);
            }

            return NavigationDecision.navigate;
          } else {
            AppConfig.logger.w('Preventing untrusted WooWebView URL');
            return NavigationDecision.prevent;
          }
        },
      ),
    );
  }

  @override
  void setCanPopWebView(bool canPop) {
    canPopWebView = canPop;
    update([AppPageIdConstants.wooWebView]);
  }

  /// True only when [rawUrl] is an HTTPS URL on the configured store domain
  /// with zero control or Bidi spoofing characters.
  bool isAllowedSiteUrl(String rawUrl) =>
      WooSecurityUtils.isAllowedSiteUrl(rawUrl, siteHost: _configuredSiteHost);

  /// Strict HTTPS host-based navigation gate: allows only the configured store
  /// host or trusted external payment/captcha provider domains.
  bool isAllowedNavigationUrl(String rawUrl) =>
      WooSecurityUtils.isAllowedNavigationUrl(
        rawUrl,
        siteHost: _configuredSiteHost,
      );

  /// True only when [rawUrl] is an order-confirmation page on the store's own
  /// host with a valid order ID segment (prevents external URL order spoofing).
  bool isTrustedOrderConfirmationUrl(String rawUrl) {
    if (!isAllowedSiteUrl(rawUrl)) return false;
    final parsed = parseOrderConfirmation(rawUrl);
    return parsed.$1.isNotEmpty;
  }

  /// Safely extracts `(orderId, orderKey)` from a WooCommerce `orden-recibida` URL.
  static (String, String) parseOrderConfirmation(String rawUrl) =>
      WooSecurityUtils.parseOrderConfirmation(rawUrl);

  static String sanitizeOrderDescription(String raw) =>
      WooSecurityUtils.sanitizeOrderDescription(raw);

  @override
  Future<String> createInternalOrder() async {
    if (_creatingOrder) return '';
    if (!isAllowedSiteUrl(url)) return '';
    final (orderId, orderKey) = parseOrderConfirmation(url);
    if (orderId.isEmpty) return '';

    // Idempotency guard against duplicate WebView redirects/reloads on orden-recibida.
    if (_createdOrderIds.contains(orderId)) {
      return '';
    }

    _creatingOrder = true;
    try {
      final customerEmail = _userService?.user.email ?? '';
      final rawSaleAmount = releaseItem.salePrice?.amount ?? 0;
      final safeAmount =
          (rawSaleAmount.isFinite && rawSaleAmount >= 0) ? rawSaleAmount : 0.0;
      AppOrder order = AppOrder(
        id: orderId,
        description: sanitizeOrderDescription(releaseItem.name),
        url: url,
        createdTime: DateTime.now().millisecondsSinceEpoch,
        customerEmail: customerEmail,
        product: AppProduct.fromReleaseItem(releaseItem),
        invoiceIds: [url],
      );

      String successfulOrderId = await OrderFirestore().insert(order);
      if (successfulOrderId.isNotEmpty) {
        _createdOrderIds.add(orderId);
        AppTransaction transaction = AppTransaction(
          type: TransactionType.purchase,
          orderId: orderId,
          createdTime: DateTime.now().millisecondsSinceEpoch,
          senderId: customerEmail,
          status: TransactionStatus.completed,
          amount: safeAmount,
          currency: releaseItem.salePrice?.currency ?? AppCurrency.appCoin,
          secretKey: orderKey,
        );

        await TransactionFirestore().insert(transaction);
      }
      return orderId;
    } finally {
      _creatingOrder = false;
    }
  }
}
