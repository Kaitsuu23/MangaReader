import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../storage/local_storage.dart';

/// Layanan pendeteksi koneksi internet secara real-time dan penyedia SnackBar/info saat offline.
class NetworkService {
  static const _channel = MethodChannel('org.dhiksn.yomika/connectivity');

  static bool _isConnected = true;
  static bool get isConnected => _isConnected;

  static final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(true);

  static bool _isInitialized = false;
  static DateTime? _lastOfflineSnackbarTime;

  /// Inisialisasi pendeteksi koneksi jaringan
  static void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onConnectivityChanged') {
        final connected = call.arguments as bool? ?? true;
        _updateConnectionState(connected);
      }
    });

    // Pengecekan awal saat startup
    checkConnection();
  }

  static void _updateConnectionState(bool connected) {
    if (_isConnected != connected) {
      _isConnected = connected;
      isConnectedNotifier.value = connected;
    }
  }

  /// Cek koneksi secara aktif (melalui native Android ConnectivityManager + fallback DNS/socket)
  static Future<bool> checkConnection() async {
    try {
      final res = await _channel.invokeMethod<bool>('isConnected');
      if (res != null) {
        _updateConnectionState(res);
        return res;
      }
    } catch (_) {}

    // Fallback dart:io lookup jika di luar Android atau channel tidak merespon
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      final connected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      _updateConnectionState(connected);
      return connected;
    } on SocketException catch (_) {
      _updateConnectionState(false);
      return false;
    } on TimeoutException catch (_) {
      _updateConnectionState(false);
      return false;
    } catch (_) {
      return _isConnected;
    }
  }

  /// Memeriksa apakah suatu Exception / error berkaitan dengan kegagalan internet
  static bool isNetworkError(dynamic error) {
    if (error == null) return false;
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;

    final msg = error.toString().toLowerCase();

    // Jika error memiliki status HTTP (misal 403 Forbidden, 404, 500), berarti request sampai ke server.
    // Ini adalah masalah dari sumber/server, bukan ketiadaan koneksi internet lokal perangkat.
    if (msg.contains('status=403') ||
        msg.contains('status=404') ||
        msg.contains('status=500') ||
        msg.contains('status=502') ||
        msg.contains('status=503') ||
        msg.contains('status=401') ||
        msg.contains('403 forbidden') ||
        msg.contains('akses ditolak') ||
        msg.contains('cloudflare')) {
      return false;
    }

    return msg.contains('socketexception') ||
        msg.contains('networkexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('no address associated with hostname') ||
        msg.contains('connectexception') ||
        msg.contains('unknownhostexception') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('no internet') ||
        msg.contains('timed out') ||
        msg.contains('timeout');
  }

  /// Menampilkan SnackBar mengambang bahwa perangkat tidak memiliki koneksi internet
  static void showNoInternetSnackBar(
    BuildContext context, {
    VoidCallback? onRetry,
    String message = 'Tidak ada koneksi internet',
    bool force = false,
    bool? hasBottomNavbar,
    ScaffoldMessengerState? messengerState,
  }) {
    if (!context.mounted) return;

    // Throttle agar tidak spam snackbar jika dipicu berulang kali dalam 2 detik
    final now = DateTime.now();
    if (!force &&
        _lastOfflineSnackbarTime != null &&
        now.difference(_lastOfflineSnackbarTime!) < const Duration(milliseconds: 2000)) {
      return;
    }
    _lastOfflineSnackbarTime = now;

    final messenger = messengerState ?? ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    // Determine bottom margin:
    // - If caller explicitly provides hasBottomNavbar, use it.
    // - Otherwise, check whether the current screen is a pushed route (canPop = true).
    //   Pushed routes (Detail, Reader, Source View, Search, Settings, etc.) never have the bottom navbar.
    final bool canPop = ModalRoute.of(context)?.canPop ?? false;
    final bool screenHasNavbar = hasBottomNavbar ?? (!canPop);
    final double bottomMargin = (screenHasNavbar && LocalStorage.isFloatingNavEnabled()) ? 88.0 : 16.0;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Colors.redAccent,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Periksa sambungan Wi-Fi atau data seluler Anda.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF232326),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(left: 16, right: 16, bottom: bottomMargin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        duration: const Duration(seconds: 4),
        action: onRetry != null
            ? SnackBarAction(
                label: 'Coba Lagi',
                textColor: Theme.of(context).colorScheme.primary,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  /// Menampilkan SnackBar mengambang bahwa koneksi internet telah pulih
  static void showBackOnlineSnackBar(BuildContext context, {bool? hasBottomNavbar}) {
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final bool canPop = ModalRoute.of(context)?.canPop ?? false;
    final bool screenHasNavbar = hasBottomNavbar ?? (!canPop);
    final bottomMargin = (screenHasNavbar && LocalStorage.isFloatingNavEnabled()) ? 84.0 : 16.0;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_rounded,
                color: Colors.greenAccent,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Koneksi internet terhubung kembali',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1B281D),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(left: 16, right: 16, bottom: bottomMargin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: Colors.green.withValues(alpha: 0.35),
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
