import 'package:flutter_test/flutter_test.dart';
import 'package:neom_woo/utils/enums/woo_order_status.dart';
import 'package:neom_woo/utils/enums/woo_order_currency.dart';
import 'package:neom_woo/utils/enums/woo_product_type.dart';
import 'package:neom_woo/utils/enums/woo_product_status.dart';
import 'package:neom_woo/utils/enums/woo_payment_method.dart';
import 'package:neom_woo/utils/enums/woo_tax_status.dart';
import 'package:neom_woo/utils/enums/woo_catalog_visibility.dart';
import 'package:neom_woo/utils/enums/woo_back_order_status.dart';

void main() {
  group('WooOrderStatus values match WooCommerce REST API strings', () {
    test('all well-known WooCommerce order statuses are present', () {
      final fromValue = {
        for (final s in WooOrderStatus.values) s.value: s,
      };
      expect(fromValue.containsKey('pending'), isTrue);
      expect(fromValue.containsKey('processing'), isTrue);
      expect(fromValue.containsKey('on-hold'), isTrue);
      expect(fromValue.containsKey('completed'), isTrue);
      expect(fromValue.containsKey('cancelled'), isTrue);
      expect(fromValue.containsKey('refunded'), isTrue);
      expect(fromValue.containsKey('failed'), isTrue);
    });

    test('enum name and value format: onHold maps to "on-hold" (dashed)', () {
      expect(WooOrderStatus.onHold.value, 'on-hold');
      expect(WooOrderStatus.autoDraft.value, 'auto-draft');
      expect(WooOrderStatus.checkoutDraft.value, 'checkout-draft');
      expect(WooOrderStatus.nupaleSession.value, 'nupale-session');
    });

    test('values list has no duplicates', () {
      final values = WooOrderStatus.values.map((s) => s.value).toList();
      expect(values.toSet().length, values.length);
    });

    test('terminal statuses (completed / cancelled / refunded / failed) are distinguishable', () {
      final terminal = {
        WooOrderStatus.completed,
        WooOrderStatus.cancelled,
        WooOrderStatus.refunded,
        WooOrderStatus.failed,
      };
      // Sanity: each is unique and has unique value.
      expect(terminal.length, 4);
      expect(terminal.map((e) => e.value).toSet().length, 4);
    });
  });

  group('WooOrderCurrency coverage', () {
    test('includes MXN, USD, EUR, GBP, JPY, BTC and other common currencies', () {
      final names = WooOrderCurrency.values.map((c) => c.name).toSet();
      for (final iso in ['MXN', 'USD', 'EUR', 'GBP', 'JPY', 'BTC', 'AUD', 'CAD']) {
        expect(names, contains(iso), reason: '$iso missing');
      }
    });

    test('has 100+ currencies (ISO 4217-ish)', () {
      expect(WooOrderCurrency.values.length, greaterThan(100));
    });

    test('enum name lookup returns the right instance', () {
      final mxn = WooOrderCurrency.values.firstWhere((c) => c.name == 'MXN');
      expect(mxn, WooOrderCurrency.MXN);
    });
  });

  group('Other Woo enums exist with sane cardinality', () {
    test('WooProductType includes simple, variable, subscription', () {
      final names = WooProductType.values.map((t) => t.name).toSet();
      expect(names, containsAll(['simple', 'variable', 'subscription']));
    });

    test('WooPaymentMethod includes stripe and paypal', () {
      final names = WooPaymentMethod.values.map((t) => t.name).toSet();
      expect(names, containsAll(['stripe', 'paypal']));
    });

    test('WooProductStatus, TaxStatus, CatalogVisibility, BackOrder enums non-empty', () {
      expect(WooProductStatus.values, isNotEmpty);
      expect(WooTaxStatus.values, isNotEmpty);
      expect(WooCatalogVisibility.values, isNotEmpty);
      expect(WooBackOrderStatus.values, isNotEmpty);
    });
  });
}
