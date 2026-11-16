import 'package:flutter/material.dart';
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_commons/ui/widgets/app_circular_progress_indicator.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:neom_commons/utils/external_utilities.dart';
import 'package:sint/sint.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'woo_webview_controller.dart';

class WooWebViewPage extends StatelessWidget {
  const WooWebViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SintBuilder<WooWebViewController>(
      id: AppPageIdConstants.wooWebView,
      init: WooWebViewController(),
      builder: (controller) {
        final wv = controller.maybeWebViewController;
        final isExternal = controller.usesExternalBrowser || wv == null;
        return Scaffold(
          backgroundColor: AppColor.scaffold,
          body: SafeArea(
            child: PopScope(
              canPop: isExternal || controller.canPopWebView,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;
                if (!isExternal && await wv.canGoBack()) {
                  await wv.goBack();
                } else {
                  controller.setCanPopWebView(true);
                  if (context.mounted) {
                    Sint.maybePop();
                  }
                }
              },
              child: controller.isLoading
                  ? AppCircularProgressIndicator(
                      subtitle: controller.loadingSubtitle,
                    )
                  : isExternal
                      ? _buildExternalCheckoutFallback(context, controller)
                      : WebViewWidget(controller: wv),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExternalCheckoutFallback(
    BuildContext context,
    WooWebViewController controller,
  ) {
    final validUrl =
        controller.url.isNotEmpty && controller.isAllowedNavigationUrl(controller.url);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.open_in_browser_rounded,
                size: 56,
                color: Colors.white70,
              ),
              const SizedBox(height: 16),
              Text(
                validUrl
                    ? 'La plataforma de compra se abrió de forma segura en tu navegador.'
                    : 'No fue posible abrir el enlace de compra.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              if (validUrl)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ElevatedButton.icon(
                    onPressed: () => ExternalUtilities.launchURL(
                      controller.url,
                      openInApp: false,
                    ),
                    icon: const Icon(Icons.launch_rounded, size: 18),
                    label: const Text('Abrir nuevamente en el navegador'),
                  ),
                ),
              TextButton(
                onPressed: () => Sint.maybePop(),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
