import 'dart:async';
import 'dart:math';

import 'package:enum_to_string/enum_to_string.dart';
import 'package:get/get.dart';
import 'package:neom_commons/utils/text_utilities.dart';
import 'package:neom_core/app_config.dart';
import 'package:neom_core/domain/model/app_release_item.dart';
import 'package:neom_core/domain/use_cases/woo_gateway_service.dart';
import 'package:neom_core/utils/enums/media_item_type.dart';
import 'package:neom_core/utils/enums/product_type.dart';
import 'package:neom_core/utils/enums/release_type.dart';

import '../../domain/model/woo_product.dart';
import '../../utils/constants/woo_attribute_constants.dart';
import '../../utils/mappers/woo_product_mapper.dart';
import '../api_services/woo_products_api.dart';
import '../functions/woo_firebase_functions.dart';

class WooGatewayController implements WooGatewayService {

  @override
  Future<void> createProductFromReleaseItem(AppReleaseItem releaseItem, {fromFunctions = false}) {
    // TODO: implement createProductFromReleaseItem
    throw UnimplementedError();
  }

  @override
  Future<AppReleaseItem?> getProductAsReleaseItem(String productId, {fromFunctions = false}) {
    // TODO: implement getProductAsReleaseItem
    throw UnimplementedError();
  }

  @override
  Future<Map<ProductType, Map<int, AppReleaseItem>>> getProductsAsReleaseItems({int perPage = 25, int page = 1, List<String> categoryIds = const [], fromFunctions = false}) async {

    ProductType productType = ProductType.digital;

    List<WooProduct> wooProducts = [];
    if(fromFunctions) {
      wooProducts = await WooFirebaseFunctions.getProducts(perPage: perPage, categoryIds: categoryIds);
    } else {
      wooProducts = await WooProductsAPI.getProducts(perPage: perPage, categoryIds: categoryIds);
    }

    Map<ProductType, Map<int, AppReleaseItem>> categorizedReleaseItems = {
      ProductType.appCoin: {},
      ProductType.digital: {},
      ProductType.physical: {},
      ProductType.service: {},
      ProductType.subscription: {},
      ProductType.crowdfunding: {},
      ProductType.external: {},
      ProductType.streaming: {},
      ProductType.event: {},
      ProductType.booking: {},
      ProductType.notDefined: {},
    };

    for (int i = 0; i < wooProducts.length; i++) {
      WooProduct product = wooProducts[i];
      if(product.downloads?.isEmpty ?? true ) {
        String type = product.attributes?[WooAttributeConstants.productType]?.options.first ?? '';
        productType = EnumToString.fromString(ProductType.values, type) ?? ProductType.digital;

        AppReleaseItem releaseItem = WooProductMapper.toAppReleaseItem(product);
        if(product.categories.firstWhereOrNull((category) => category.name.toLowerCase()== MediaItemType.podcast.name.toLowerCase()) != null){
          releaseItem.type = ReleaseType.episode;
        } else if(product.categories.firstWhereOrNull((category) => category.name.toLowerCase() == MediaItemType.audiobook.name.tr.toLowerCase()) != null){
          releaseItem.type = ReleaseType.chapter;
        }

        categorizedReleaseItems[productType]?[i] = releaseItem;
      } else {
        int index = 0;
        productType = ProductType.digital;
        List<AppReleaseItem> releases = [];
        product.downloads?.forEach((download) {
          AppReleaseItem releaseItem = WooProductMapper.toAppReleaseItem(product);
          if(product.categories.firstWhereOrNull((category) => category.name.toLowerCase()== MediaItemType.podcast.name.toLowerCase()) != null){
            releaseItem.type = ReleaseType.episode;
          } else if(product.categories.firstWhereOrNull((category) => category.name.toLowerCase() == MediaItemType.audiobook.name.tr.toLowerCase()) != null){
            releaseItem.type = ReleaseType.chapter;
          }

          releaseItem.name = download.name ?? '';
          releaseItem.ownerName = TextUtilities.getArtistName(product.name);
          releaseItem.previewUrl = download.file ?? '';
          releaseItem.id = '${product.id}_${index++}';
          releaseItem.metaId = product.id.toString();
          releaseItem.metaName = TextUtilities.getMediaName(product.name);
          releases.add(releaseItem);
        },);

        int randomIndex = Random().nextInt(releases.length);
        categorizedReleaseItems[productType]?[i] = releases[randomIndex];
        AppConfig.instance.releaseItemlists[product.id.toString()] = WooProductMapper.toItemlist(product);
      }

    }

    return categorizedReleaseItems;
  }

  
}
