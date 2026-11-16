import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:manga_app/shared/models/feed_item.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_feed_sync');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Feed Item Read Status & Sync Tests', () {
    test('Feed item is unread when added, and becomes read after chapter is read in history', () async {
      const slug = 'i-married-the-dragon-i-killed';
      const source = 'shinigami';

      final feedItem = FeedItem(
        id: 'normal_${slug}_12345',
        mangaSlug: slug,
        mangaTitle: 'I Married The Dragon I Killed',
        mangaCover: 'https://example.com/cover.jpg',
        mangaSource: source,
        newChaptersCount: 1,
        newChapters: ['Chapter 22'],
        newChapterSlugs: ['chapter-22'],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isNew: true,
        modeId: 'normal',
        modeName: 'Normal',
      );

      await LocalStorage.addFeedItem(feedItem);

      // Verify feed item is initially unread
      expect(LocalStorage.isFeedItemUnread(feedItem), true);
      expect(LocalStorage.getUnreadNewChaptersCount(feedItem), 1);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 1);

      // User reads Chapter 22 (saveHistory or markChaptersAsRead)
      await LocalStorage.saveHistory(
        slug: slug,
        title: 'I Married The Dragon I Killed',
        cover: 'https://example.com/cover.jpg',
        chapterSlug: 'chapter-22',
        chapterTitle: 'Chapter 22',
        source: source,
        page: 15,
        totalPages: 15,
        modeId: 'normal',
      );

      // Verify that after reading, feed item is recognized as read
      final itemsAfter = LocalStorage.getFeedItems(modeId: 'normal');
      expect(itemsAfter.isNotEmpty, true);
      final updatedItem = itemsAfter.first;

      expect(LocalStorage.isFeedItemUnread(updatedItem), false);
      expect(LocalStorage.getUnreadNewChaptersCount(updatedItem), 0);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 0);
      expect(updatedItem.isNew, false);
    });

    test('Multi-chapter feed item decrements unread count as chapters are read', () async {
      const slug = 'martial-peak';
      const source = 'komiku';

      final feedItem = FeedItem(
        id: 'normal_${slug}_67890',
        mangaSlug: slug,
        mangaTitle: 'Martial Peak',
        mangaSource: source,
        newChaptersCount: 2,
        newChapters: ['Chapter 50', 'Chapter 51'],
        newChapterSlugs: ['chapter-50', 'chapter-51'],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isNew: true,
        modeId: 'normal',
        modeName: 'Normal',
      );

      await LocalStorage.addFeedItem(feedItem);

      expect(LocalStorage.getUnreadNewChaptersCount(feedItem), 2);
      expect(LocalStorage.isFeedItemUnread(feedItem), true);

      // User reads only Chapter 50
      await LocalStorage.markChaptersAsRead(slug, ['chapter-50'], source: source, modeId: 'normal');

      expect(LocalStorage.getUnreadNewChaptersCount(feedItem), 1);
      expect(LocalStorage.isFeedItemUnread(feedItem), true);

      // User reads Chapter 51
      await LocalStorage.markChaptersAsRead(slug, ['chapter-51'], source: source, modeId: 'normal');

      expect(LocalStorage.getUnreadNewChaptersCount(feedItem), 0);
      expect(LocalStorage.isFeedItemUnread(feedItem), false);
    });

    test('markFeedItemAsRead directly marks item as read and clears unread count', () async {
      const slug = 'solo-leveling';
      const source = 'shinigami';

      final feedItem = FeedItem(
        id: 'normal_${slug}_99999',
        mangaSlug: slug,
        mangaTitle: 'Solo Leveling',
        mangaSource: source,
        newChaptersCount: 1,
        newChapters: ['Chapter 100'],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isNew: true,
        modeId: 'normal',
      );

      await LocalStorage.addFeedItem(feedItem);
      expect(LocalStorage.isFeedItemUnread(feedItem), true);

      await LocalStorage.markFeedItemAsRead(feedItem.id);

      final items = LocalStorage.getFeedItems(modeId: 'normal');
      expect(items.first.isNew, false);
      expect(LocalStorage.isFeedItemUnread(items.first), false);
      expect(LocalStorage.getUnreadNewChaptersCount(items.first), 0);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 0);
    });

    test('Previously completed manga (100% percent in history) shows new chapters as unread in Pembaruan Terkini', () async {
      const slug = 'youre-the-only-one-i-can-see';
      const source = 'shinigami';

      // History has 100% read progress on Chapter 34
      await LocalStorage.saveHistory(
        slug: slug,
        title: "You're the Only One I Can See",
        cover: 'https://example.com/cover.jpg',
        chapterSlug: 'chapter-34',
        chapterTitle: 'Chapter 34',
        chapterNumber: 34,
        source: source,
        page: 20,
        totalPages: 20,
        percent: 1.0,
        totalChapters: 34,
        modeId: 'normal',
      );
      await LocalStorage.markChaptersAsRead(slug, ['chapter-34'], source: source, modeId: 'normal');

      // Now Chapter 35 arrives as a new chapter
      final feedItem = FeedItem(
        id: 'normal_${slug}_353535',
        mangaSlug: slug,
        mangaTitle: "You're the Only One I Can See",
        mangaCover: 'https://example.com/cover.jpg',
        mangaSource: source,
        newChaptersCount: 1,
        newChapters: ['Chapter 35'],
        newChapterSlugs: ['chapter-35'],
        createdAt: DateTime.now().millisecondsSinceEpoch - 180000, // 3 minutes ago
        isNew: true,
        modeId: 'normal',
        modeName: 'Normal',
      );
      await LocalStorage.addFeedItem(feedItem);

      // Verify it is NOT considered read just because previous history percent was 1.0
      expect(LocalStorage.getUnreadNewChaptersCount(feedItem), 1);
      expect(LocalStorage.isFeedItemUnread(feedItem), true);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 1);

      // Verify syncAllFeedItemsReadStatus preserves / heals isNew=true
      await LocalStorage.syncAllFeedItemsReadStatus(modeId: 'normal');
      final feedItems = LocalStorage.getFeedItems(modeId: 'normal');
      expect(feedItems.first.isNew, true);
      expect(LocalStorage.isFeedItemUnread(feedItems.first), true);

      // Now user actually reads Chapter 35
      await LocalStorage.saveHistory(
        slug: slug,
        title: "You're the Only One I Can See",
        cover: 'https://example.com/cover.jpg',
        chapterSlug: 'chapter-35',
        chapterTitle: 'Chapter 35',
        chapterNumber: 35,
        source: source,
        page: 20,
        totalPages: 20,
        percent: 1.0,
        totalChapters: 35,
        modeId: 'normal',
      );

      final itemsAfterRead = LocalStorage.getFeedItems(modeId: 'normal');
      expect(LocalStorage.getUnreadNewChaptersCount(itemsAfterRead.first), 0);
      expect(LocalStorage.isFeedItemUnread(itemsAfterRead.first), false);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 0);
    });

    test('Manga with inflated chapterNumber in history (e.g. from prologue offset) keeps new chapter unread in Pembaruan Terkini', () async {
      const slug = 'im-being-misunderstood-as-a-soccer-genius';
      const source = 'softkomik';

      // History was saved with chapterNumber: 100 because chIdx was 99 (prologue at index 0)
      // but chapterSlug was '99' and chapterTitle was 'Chapter 99'
      await LocalStorage.saveHistory(
        slug: slug,
        title: "I'm Being Misunderstood as a Soccer Genius",
        cover: 'https://example.com/soccer.jpg',
        chapterSlug: '99',
        chapterTitle: 'Chapter 99',
        chapterNumber: 100,
        source: source,
        page: 10,
        totalPages: 10,
        percent: 0.99,
        totalChapters: 99,
        modeId: 'normal',
      );
      await LocalStorage.markChaptersAsRead(slug, ['99', 'chapter-99'], source: source, modeId: 'normal');

      // Now Chapter 100 actually arrives
      final feedItem = FeedItem(
        id: 'normal_${slug}_100100',
        mangaSlug: slug,
        mangaTitle: "I'm Being Misunderstood as a Soccer Genius",
        mangaCover: 'https://example.com/soccer.jpg',
        mangaSource: source,
        newChaptersCount: 1,
        newChapters: ['Chapter 100'],
        newChapterSlugs: ['100'],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isNew: true,
        modeId: 'normal',
        modeName: 'Normal',
      );
      await LocalStorage.addFeedItem(feedItem);

      // Verify Chapter 100 is NOT treated as read by historyNum >= chNum!
      expect(LocalStorage.getUnreadNewChaptersCount(feedItem), 1);
      expect(LocalStorage.isFeedItemUnread(feedItem), true);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 1);

      // Verify syncAllFeedItemsReadStatus preserves isNew=true
      await LocalStorage.syncAllFeedItemsReadStatus(modeId: 'normal');
      final feedItems = LocalStorage.getFeedItems(modeId: 'normal');
      expect(feedItems.first.isNew, true);
      expect(LocalStorage.isFeedItemUnread(feedItems.first), true);

      // Once the user actually reads Chapter 100:
      await LocalStorage.saveHistory(
        slug: slug,
        title: "I'm Being Misunderstood as a Soccer Genius",
        cover: 'https://example.com/soccer.jpg',
        chapterSlug: '100',
        chapterTitle: 'Chapter 100',
        chapterNumber: 100,
        source: source,
        page: 10,
        totalPages: 10,
        percent: 1.0,
        totalChapters: 100,
        modeId: 'normal',
      );

      final itemsAfterRead = LocalStorage.getFeedItems(modeId: 'normal');
      expect(LocalStorage.getUnreadNewChaptersCount(itemsAfterRead.first), 0);
      expect(LocalStorage.isFeedItemUnread(itemsAfterRead.first), false);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 0);
    });

    test('New chapter read before feed check is recognized as read and does not remain unread', () async {
      const slug = 'kanojo-okarishimasu';
      const source = 'komiku';

      // 1. Set baseline at Chapter 448
      await LocalStorage.saveTrackBaseline(
        slug,
        lastChapterSlug: 'ch-448',
        totalChapters: 448,
        modeId: 'normal',
      );

      // 2. User reads Chapter 449 before checking feed
      await LocalStorage.saveHistory(
        slug: slug,
        title: 'Kanojo Okarishimasu',
        cover: null,
        chapterSlug: 'ch-449',
        chapterTitle: 'Bab 449',
        chapterNumber: 449,
        source: source,
        page: 20,
        totalPages: 20,
        percent: 1.0,
        totalChapters: 449,
        modeId: 'normal',
      );
      await LocalStorage.markChaptersAsRead(slug, ['ch-449'], source: source, modeId: 'normal');

      // 3. Verify isChapterReadMatch recognizes Chapter 449 as read
      final readChapters = LocalStorage.getReadChapters(slug, source: source, modeId: 'normal').toSet();
      final history = LocalStorage.getHistoryItem(slug, source: source, modeId: 'normal');
      expect(
        LocalStorage.isChapterReadMatch(
          title: 'Bab 449',
          slug: 'ch-449',
          readChapters: readChapters,
          history: history,
        ),
        true,
      );

      // 4. If a FeedItem with Chapter 449 was evaluated, it is immediately recognized as read
      final feedItem = FeedItem(
        id: 'normal_${slug}_449',
        mangaSlug: slug,
        mangaTitle: 'Kanojo Okarishimasu',
        mangaSource: source,
        newChaptersCount: 1,
        newChapters: ['Bab 449'],
        newChapterSlugs: ['ch-449'],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isNew: true,
        modeId: 'normal',
      );
      await LocalStorage.addFeedItem(feedItem);

      await LocalStorage.syncFeedItemsReadStatus(slug: slug, source: source, modeId: 'normal');
      final feedItems = LocalStorage.getFeedItems(modeId: 'normal');
      expect(feedItems.first.isNew, false);
      expect(LocalStorage.isFeedItemUnread(feedItems.first), false);
      expect(LocalStorage.getUnreadNewChaptersCount(feedItems.first), 0);
      expect(LocalStorage.getUnreadFeedCount(modeId: 'normal'), 0);
    });

    test('migrateFeedAndTrackBaseline migrates feed items and tracker baseline to new source/slug', () async {
      const oldSlug = 'nano-machine-error';
      const oldSource = 'komikcast';
      const newSlug = 'nano-machine-working';
      const newSource = 'shinigami';
      const title = 'Nano Machine';

      // 1. Setup old baseline and feed item
      await LocalStorage.saveTrackBaseline(
        oldSlug,
        lastChapterSlug: 'ch-200',
        totalChapters: 200,
        modeId: 'normal',
      );

      final feedItem = FeedItem(
        id: 'normal_${oldSlug}_99999',
        mangaSlug: oldSlug,
        mangaTitle: title,
        mangaSource: oldSource,
        newChaptersCount: 1,
        newChapters: ['Chapter 201'],
        newChapterSlugs: ['chapter-201'],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isNew: true,
        modeId: 'normal',
      );
      await LocalStorage.addFeedItem(feedItem);

      // Verify baseline and feed item exist for old slug
      expect(LocalStorage.getTrackBaseline(oldSlug, modeId: 'normal')?['totalChapters'], 200);
      expect(LocalStorage.getFeedItems(modeId: 'normal').first.mangaSource, oldSource);

      // 2. Perform migration
      await LocalStorage.migrateFeedAndTrackBaseline(
        oldSlug: oldSlug,
        oldSource: oldSource,
        newSlug: newSlug,
        newSource: newSource,
        newTitle: title,
        modeId: 'normal',
      );

      // 3. Verify baseline migrated
      expect(LocalStorage.getTrackBaseline(oldSlug, modeId: 'normal'), isNull);
      expect(LocalStorage.getTrackBaseline(newSlug, modeId: 'normal')?['totalChapters'], 200);

      // 4. Verify feed item migrated
      final updatedFeed = LocalStorage.getFeedItems(modeId: 'normal');
      expect(updatedFeed.length, 1);
      expect(updatedFeed.first.mangaSlug, newSlug);
      expect(updatedFeed.first.mangaSource, newSource);
      expect(updatedFeed.first.mangaTitle, title);
    });

    test('resolveMigratedFeedItem automatically resolves orphaned feed items from favorites', () async {
      const oldSlug = 'nano-machine-broken';
      const oldSource = 'broken_source';
      const newSlug = 'nano-machine-ok';
      const newSource = 'shinigami';
      const title = 'Nano Machine';

      // 1. Setup favorite on new source (as done by AlternativesScreen migration)
      await LocalStorage.saveFavorite(
        slug: newSlug,
        title: title,
        cover: 'https://example.com/cover.jpg',
        source: newSource,
        modeId: 'normal',
      );

      // 2. Old feed item still referencing broken source
      final oldFeedItem = FeedItem(
        id: 'normal_${oldSlug}_88888',
        mangaSlug: oldSlug,
        mangaTitle: title,
        mangaSource: oldSource,
        newChaptersCount: 1,
        newChapters: ['Chapter 201'],
        newChapterSlugs: ['chapter-201'],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isNew: true,
        modeId: 'normal',
      );
      await LocalStorage.addFeedItem(oldFeedItem);

      // 3. resolveMigratedFeedItem directly
      final resolved = LocalStorage.resolveMigratedFeedItem(oldFeedItem, modeId: 'normal');
      expect(resolved, isNotNull);
      expect(resolved!.mangaSlug, newSlug);
      expect(resolved.mangaSource, newSource);

      // 4. getFeedItems automatically heals and returns resolved item
      final items = LocalStorage.getFeedItems(modeId: 'normal');
      expect(items.first.mangaSlug, newSlug);
      expect(items.first.mangaSource, newSource);
    });
  });
}
