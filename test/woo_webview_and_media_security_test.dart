import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neom_woo/utils/woo_security_utils.dart';

void main() {
  group('WooSecurityUtils Desktop/Web & URL security hardening', () {
    test('shouldUseExternalBrowser routes macOS, Windows, Linux & Web externally', () {
      expect(
        WooSecurityUtils.shouldUseExternalBrowser(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        WooSecurityUtils.shouldUseExternalBrowser(
          isWeb: false,
          platform: TargetPlatform.macOS,
        ),
        isTrue,
      );
      expect(
        WooSecurityUtils.shouldUseExternalBrowser(
          isWeb: false,
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
      expect(
        WooSecurityUtils.shouldUseExternalBrowser(
          isWeb: false,
          platform: TargetPlatform.linux,
        ),
        isTrue,
      );
      expect(
        WooSecurityUtils.shouldUseExternalBrowser(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
      expect(
        WooSecurityUtils.shouldUseExternalBrowser(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
    });

    test('isAllowedNavigationUrl & parseOrderConfirmation reject Bidi, userInfo & non-HTTPS', () {
      const siteHost = 'tienda.emxi.org';
      expect(
        WooSecurityUtils.isAllowedSiteUrl(
          'https://tienda.emxi.org/finalizar-compra/',
          siteHost: siteHost,
        ),
        isTrue,
      );
      expect(
        WooSecurityUtils.isAllowedSiteUrl(
          'http://tienda.emxi.org/finalizar-compra/',
          siteHost: siteHost,
        ),
        isFalse,
      );
      expect(
        WooSecurityUtils.isAllowedSiteUrl(
          'https://attacker@tienda.emxi.org/finalizar-compra/',
          siteHost: siteHost,
        ),
        isFalse,
      );
      expect(
        WooSecurityUtils.isAllowedSiteUrl(
          'https://tienda.emxi.org/\u202Efinalizar-compra/',
          siteHost: siteHost,
        ),
        isFalse,
      );
      expect(
        WooSecurityUtils.isAllowedNavigationUrl(
          'https://checkout.stripe.com/c/pay/cs_test_1',
          siteHost: siteHost,
        ),
        isTrue,
      );
      expect(
        WooSecurityUtils.isAllowedNavigationUrl(
          'https://evil.example.com/orden-recibida/99',
          siteHost: siteHost,
        ),
        isFalse,
      );

      expect(
        WooSecurityUtils.parseOrderConfirmation(
          'https://tienda.emxi.org/finalizar-compra/orden-recibida/4821/?key=wc_order_Abc123',
        ),
        ('4821', 'wc_order_Abc123'),
      );
      expect(
        WooSecurityUtils.parseOrderConfirmation(
          'https://tienda.emxi.org/finalizar-compra/orden-recibida/4821/?key=wc_order_<script>',
        ),
        ('4821', ''),
      );
    });

    test('sanitizeOrderDescription & sanitizeMediaFilename strip traversal, quotes & tags', () {
      expect(
        WooSecurityUtils.sanitizeOrderDescription(
          '<think>plan</think>[BIOCHIP: 1] Obra\u202E Literaria',
        ),
        'Obra Literaria',
      );

      expect(
        WooSecurityUtils.sanitizeMediaFilename(
          '../../etc/passwd"\r\nContent-Type: text/html',
          fallbackExtension: '.jpg',
        ),
        'html.jpg',
      );
      expect(
        WooSecurityUtils.sanitizeMediaFilename(
          '../../etc/passwd"\r\nX-Evil: 1',
          fallbackExtension: '.jpg',
        ),
        'passwd_X-Evil_1.jpg',
      );
      expect(
        WooSecurityUtils.sanitizeMediaFilename(
          'Portada Canción Niño\u202E.png',
          fallbackExtension: '.png',
        ),
        'Portada_Cancion_Nino.png',
      );
    });
  });
}
