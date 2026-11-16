import 'package:neom_core/app_config.dart';
import 'package:neom_core/domain/model/app_user.dart';

class WooUsersAPI {
  /// Disabled client-side stub: never transmit user passwords or placeholder
  /// credentials (`tudominio.com` / `<tu_clave_api>`) from the client.
  /// Customer provisioning must go through a server-side Cloud Function.
  Future<void> createWooCommerceUser(AppUser user) async {
    AppConfig.logger.w(
      'WooUsersAPI.createWooCommerceUser blocked on client; '
      'use server-side CloudProperties.wooProxy instead.',
    );
  }
}
