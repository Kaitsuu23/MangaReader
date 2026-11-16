import 'dart:io';
import '../storage/local_storage.dart';

/// Global HttpOverrides that dynamically applies user-configured network preferences:
/// - Bad certificate acceptance (SSL bypass)
/// - Manual HTTP / SOCKS proxy routing
class AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    // Apply SSL bypass if enabled in settings
    if (LocalStorage.isSslBypassEnabled()) {
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    }

    // Apply manual proxy if enabled in settings
    if (LocalStorage.isManualProxyEnabled()) {
      final host = LocalStorage.getManualProxyHost().trim();
      final port = LocalStorage.getManualProxyPort();
      final type = LocalStorage.getManualProxyType().toUpperCase();
      if (host.isNotEmpty) {
        if (type.contains('SOCKS')) {
          client.findProxy = (uri) => 'SOCKS $host:$port;';
        } else {
          client.findProxy = (uri) => 'PROXY $host:$port;';
        }
      }
    }

    return client;
  }

  /// Installs or updates the global HttpOverrides.
  static void install() {
    HttpOverrides.global = AppHttpOverrides();
  }
}
