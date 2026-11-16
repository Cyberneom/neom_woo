import 'package:cloud_functions/cloud_functions.dart';
import 'package:neom_core/app_config.dart';
import 'package:neom_core/utils/neom_error_logger.dart';

import '../../domain/model/woo_product.dart';
import '../../utils/enums/woo_product_status.dart';

class WooFirebaseFunctions {
  static const Duration _callableTimeout = Duration(seconds: 20);

  static Future<List<WooProduct>> getProducts({
    int perPage = 25,
    int page = 1,
    WooProductStatus status = WooProductStatus.publish,
    List<String> categoryIds = const [],
  }) async {
    final safePage = page.clamp(1, 1000);
    final safePerPage = perPage.clamp(1, 100);
    final safeCategoryIds = categoryIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.length <= 64)
        .take(50)
        .toList(growable: false);

    AppConfig.logger.d(
      'Fetching WooProducts from Firebase Functions: page $safePage, '
      'perPage $safePerPage, status ${status.name}, '
      'categoryIds ${safeCategoryIds.length}',
    );
    List<WooProduct> products = [];

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getWooProducts')
          .call({
            'page': safePage,
            'perPage': safePerPage,
            'status': status.name,
            'categoryIds': safeCategoryIds,
          })
          .timeout(_callableTimeout);

      final raw = result.data;
      if (raw is List) {
        products = raw
            .whereType<Map>()
            .map((e) => WooProduct.fromJSON(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e, st) {
      NeomErrorLogger.recordError(
        e,
        st,
        module: 'neom_woo',
        operation: 'getProducts',
      );
    }
    return products;
  }
}
