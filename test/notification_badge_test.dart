import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:manga_app/shared/models/feed_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_badge');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Notification Badge & Total Unread Chapters Tests', () {
    test('getTotalUnreadNewChaptersCount sums chapter counts across multiple manga items', () async {
      final item1 = FeedItem(
        id: 'normal_manga_1_100',
        mangaSlug: 'manga-1',
        mangaTitle: 'Manga One',
        mangaSource: 'shinigami',
        newChaptersCount: 2,
        newChapters: ['Chapter 10', 'Chapter 11'],
        newChapterSlugs: ['ch-10', 'ch-11'],
        createdAt: 1000,
        isNew: true,
        modeId: 'normal',
      );

      final item2 = FeedItem(
        id: 'normal_manga_2_200',
        mangaSlug: 'manga-2',
        mangaTitle: 'Manga Two',
        mangaSource: 'bacakomik',
        newChaptersCount: 3,
        newChapters: ['Chapter 1', 'Chapter 2', 'Chapter 3'],
        newChapterSlugs: ['ch-1', 'ch-2', 'ch-3'],
        createdAt: 2000,
        isNew: true,
        modeId: 'normal',
      );

      await LocalStorage.addFeedItem(item1);
      await LocalStorage.addFeedItem(item2);

      // getUnreadFeedCount returns count of manga items = 2
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 2);

      // getTotalUnreadNewChaptersCount returns total new chapters = 2 + 3 = 5
      expect(LocalStorage.getTotalUnreadNewChaptersCount(modeId: 'normal'), 5);

      // User reads 1 chapter from manga-1 (ch-10)
      await LocalStorage.markChaptersAsRead('manga-1', ['ch-10'], source: 'shinigami', modeId: 'normal');

      // Now manga-1 has 1 unread chapter remaining, manga-2 has 3 -> total = 4
      expect(LocalStorage.getTotalUnreadNewChaptersCount(modeId: 'normal'), 4);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 2);

      // User reads ch-11 -> manga-1 is completely read
      await LocalStorage.markChaptersAsRead('manga-1', ['ch-11'], source: 'shinigami', modeId: 'normal');

      // manga-1 is now read (0), manga-2 has 3 -> total = 3
      expect(LocalStorage.getTotalUnreadNewChaptersCount(modeId: 'normal'), 3);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 1);

      // User marks manga-2 feed item as read directly
      await LocalStorage.markFeedItemAsRead('normal_manga_2_200');

      expect(LocalStorage.getTotalUnreadNewChaptersCount(modeId: 'normal'), 0);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 0);
    });

    test('Single chapter manga returns +1 count', () async {
      final singleItem = FeedItem(
        id: 'normal_single_1',
        mangaSlug: 'solo-leveling',
        mangaTitle: 'Solo Leveling',
        mangaSource: 'shinigami',
        newChaptersCount: 1,
        newChapters: ['Chapter 180'],
        newChapterSlugs: ['ch-180'],
        createdAt: 3000,
        isNew: true,
        modeId: 'normal',
      );

      await LocalStorage.addFeedItem(singleItem);

      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 1);
      expect(LocalStorage.getTotalUnreadNewChaptersCount(modeId: 'normal'), 1);
    });
  });
}
