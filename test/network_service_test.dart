import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/core/services/network_service.dart';
import 'package:manga_app/shared/widgets/error_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetworkService & Offline Indicator Tests', () {
    test('isNetworkError correctly identifies offline and network exceptions', () {
      expect(NetworkService.isNetworkError(const SocketException('Failed host lookup')), true);
      expect(NetworkService.isNetworkError(TimeoutException('Request timed out')), true);
      expect(NetworkService.isNetworkError('PlatformException(PARSER_ERROR, java.net.UnknownHostException, null)'), true);
      expect(NetworkService.isNetworkError('No address associated with hostname'), true);
      expect(NetworkService.isNetworkError('ConnectException: Network is unreachable'), true);
      expect(NetworkService.isNetworkError('Connection refused'), true);
      expect(NetworkService.isNetworkError('Connection reset by peer'), true);

      // Non-network errors should be false
      expect(NetworkService.isNetworkError('NullPointerException'), false);
      expect(NetworkService.isNetworkError('FormatException: Unexpected character'), false);
      expect(NetworkService.isNetworkError('PlatformException(PARSER_ERROR, HTTP error fetching URL. Status=403, null)'), false);
      expect(NetworkService.isNetworkError('Akses ditolak (403)'), false);
      expect(NetworkService.isNetworkError(null), false);
    });

    test('friendlyError maps network error strings to user-friendly Indonesian message', () {
      final msg1 = friendlyError('SocketException: OS Error: Failed host lookup');
      expect(msg1.contains('Tidak ada koneksi internet'), true);

      final msg2 = friendlyError('java.net.UnknownHostException: Unable to resolve host');
      expect(msg2.contains('Tidak ada koneksi internet'), true);

      final msg3 = friendlyError('ConnectException: Network is unreachable');
      expect(msg3.contains('Tidak ada koneksi internet'), true);

      final msgTimeout = friendlyError('Connection timeout');
      expect(msgTimeout.contains('habis waktu'), true);
    });

    test('isConnectedNotifier reflects connectivity state updates', () {
      NetworkService.isConnectedNotifier.value = false;
      expect(NetworkService.isConnectedNotifier.value, false);

      NetworkService.isConnectedNotifier.value = true;
      expect(NetworkService.isConnectedNotifier.value, true);
    });
  });
}
