// Tests for `WooProductImage`.

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_woo/domain/model/woo_product_image.dart';

void main() {
  group('WooProductImage — defaults', () {
    test('constructor sin params asigna fechas a now', () {
      final img = WooProductImage();
      expect(img.id, 0);
      expect(img.src, '');
      expect(img.name, '');
      expect(img.alt, '');
      expect(img.dateCreated.year, greaterThanOrEqualTo(2024));
    });
  });

  group('WooProductImage — round-trip', () {
    test('preserva campos básicos', () {
      final dt = DateTime.utc(2024, 1, 15, 12);
      final original = WooProductImage(
        id: 100,
        src: 'https://x.com/img.jpg',
        name: 'Cover',
        alt: 'Album cover',
        dateCreated: dt,
        dateCreatedGmt: dt,
        dateModified: dt,
        dateModifiedGmt: dt,
      );
      final restored = WooProductImage.fromJSON(original.toJSON());
      expect(restored.id, original.id);
      expect(restored.src, original.src);
      expect(restored.name, original.name);
      expect(restored.alt, original.alt);
      expect(restored.dateCreated.year, dt.year);
    });

    test('mapa vacío usa defaults sin crashear', () {
      final img = WooProductImage.fromJSON({});
      expect(img.id, 0);
      expect(img.src, '');
      // Fechas asignadas a DateTime.now()
      expect(img.dateCreated.year, greaterThanOrEqualTo(2024));
    });

    test('fecha inválida cae a DateTime.now()', () {
      final img = WooProductImage.fromJSON({
        'date_created': 'not-a-date',
      });
      expect(img.dateCreated.year, greaterThanOrEqualTo(2024));
    });

    test('toJSON serializa fechas como ISO 8601', () {
      final img = WooProductImage(
        id: 1, dateCreated: DateTime.utc(2024, 1, 15, 12),
      );
      expect(img.toJSON()['date_created'], '2024-01-15T12:00:00.000Z');
    });
  });
}
