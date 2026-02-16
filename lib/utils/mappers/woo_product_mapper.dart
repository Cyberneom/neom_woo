import 'package:enum_to_string/enum_to_string.dart';
import 'package:neom_commons/utils/text_utilities.dart';
import 'package:neom_core/domain/model/app_release_item.dart';
import 'package:neom_core/domain/model/item_list.dart';
import 'package:neom_core/domain/model/price.dart';
import 'package:neom_core/utils/enums/app_currency.dart';
import 'package:neom_core/utils/enums/itemlist_type.dart';
import 'package:neom_core/utils/enums/media_item_type.dart';
import 'package:neom_core/utils/enums/owner_type.dart';
import 'package:neom_core/utils/enums/release_status.dart';
import 'package:neom_core/utils/enums/release_type.dart';
import 'package:sint/sint.dart';

import '../../domain/model/woo_product.dart';
import '../../domain/model/woo_product_attribute.dart';
import '../../domain/model/woo_product_category.dart';
import '../../domain/model/woo_product_downloads.dart';
import '../../domain/model/woo_product_image.dart';
import '../../domain/model/woo_product_tag.dart';
import '../../utils/enums/woo_product_status.dart';

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
        ownerName: (product.attributes?.containsKey('ownerName') ?? false) ? product.attributes!['ownerName']!.options.first : TextUtilities.getArtistName(product.name),
        ownerType: OwnerType.woo,
        categories: List.from(product.categories.map((c) => c.name).toList()),
        tags: List.from(product.tags.map((t) => t.name).toList()),
        lyrics: product.shortDescription,
        language: (product.attributes?.containsKey('language') ?? false) ? product.attributes!['language']!.options.first : '',
        digitalPrice: product.virtual ? Price(amount: product.regularPrice, currency: AppCurrency.mxn) : null,
        physicalPrice: !product.virtual ? Price(amount: product.regularPrice, currency: AppCurrency.mxn) : null,
        salePrice: Price(amount: product.salePrice, currency: AppCurrency.mxn),
        variations: product.variations,
        isRental: (product.attributes?.containsKey('isRental') ?? true) ? bool.parse(product.attributes!['isRental']!.options.first) : true,
        publishedYear: (product.attributes?.containsKey('publishedYear') ?? false) ? int.tryParse(product.attributes!['publishedYear']!.options.first) : null,
        metaOwner: (product.attributes?.containsKey('metaOwner') ?? false) ? product.attributes!['metaOwner']!.options.first
            : (product.attributes?.containsKey('publisher') ?? false) ? product.attributes!['publisher']!.options.first : null, ///REMOVE LOOKUP FOR PUBLISHER WHEN WOOCOMMERCE IS UPDATED
        createdTime: product.dateCreated?.millisecondsSinceEpoch ?? 0,
        modifiedTime: product.dateModified?.millisecondsSinceEpoch,
        state: 0,
        externalUrl: product.permalink,
        webPreviewUrl: (product.attributes?.containsKey('webPreviewUrl') ?? false) ? product.attributes!['webPreviewUrl']!.options.first : null
    );
  }

  /// Converts an AppReleaseItem to a WooProduct for creating in WooCommerce
  static WooProduct fromAppReleaseItem(
    AppReleaseItem item, {
    String? coverImageUrl,
    String? downloadFileUrl,
  }) {
    // Determine if product is virtual or physical based on prices
    final bool hasPhysicalPrice = item.physicalPrice != null && (item.physicalPrice!.amount ?? 0) > 0;
    final bool hasDigitalPrice = item.digitalPrice != null && (item.digitalPrice!.amount ?? 0) > 0;
    final bool isVirtual = !hasPhysicalPrice;

    // Use physical price if available, otherwise digital price
    final double regularPrice = hasPhysicalPrice
        ? (item.physicalPrice!.amount ?? 0.0)
        : (item.digitalPrice?.amount ?? 0.0);

    // Generate SKU: author initials + title initials + D/F + short timestamp for uniqueness
    final String sku = _generateSku(item.ownerName, item.name, hasPhysicalPrice,
        timestamp: item.createdTime > 0 ? item.createdTime : DateTime.now().millisecondsSinceEpoch);

    // Build categories from item.categories (genres) AND instruments
    final List<WooProductCategory> wooCategories = [
      ...item.categories.map((cat) => WooProductCategory(name: cat, slug: _generateSlug(cat))),
      ...(item.instruments ?? []).map((inst) => WooProductCategory(name: inst, slug: _generateSlug(inst))),
    ];

    // Build tags from item.tags only
    final List<WooProductTag> wooTags = [
      ...(item.tags ?? []).map((tag) => WooProductTag(name: tag, slug: _generateSlug(tag))),
    ];

    // Build short description
    String shortDescription = '';
    if (item.ownerName.isNotEmpty) {
      shortDescription = 'Por: ${item.ownerName}';
    }
    if (item.metaOwner?.isNotEmpty ?? false) {
      shortDescription += shortDescription.isNotEmpty
          ? ' | Editorial: ${item.metaOwner}'
          : 'Editorial: ${item.metaOwner}';
    }

    // Product name format: "Author – Title" for public visibility
    final productName = item.ownerName.isNotEmpty
        ? '${item.ownerName} \u2013 ${item.name}'
        : item.name;

    return WooProduct(
      name: productName,
      slug: _generateSlug(productName),
      sku: sku,
      status: item.status == ReleaseStatus.publish
          ? WooProductStatus.publish
          : WooProductStatus.draft,
      description: item.description,
      shortDescription: shortDescription,
      regularPrice: regularPrice,
      salePrice: item.salePrice?.amount ?? 0.0,
      virtual: isVirtual,
      downloadable: downloadFileUrl?.isNotEmpty ?? false,
      purchasable: true,
      downloads: downloadFileUrl != null && downloadFileUrl.isNotEmpty
          ? [
              WooProductDownload(
                id: item.id.isNotEmpty
                    ? item.id
                    : DateTime.now().millisecondsSinceEpoch.toString(),
                name: item.name,
                file: downloadFileUrl,
              )
            ]
          : [],
      downloadLimit: -1,
      downloadExpiry: -1,
      images: coverImageUrl != null && coverImageUrl.isNotEmpty
          ? [
              WooProductImage(
                src: coverImageUrl,
                name: item.name,
                alt: '${item.name} - ${item.ownerName}',
              )
            ]
          : [],
      categories: wooCategories,
      tags: wooTags,
      attributes: {
        'previewUrl': WooProductAttribute(
          name: 'previewUrl',
          options: [item.previewUrl],
          visible: false,
        ),
        'ownerName': WooProductAttribute(
          name: 'ownerName',
          options: [item.ownerName],
          visible: true,
        ),
        'ownerEmail': WooProductAttribute(
          name: 'ownerEmail',
          options: [item.ownerEmail],
          visible: false,
        ),
        'duration': WooProductAttribute(
          name: 'duration',
          options: [item.duration.toString()],
          visible: true,
        ),
        'type': WooProductAttribute(
          name: 'type',
          options: [item.type.name],
          visible: true,
        ),
        'language': WooProductAttribute(
          name: 'language',
          options: [item.language ?? 'es'],
          visible: true,
        ),
        'publishedYear': WooProductAttribute(
          name: 'publishedYear',
          options: [item.publishedYear?.toString() ?? ''],
          visible: true,
        ),
        'firestoreId': WooProductAttribute(
          name: 'firestoreId',
          options: [item.id],
          visible: false,
        ),
        if (item.metaOwner?.isNotEmpty ?? false)
          'metaOwner': WooProductAttribute(
            name: 'metaOwner',
            options: [item.metaOwner!],
            visible: true,
          ),
        if (item.instruments?.isNotEmpty ?? false)
          'instruments': WooProductAttribute(
            name: 'instruments',
            options: item.instruments!,
            visible: true,
          ),
        if (item.place != null)
          'place': WooProductAttribute(
            name: 'place',
            options: [item.place!.name ?? ''],
            visible: true,
          ),
        if (hasPhysicalPrice)
          'physicalPrice': WooProductAttribute(
            name: 'physicalPrice',
            options: [(item.physicalPrice!.amount ?? 0).toString()],
            visible: true,
          ),
        if (hasDigitalPrice)
          'digitalPrice': WooProductAttribute(
            name: 'digitalPrice',
            options: [(item.digitalPrice!.amount ?? 0).toString()],
            visible: true,
          ),
      },
    );
  }

  /// Generates a URL-safe slug from a name
  static String _generateSlug(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
  }

  /// Generates SKU from author name, title, product type and timestamp for uniqueness
  /// Format: AUTHOR_INITIALS-TITLE_INITIALS-TYPE-TIMESTAMP (e.g., SM-PDGC-D-1771217893)
  static String _generateSku(String authorName, String title, bool isPhysical, {int timestamp = 0}) {
    String getInitials(String text) {
      if (text.isEmpty) return 'XX';
      final words = text.trim().split(RegExp(r'\s+'));
      if (words.length == 1) {
        return text.substring(0, text.length >= 3 ? 3 : text.length).toUpperCase();
      }
      return words
          .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
          .join()
          .substring(0, words.length >= 4 ? 4 : words.length);
    }

    final authorInitials = getInitials(authorName);
    final titleInitials = getInitials(title);
    final typeCode = isPhysical ? 'F' : 'D';
    // Use last 6 digits of timestamp for uniqueness without making SKU too long
    final suffix = timestamp > 0 ? '-${(timestamp % 1000000).toString()}' : '';

    return '$authorInitials-$titleInitials-$typeCode$suffix';
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
