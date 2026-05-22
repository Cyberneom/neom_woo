import 'package:neom_core/ui/deferred_loader.dart';
import 'package:neom_core/utils/constants/app_route_constants.dart';
import 'package:sint/sint.dart';

import 'ui/woo_webview_page.dart' deferred as wooWebView;

class WooRoutes {

  static final List<SintPage<dynamic>> routes = [
    SintPage(
        name: AppRouteConstants.wooWebView,
        page: () => DeferredLoader(wooWebView.loadLibrary, () => wooWebView.WooWebViewPage()),
        transition: Transition.zoom
    ),
  ];

}
