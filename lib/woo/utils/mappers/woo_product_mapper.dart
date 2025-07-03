import 'package:enum_to_string/enum_to_string.dart';
import 'package:get/get.dart';
import 'package:neom_commons/commons/utils/app_utilities.dart';
import 'package:neom_core/core/domain/model/app_release_item.dart';
import 'package:neom_core/core/domain/model/item_list.dart';
import 'package:neom_core/core/domain/model/price.dart';
import 'package:neom_core/core/utils/enums/app_currency.dart';
import 'package:neom_core/core/utils/enums/itemlist_type.dart';
import 'package:neom_core/core/utils/enums/media_item_type.dart';
import 'package:neom_core/core/utils/enums/owner_type.dart';
import 'package:neom_core/core/utils/enums/release_status.dart';
import 'package:neom_core/core/utils/enums/release_type.dart';

import '../../domain/model/woo_product.dart';
import '../../domain/model/woo_product_downloads.dart';

class WooProductMapper {

  static AppReleaseItem toAppReleaseItem(WooProduct product) {
    return AppReleaseItem(
        id: product.id.toString(),
        name: product.name,
        description: product.description.isNotEmpty ? product.description : product.shortDescription.isNotEmpty ? product.shortDescription : '',
        imgUrl: product.images.isNotEmpty ? product.images.first.src : '',
        galleryUrls: product.images.map<String>((img)=> img.src).toList(),
        previewUrl: (product.attributes?.containsKey('previewUrl') ?? false) ? product.attributes!['previewUrl']!.options.first : '',
        duration: (product.attributes?.containsKey('duration') ?? false) ? int.tryParse(product.attributes!['duration']!.options.first) ?? 0 : 0,
        type: (product.attributes?.containsKey('type') ?? false) ? EnumToString.fromString(ReleaseType.values, product.attributes!['type']!.options.first) ?? ReleaseType.single : ReleaseType.single,
        status: EnumToString.fromString(ReleaseStatus.values, product.status.name) ?? ReleaseStatus.draft,
        ownerEmail: (product.attributes?.containsKey('ownerEmail') ?? false) ? product.attributes!['ownerEmail']!.options.first : '',
        ownerName: (product.attributes?.containsKey('ownerName') ?? false) ? product.attributes!['ownerName']!.options.first : AppUtilities.getArtistName(product.name),
        ownerType: OwnerType.woo,
        categories: List.from(product.categories.map((c) => c.name).toList()),
        tags: List.from(product.tags.map((t) => t.name).toList()),
        // metaName = null,
        // metaId = null,
        // metaOwnerId = null,
        // appMediaItemIds = null,
        // instruments = null,
        lyrics: product.shortDescription,
        language: (product.attributes?.containsKey('language') ?? false) ? product.attributes!['language']!.options.first : '',
        digitalPrice: product.virtual ? Price(amount: product.regularPrice, currency: AppCurrency.mxn) : null,
        physicalPrice: !product.virtual ? Price(amount: product.regularPrice, currency: AppCurrency.mxn) : null,
        salePrice: Price(amount: product.salePrice, currency: AppCurrency.mxn),
        variations: product.variations,
        isRental: (product.attributes?.containsKey('isRental') ?? true) ? bool.parse(product.attributes!['isRental']!.options.first) : true,
        publishedYear: (product.attributes?.containsKey('publishedYear') ?? false) ? int.tryParse(product.attributes!['publishedYear']!.options.first) : null,
        publisher: (product.attributes?.containsKey('publisher') ?? false) ? product.attributes!['publisher']!.options.first : null,
        // place =  null,
        // boughtUsers = null,
        createdTime: product.dateCreated?.millisecondsSinceEpoch ?? 0,
        modifiedTime: product.dateModified?.millisecondsSinceEpoch,
        state: 0,
        // externalArtists = null,
        // featInternalArtists = null,
        // likedProfiles = null
        externalUrl: product.permalink,
        webPreviewUrl: (product.attributes?.containsKey('webPreviewUrl') ?? false) ? product.attributes!['webPreviewUrl']!.options.first : null
    );
  }

  static Itemlist toItemlist(WooProduct product) {
    return Itemlist(
      id: product.id.toString(),
      name: product.name,
      description: product.description.isNotEmpty ? product.description : product.shortDescription.isNotEmpty ? product.shortDescription : '',
      ownerId: (product.attributes?.containsKey('ownerEmail') ?? false) ? product.attributes!['ownerEmail']!.options.first : '',
      ownerName: (product.attributes?.containsKey('ownerName') ?? false) ? product.attributes!['ownerName']!.options.first : '',
      ownerType: OwnerType.woo,
      href: product.permalink,
      imgUrl: product.images.isNotEmpty ? product.images.first.src : '',
      public: (EnumToString.fromString(ReleaseStatus.values, product.status.name) ?? ReleaseStatus.draft) == ReleaseStatus.publish,
      isModifiable: false,
      uri: product.permalink,
      type: (product.attributes?.containsKey('type') ?? false) ? EnumToString.fromString(ItemlistType.values, product.attributes!['type']!.options.first) ?? ItemlistType.single : ItemlistType.single,
      categories: List.from(product.categories.map((c) => c.name).toList()),
      tags: List.from(product.tags.map((t) => t.name).toList()),
      language: (product.attributes?.containsKey('language') ?? false) ? product.attributes!['language']!.options.first : '',
      createdTime: product.dateCreated?.millisecondsSinceEpoch ?? 0,
      modifiedTime: product.dateModified?.millisecondsSinceEpoch,
      appReleaseItems: product.downloads?.asMap().entries.map((entry) {
        int index = entry.key;
        WooProductDownload download = entry.value;
        AppReleaseItem releaseItem = toAppReleaseItem(product);
        if(product.categories.firstWhereOrNull((category) => category.name == MediaItemType.podcast.name) != null){
          releaseItem.type = ReleaseType.episode;
        } else if(product.categories.firstWhereOrNull((category) => category.name == MediaItemType.audiobook.name.tr) != null){
          releaseItem.type = ReleaseType.chapter;
        }
        releaseItem.name = download.name ?? '';
        releaseItem.ownerName = product.name;
        releaseItem.previewUrl = download.file ?? '';
        releaseItem.id = '${product.id}_${index++}';
        return releaseItem;
      },).toList(),
    );
  }

}
