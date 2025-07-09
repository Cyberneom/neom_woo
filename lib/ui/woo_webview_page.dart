import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:neom_commons/ui/theme/app_color.dart';
import 'package:neom_commons/ui/widgets/app_circular_progress_indicator.dart';
import 'package:neom_commons/utils/constants/app_page_id_constants.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'woo_webview_controller.dart';

class WooWebViewPage extends StatelessWidget {

  const WooWebViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<WooWebViewController>(
      id: AppPageIdConstants.wooWebView,
      init: WooWebViewController(),
      builder: (_) => Scaffold(
        backgroundColor: AppColor.main50,
        body: SafeArea(
          child: WillPopScope(
            onWillPop: () async {
              if(await _.webViewController.canGoBack()) {
                await _.webViewController.goBack();
                return Future.value(false);
              } else {
                _.setCanPopWebView(true);
                return Future.value(false);
              }
            },
            child: _.isLoading ? AppCircularProgressIndicator(subtitle: _.loadingSubtitle) : WebViewWidget(
              controller: _.webViewController,
            ),
          ),
        ),
      )
    );
  }

}
