import 'package:flutter_test/flutter_test.dart';
import 'package:neom_woo/domain/model/woo_line_item.dart';

void main() {
  group('WooLineItem.fromJSON · defensive parsing', () {
    test('int quantity is preserved', () {
      final l = WooLineItem.fromJSON({'product_id': 42, 'quantity': 3});
      expect(l.productId, '42');
      expect(l.quantity, 3);
    });

    test('string product_id is preserved', () {
      final l = WooLineItem.fromJSON({'product_id': 'sku-abc', 'quantity': 1});
      expect(l.productId, 'sku-abc');
    });

    test('numeric-string quantity parses cleanly (WooCommerce plugin quirk)', () {
      // Prior to the fix this line blew up with a cast error.
      final l = WooLineItem.fromJSON({'product_id': 1, 'quantity': '5'});
      expect(l.quantity, 5);
    });

    test('double quantity (unusual) truncates to int', () {
      final l = WooLineItem.fromJSON({'product_id': 1, 'quantity': 2.9});
      expect(l.quantity, 2);
    });

    test('missing quantity defaults to 0 instead of crashing', () {
      final l = WooLineItem.fromJSON({'product_id': 1});
      expect(l.quantity, 0);
    });

    test('null quantity defaults to 0', () {
      final l = WooLineItem.fromJSON({'product_id': 1, 'quantity': null});
      expect(l.quantity, 0);
    });

    test('malformed quantity string defaults to 0', () {
      final l = WooLineItem.fromJSON({'product_id': 1, 'quantity': 'nope'});
      expect(l.quantity, 0);
    });

    test('missing product_id becomes empty string (no NPE)', () {
      final l = WooLineItem.fromJSON({'quantity': 2});
      expect(l.productId, '');
      expect(l.quantity, 2);
    });
  });

  group('WooLineItem.toJSON', () {
    test('snake_case keys for WooCommerce REST compatibility', () {
      final l = WooLineItem(productId: '99', quantity: 4);
      final j = l.toJSON();
      expect(j['product_id'], '99');
      expect(j['quantity'], 4);
      // No camelCase leaks — the API rejects unknown keys.
      expect(j.containsKey('productId'), isFalse);
    });

    test('round-trip through JSON preserves fields', () {
      final a = WooLineItem(productId: '7', quantity: 12);
      final b = WooLineItem.fromJSON(a.toJSON());
      expect(b.productId, a.productId);
      expect(b.quantity, a.quantity);
    });
  });
}
