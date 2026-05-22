// Tests for `WooProductTag`.

import 'package:flutter_test/flutter_test.dart';
import 'package:neom_woo/domain/model/woo_product_tag.dart';

void main() {
  group('WooProductTag — defaults', () {
    test('constructor sin params', () {
      final t = WooProductTag();
      expect(t.id, 0);
      expect(t.name, '');
      expect(t.slug, '');
    });

    test('parámetros nombrados', () {
      final t = WooProductTag(id: 42, name: 'Rock', slug: 'rock');
      expect(t.id, 42);
      expect(t.name, 'Rock');
      expect(t.slug, 'rock');
    });
  });

  group('WooProductTag — round-trip', () {
    test('preserva todos los campos', () {
      final original = WooProductTag(id: 1, name: 'Música', slug: 'musica');
      final restored = WooProductTag.fromJSON(original.toJSON());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.slug, original.slug);
    });

    test('mapa vacío usa defaults', () {
      final t = WooProductTag.fromJSON({});
      expect(t.id, 0);
      expect(t.name, '');
      expect(t.slug, '');
    });
  });
}
