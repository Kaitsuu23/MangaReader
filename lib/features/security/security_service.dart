import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/storage/local_storage.dart';

class SecurityService {
  static final LocalAuthentication _auth = LocalAuthentication();
  static final ValueNotifier<bool> isLockedNotifier = ValueNotifier<bool>(false);
  static DateTime? _pausedAt;

  static bool get isLocked => isLockedNotifier.value;

  /// Inisialisasi status keamanan saat aplikasi mulai
  static void init() {
    if (LocalStorage.isAppLockEnabled()) {
      isLockedNotifier.value = true;
    }
  }

  /// Cek apakah perangkat mendukung biometrik
  static Future<bool> canAuthenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Dapatkan daftar tipe biometrik yang tersedia (sidik jari, wajah, dsb)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Jalankan autentikasi biometrik / kredensial perangkat
  static Future<bool> authenticate({String reason = 'Buka Yomika untuk melanjutkan'}) async {
    try {
      final isBiometric = LocalStorage.isBiometricEnabled();
      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: !isBiometric ? false : false,
        persistAcrossBackgrounding: true,
      );
      if (authenticated) {
        unlock();
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      debugPrint('[SecurityService] Authenticate error: $e');
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Dipanggil saat aplikasi masuk ke background
  static void onAppPaused() {
    if (!LocalStorage.isAppLockEnabled()) return;
    _pausedAt = DateTime.now();
  }

  /// Dipanggil saat aplikasi kembali ke foreground
  static void onAppResumed() {
    if (!LocalStorage.isAppLockEnabled()) {
      isLockedNotifier.value = false;
      return;
    }

    if (_pausedAt == null) {
      isLockedNotifier.value = true;
      return;
    }

    final timeoutMinutes = LocalStorage.getAppLockTimeout();
    final elapsed = DateTime.now().difference(_pausedAt!);

    if (timeoutMinutes == 0 || elapsed.inMinutes >= timeoutMinutes) {
      isLockedNotifier.value = true;
    }
    _pausedAt = null;
  }

  /// Buka kunci aplikasi
  static void unlock() {
    isLockedNotifier.value = false;
    _pausedAt = null;
  }

  /// Kunci aplikasi secara manual
  static void lock() {
    if (LocalStorage.isAppLockEnabled()) {
      isLockedNotifier.value = true;
    }
  }
}
