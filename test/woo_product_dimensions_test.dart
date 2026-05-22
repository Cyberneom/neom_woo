// Tests for `WooProductDimensions`.

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_woo/domain/model/woo_product_dimensions.dart';

void main() {
  group('WooProductDimensions — defaults', () {
    test('constructor sin params', () {
      final d = WooProductDimensions();
      expect(d.length, 0);
      expect(d.width, 0);
      expect(d.height, 0);
    });

    test('parámetros nombrados', () {
      final d = WooProductDimensions(length: 30.5, width: 20, height: 10);
      expect(d.length, 30.5);
      expect(d.width, 20);
      expect(d.height, 10);
    });
  });

  group('WooProductDimensions — round-trip', () {
    test('preserva todos los campos', () {
      final original = WooProductDimensions(
        length: 30.5, width: 20, height: 10,
      );
      final restored = WooProductDimensions.fromJSON(original.toJSON());
      expect(restored.length, original.length);
      expect(restored.width, original.width);
      expect(restored.height, original.height);
    });

    test('null → todos 0', () {
      final d = WooProductDimensions.fromJSON(null);
      expect(d.length, 0);
      expect(d.width, 0);
      expect(d.height, 0);
    });

    test('mapa vacío → defaults', () {
      final d = WooProductDimensions.fromJSON({});
      expect(d.length, 0);
    });

    test('valores como string se parsean (WooCommerce envía strings)', () {
      final d = WooProductDimensions.fromJSON({
        'length': '30.5',
        'width': '20',
        'height': '10',
      });
      expect(d.length, 30.5);
      expect(d.width, 20);
      expect(d.height, 10);
    });

    test('valores no numéricos caen a 0', () {
      final d = WooProductDimensions.fromJSON({
        'length': 'invalid',
        'width': null,
      });
      expect(d.length, 0);
      expect(d.width, 0);
    });
  });
}
