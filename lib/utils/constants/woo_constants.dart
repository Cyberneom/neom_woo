
class WooConstants {

  static const String jwtTokenUrl = '/wp-json/jwt-auth/v1/token';

  static const String attributes = 'attributes';
  static const String username = 'username';
  static const String password = 'password';

  static const String carrito = 'carrito';
  static const String checkout = 'checkout';
  static const String ordenRecibida = 'orden-recibida';
  static const String paypal = 'www.paypal.com';
  static const String stripe = 'stripe';
  static const String captcha = 'captcha';
  static const List<String> allowedUrls = [carrito, checkout, ordenRecibida, paypal, stripe];

}
