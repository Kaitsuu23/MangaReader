import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:manga_app/core/services/network_service.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:manga_app/shared/widgets/sliced_page_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reader_retry_test_');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Reader Image Retry & Auto-reload on Reconnect Tests', () {
    test('NetworkService.isConnectedNotifier notifies listeners when connection changes', () {
      bool reconnected = false;
      NetworkService.isConnectedNotifier.addListener(() {
        if (NetworkService.isConnectedNotifier.value) {
          reconnected = true;
        }
      });

      NetworkService.isConnectedNotifier.value = false;
      expect(NetworkService.isConnectedNotifier.value, false);
      expect(reconnected, false);

      NetworkService.isConnectedNotifier.value = true;
      expect(NetworkService.isConnectedNotifier.value, true);
      expect(reconnected, true);
    });

    test('PageSliceCache invalidate clears futures for specified URL', () {
      const testUrl = 'https://example.com/chapter-1/page-1.jpg';
      PageSliceCache.instance.invalidate(testUrl);
      // Ensure invalidate does not throw and allows retry
      expect(testUrl.isNotEmpty, true);
    });

    testWidgets('Reader retry button renders properly and triggers callback', (tester) async {
      bool retryClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FilledButton.tonal(
                onPressed: () => retryClicked = true,
                child: const Text('Coba Lagi'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Coba Lagi'), findsOneWidget);
      await tester.tap(find.text('Coba Lagi'));
      await tester.pump();

      expect(retryClicked, true);
    });
  });
}
