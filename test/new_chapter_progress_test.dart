import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_new_chapter');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('New Chapter Release & Reading Progress Downgrade Tests', () {
    test('Manga with 100% completed progress downgrades when new chapter is added', () async {
      const slug = 'i-married-the-dragon-i-killed';
      const source = 'shinigami';

      // 1. User read Chapter 21 when total was 21 (100% complete)
      await LocalStorage.saveHistory(
        slug: slug,
        title: 'I Married The Dragon I Killed',
        cover: 'https://example.com/cover.jpg',
        chapterSlug: 'chapter-21',
        chapterTitle: 'Chapter 21',
        source: source,
        page: 20,
        totalPages: 20,
        percent: 1.0,
        totalChapters: 21,
        chapterNumber: 21,
      );

      // Verify initial state is 100%
      expect(LocalStorage.getHistoryProgress(slug, source: source), 1.0);
      final readBefore = LocalStorage.getReadChapters(slug, source: source);
      expect(readBefore.contains('chapter-21'), true);

      // 2. New Chapter 22 is released (total chapters becomes 22)
      // New chapter should be marked unread
      await LocalStorage.markChaptersAsUnread(slug, ['chapter-22'], source: source);

      // Progress should be updated to reflect 21/22 (~0.9545)
      final newProgress = (21.0 / 22.0);
      await LocalStorage.updateHistoryMetadata(
        slug: slug,
        source: source,
        percent: newProgress,
        totalChapters: 22,
      );

      // 3. Verify that progress is no longer 1.0 (not 100%)
      final updatedProgress = LocalStorage.getHistoryProgress(slug, source: source);
      expect(updatedProgress, closeTo(0.9545, 0.01));
      expect(updatedProgress < 0.99, true);

      // Verify Chapter 22 is NOT marked as read
      final readAfter = LocalStorage.getReadChapters(slug, source: source);
      expect(readAfter.contains('chapter-22'), false);
      expect(readAfter.contains('chapter-21'), true);
    });
  });
}
