import 'package:neom_core/utils/constants/app_route_constants.dart';
import 'package:sint/sint.dart';

import 'ui/woo_webview_page.dart';

class WooRoutes {

  static final List<SintPage<dynamic>> routes = [
    SintPage(
        name: AppRouteConstants.wooWebView,
        page: () => const WooWebViewPage(),
        transition: Transition.zoom
    ),
  ];

}
