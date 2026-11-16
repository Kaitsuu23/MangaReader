import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_history_sort_test');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Kotatsu Redo History Sorting & Timestamp Tests', () {
    test('saveHistory preserves passed createdAt and updatedAt timestamps', () async {
      final customCreatedAt = 1672531199000; // 2022-12-31
      final customUpdatedAt = 1704067199000; // 2023-12-31

      await LocalStorage.saveHistory(
        slug: 'manga-one',
        title: 'Manga One',
        cover: null,
        chapterSlug: 'ch-1',
        chapterTitle: 'Chapter 1',
        source: 'shinigami',
        page: 5,
        totalPages: 20,
        createdAt: customCreatedAt,
        updatedAt: customUpdatedAt,
      );

      final item = LocalStorage.getHistoryItem('manga-one');
      expect(item, isNotNull);
      expect(item!['createdAt'], customCreatedAt);
      expect(item['updatedAt'], customUpdatedAt);
    });

    test('getHistory properly ignores read_* keys', () async {
      await LocalStorage.saveHistory(
        slug: 'manga-a',
        title: 'Alpha Manga',
        cover: null,
        chapterSlug: 'ch-1',
        chapterTitle: 'Chapter 1',
        source: 'shinigami',
        page: 1,
        totalPages: 10,
      );

      await LocalStorage.markChapterAsRead('manga-a', 'ch-1');
      await LocalStorage.markChapterAsRead('manga-a', 'ch-2');

      final list = LocalStorage.getHistory();
      expect(list.length, 1);
      expect(list.first['slug'], 'manga-a');
    });

    test('All 8 Kotatsu sort orders sort history items accurately', () async {
      // Manga A: Oldest added, high progress, read recently
      await LocalStorage.saveHistory(
        slug: 'manga-a',
        title: 'Beta Manga',
        cover: null,
        chapterSlug: 'ch-10',
        chapterTitle: 'Chapter 10',
        source: 'shinigami',
        page: 10,
        totalPages: 10,
        percent: 0.9,
        createdAt: 1000,
        updatedAt: 5000,
      );

      // Manga B: Medium added, low progress, read long ago
      await LocalStorage.saveHistory(
        slug: 'manga-b',
        title: 'Alpha Manga',
        cover: null,
        chapterSlug: 'ch-1',
        chapterTitle: 'Chapter 1',
        source: 'shinigami',
        page: 1,
        totalPages: 10,
        percent: 0.1,
        createdAt: 2000,
        updatedAt: 3000,
      );

      // Manga C: Newest added, medium progress, read very recently
      await LocalStorage.saveHistory(
        slug: 'manga-c',
        title: 'Charlie Manga',
        cover: null,
        chapterSlug: 'ch-5',
        chapterTitle: 'Chapter 5',
        source: 'shinigami',
        page: 5,
        totalPages: 10,
        percent: 0.5,
        createdAt: 3000,
        updatedAt: 8000,
      );

      // 1. LAST_READ (updatedAt DESC): C (8000), A (5000), B (3000)
      final lastRead = LocalStorage.getHistory(sortOrder: 'last_read');
      expect(lastRead.map((m) => m['slug']).toList(), ['manga-c', 'manga-a', 'manga-b']);

      // 2. LONG_AGO_READ (updatedAt ASC): B (3000), A (5000), C (8000)
      final longAgo = LocalStorage.getHistory(sortOrder: 'long_ago_read');
      expect(longAgo.map((m) => m['slug']).toList(), ['manga-b', 'manga-a', 'manga-c']);

      // 3. NEWEST (createdAt DESC): C (3000), B (2000), A (1000)
      final newest = LocalStorage.getHistory(sortOrder: 'newest');
      expect(newest.map((m) => m['slug']).toList(), ['manga-c', 'manga-b', 'manga-a']);

      // 4. OLDEST (createdAt ASC): A (1000), B (2000), C (3000)
      final oldest = LocalStorage.getHistory(sortOrder: 'oldest');
      expect(oldest.map((m) => m['slug']).toList(), ['manga-a', 'manga-b', 'manga-c']);

      // 5. PROGRESS (percent DESC): A (0.9), C (0.5), B (0.1)
      final progress = LocalStorage.getHistory(sortOrder: 'progress');
      expect(progress.map((m) => m['slug']).toList(), ['manga-a', 'manga-c', 'manga-b']);

      // 6. UNREAD (percent ASC): B (0.1), C (0.5), A (0.9)
      final unread = LocalStorage.getHistory(sortOrder: 'unread');
      expect(unread.map((m) => m['slug']).toList(), ['manga-b', 'manga-c', 'manga-a']);

      // 7. TITLE_ASC: Alpha (B), Beta (A), Charlie (C)
      final titleAsc = LocalStorage.getHistory(sortOrder: 'title_asc');
      expect(titleAsc.map((m) => m['slug']).toList(), ['manga-b', 'manga-a', 'manga-c']);

      // 8. TITLE_DESC: Charlie (C), Beta (A), Alpha (B)
      final titleDesc = LocalStorage.getHistory(sortOrder: 'title_desc');
      expect(titleDesc.map((m) => m['slug']).toList(), ['manga-c', 'manga-a', 'manga-b']);
    });
  });
}
