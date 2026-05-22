// Tests for `WooProductAttribute`, `WooProductCategory`, `WooProductDownload`.
// Modelos POJO de WooCommerce REST API.

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_woo/domain/model/woo_product_attribute.dart';
import 'package:neom_woo/domain/model/woo_product_category.dart';
import 'package:neom_woo/domain/model/woo_product_downloads.dart';

void main() {
  group('WooProductAttribute', () {
    test('defaults: 0/empty values', () {
      final attr = WooProductAttribute();
      expect(attr.id, 0);
      expect(attr.name, '');
      expect(attr.slug, '');
      expect(attr.position, 0);
      expect(attr.visible, isFalse);
      expect(attr.variation, isFalse);
      expect(attr.options, isEmpty);
    });

    test('round-trip JSON', () {
      final original = WooProductAttribute(
        id: 1,
        name: 'Color',
        slug: 'pa_color',
        position: 0,
        visible: true,
        variation: true,
        options: ['Red', 'Blue', 'Green'],
      );
      final restored = WooProductAttribute.fromJSON(original.toJSON());
      expect(restored.id, 1);
      expect(restored.name, 'Color');
      expect(restored.slug, 'pa_color');
      expect(restored.position, 0);
      expect(restored.visible, isTrue);
      expect(restored.variation, isTrue);
      expect(restored.options, ['Red', 'Blue', 'Green']);
    });

    test('fromJSON con mapa vacío usa defaults', () {
      final attr = WooProductAttribute.fromJSON({});
      expect(attr.id, 0);
      expect(attr.name, '');
      expect(attr.options, isEmpty);
    });

    test('fromJSON con options null → lista vacía', () {
      final attr = WooProductAttribute.fromJSON({
        'id': 1, 'name': 'Color',
        // sin options
      });
      expect(attr.options, isEmpty);
    });
  });

  group('WooProductCategory', () {
    test('defaults', () {
      final cat = WooProductCategory();
      expect(cat.id, 0);
      expect(cat.name, '');
      expect(cat.slug, '');
    });

    test('round-trip JSON', () {
      final original = WooProductCategory(
        id: 15,
        name: 'Música',
        slug: 'musica',
      );
      final restored = WooProductCategory.fromJSON(original.toJSON());
      expect(restored.id, 15);
      expect(restored.name, 'Música');
      expect(restored.slug, 'musica');
    });

    test('fromJSON con mapa vacío usa defaults', () {
      final cat = WooProductCategory.fromJSON({});
      expect(cat.id, 0);
      expect(cat.name, '');
    });
  });

  group('WooProductDownload', () {
    test('defaults: todos null', () {
      final dl = WooProductDownload();
      expect(dl.id, isNull);
      expect(dl.name, isNull);
      expect(dl.file, isNull);
    });

    test('round-trip JSON', () {
      final original = WooProductDownload(
        id: 'download-1',
        name: 'Album.zip',
        file: 'https://example.com/files/album.zip',
      );
      final restored = WooProductDownload.fromJson(original.toJson());
      expect(restored.id, 'download-1');
      expect(restored.name, 'Album.zip');
      expect(restored.file, 'https://example.com/files/album.zip');
    });

    test('fromJson con valores no-string los convierte a string', () {
      final dl = WooProductDownload.fromJson({
        'id': 123,         // int
        'name': 'X',
        'file': 'http://x',
      });
      expect(dl.id, '123'); // toString
      expect(dl.name, 'X');
    });

    test('fromJson con mapa vacío todos null', () {
      final dl = WooProductDownload.fromJson({});
      expect(dl.id, isNull);
      expect(dl.name, isNull);
      expect(dl.file, isNull);
    });
  });
}
