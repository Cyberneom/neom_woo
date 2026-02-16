import 'package:cloud_functions/cloud_functions.dart';
import 'package:neom_core/app_config.dart';

import '../../domain/model/woo_product.dart';
import '../../utils/enums/woo_product_status.dart';

class WooFirebaseFunctions {

  static Future<List<WooProduct>> getProducts({int perPage = 25, int page = 1,
    WooProductStatus status = WooProductStatus.publish, List<String> categoryIds = const []}) async {
    AppConfig.logger.d('Fetching WooProducts from Firebase Functions: page $page, perPage $perPage, status ${status.name}, categoryIds $categoryIds');
    List<WooProduct> products = [];

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getWooProducts')
          .call({
        'page': page,
        'perPage': perPage,
        'status': status.name,
        'categoryIds': categoryIds,
      });

      final List data = result.data;
      products = data.map((e) => WooProduct.fromJSON(e)).toList();

    } catch (e) {
      AppConfig.logger.e(e.toString());
    }
    return products;
  }

}
