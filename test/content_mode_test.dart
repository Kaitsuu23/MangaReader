import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:manga_app/shared/models/content_mode.dart';
import 'package:manga_app/shared/models/feed_item.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_content_mode_test');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Content Mode / Multiple Library Tests', () {
    test('Default content modes (Normal and Restricted) are initialized properly', () {
      final modes = LocalStorage.getContentModes();
      expect(modes.length, greaterThanOrEqualTo(2));

      final normalMode = modes.firstWhere((m) => m.id == ContentMode.defaultNormalId);
      expect(normalMode.name, 'Normal');
      expect(normalMode.isDeletable, false);

      final restrictedMode = modes.firstWhere((m) => m.id == ContentMode.defaultRestrictedId);
      expect(restrictedMode.name, 'Restricted');

      expect(LocalStorage.getActiveContentModeId(), ContentMode.defaultNormalId);
    });

    test('Data Isolation: Favorites and History are strictly isolated between modes', () async {
      // 1. In Normal mode, save a favorite and history item
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);
      await LocalStorage.saveFavorite(
        slug: 'one-piece',
        title: 'One Piece',
        cover: null,
        source: 'shinigami',
        category: 'Favorit',
      );
      await LocalStorage.saveHistory(
        slug: 'one-piece',
        title: 'One Piece',
        cover: null,
        chapterSlug: 'ch-100',
        chapterTitle: 'Chapter 100',
        source: 'shinigami',
        page: 15,
        totalPages: 20,
      );

      expect(LocalStorage.isFavorite('one-piece'), true);
      expect(LocalStorage.getFavorites().length, 1);
      expect(LocalStorage.getHistory().length, 1);
      expect(LocalStorage.getHistoryItem('one-piece')?['chapterSlug'], 'ch-100');

      // 2. Switch to Restricted mode
      await LocalStorage.setActiveContentModeId(ContentMode.defaultRestrictedId);

      // In Restricted mode, Normal data MUST NOT be visible!
      expect(LocalStorage.isFavorite('one-piece'), false);
      expect(LocalStorage.getFavorites().isEmpty, true);
      expect(LocalStorage.getHistory().isEmpty, true);
      expect(LocalStorage.getHistoryItem('one-piece'), isNull);

      // Save different data in Restricted mode
      await LocalStorage.saveFavorite(
        slug: 'berserk',
        title: 'Berserk',
        cover: null,
        source: 'kiryuu',
      );
      expect(LocalStorage.isFavorite('berserk'), true);
      expect(LocalStorage.isFavorite('one-piece'), false);

      // Switch back to Normal mode
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);
      expect(LocalStorage.isFavorite('one-piece'), true);
      expect(LocalStorage.isFavorite('berserk'), false);
    });

    test('Transfer Manga: Moves reading progress, bookmarks, and favorite without data loss', () async {
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);

      // Setup comic with favorite, bookmarks, and 65% progress in Normal mode
      await LocalStorage.saveFavorite(
        slug: 'solo-leveling',
        title: 'Solo Leveling',
        cover: null,
        source: 'softkomik',
        category: 'Manhwa',
      );
      await LocalStorage.toggleBookmark(
        slug: 'solo-leveling',
        chapterSlug: 'ch-120',
        chapterTitle: 'Chapter 120',
        mangaTitle: 'Solo Leveling',
        page: 13,
      );
      await LocalStorage.saveHistory(
        slug: 'solo-leveling',
        title: 'Solo Leveling',
        cover: null,
        chapterSlug: 'ch-120',
        chapterTitle: 'Chapter 120',
        source: 'softkomik',
        page: 13,
        totalPages: 20,
        percent: 0.65,
      );

      expect(LocalStorage.isFavorite('solo-leveling'), true);
      expect(LocalStorage.isBookmarked('solo-leveling', 'ch-120'), true);
      final normalHist = LocalStorage.getHistoryItem('solo-leveling');
      expect(normalHist?['percent'], 0.65);
      expect(normalHist?['chapterSlug'], 'ch-120');

      // Transfer to Restricted mode
      await LocalStorage.transferManga(
        slug: 'solo-leveling',
        fromModeId: ContentMode.defaultNormalId,
        toModeId: ContentMode.defaultRestrictedId,
      );

      // Verify removed from Normal mode
      expect(LocalStorage.isFavorite('solo-leveling'), false);
      expect(LocalStorage.isBookmarked('solo-leveling', 'ch-120'), false);
      expect(LocalStorage.getHistoryItem('solo-leveling'), isNull);

      // Switch to Restricted mode and verify 100% data fidelity
      await LocalStorage.setActiveContentModeId(ContentMode.defaultRestrictedId);
      expect(LocalStorage.isFavorite('solo-leveling'), true);
      expect(LocalStorage.isBookmarked('solo-leveling', 'ch-120'), true);

      final restrictedHist = LocalStorage.getHistoryItem('solo-leveling');
      expect(restrictedHist, isNotNull);
      expect(restrictedHist?['title'], 'Solo Leveling');
      expect(restrictedHist?['chapterSlug'], 'ch-120');
      expect(restrictedHist?['page'], 13);
      expect(restrictedHist?['totalPages'], 20);
      expect(restrictedHist?['percent'], 0.65);
    });

    test('Transfer Manga with Target Category assigns category and updates target mode categories', () async {
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);

      await LocalStorage.saveFavorite(
        slug: 'nano-machine',
        title: 'Nano Machine',
        cover: null,
        source: 'kiryuu',
        category: 'Action',
      );

      // Initially, Restricted mode has no categories
      expect(LocalStorage.getFavoriteCategories(modeId: ContentMode.defaultRestrictedId).isEmpty, true);

      // Transfer to Restricted mode with custom target category 'Manhwa Aksi'
      await LocalStorage.transferManga(
        slug: 'nano-machine',
        fromModeId: ContentMode.defaultNormalId,
        toModeId: ContentMode.defaultRestrictedId,
        targetCategory: 'Manhwa Aksi',
      );

      // Verify Restricted mode now has the category
      final targetCategories = LocalStorage.getFavoriteCategories(modeId: ContentMode.defaultRestrictedId);
      expect(targetCategories.contains('Manhwa Aksi'), true);

      // Verify comic favorite in Restricted mode has the new category
      final restrictedFav = LocalStorage.getFavorite('nano-machine', modeId: ContentMode.defaultRestrictedId);
      expect(restrictedFav, isNotNull);
      expect(restrictedFav?['category'], 'Manhwa Aksi');
      expect(restrictedFav?['categories'], ['Manhwa Aksi']);

      // Normal mode categories should remain unaffected
      final normalCategories = LocalStorage.getFavoriteCategories(modeId: ContentMode.defaultNormalId);
      expect(normalCategories.contains('Manhwa Aksi'), false);
    });

    test('Clear Mode Data resets only the specified mode and protects Normal mode', () async {
      // Setup data in Restricted mode
      await LocalStorage.setActiveContentModeId(ContentMode.defaultRestrictedId);
      await LocalStorage.saveFavorite(
        slug: 'overflow',
        title: 'Overflow',
        cover: null,
        source: 'doujindesu',
        category: 'Dewasa',
      );
      await LocalStorage.saveHistory(
        slug: 'overflow',
        title: 'Overflow',
        cover: null,
        chapterSlug: 'ch-1',
        chapterTitle: 'Chapter 1',
        source: 'doujindesu',
        page: 5,
        totalPages: 20,
      );

      // Also ensure Normal mode has data
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);
      await LocalStorage.saveFavorite(
        slug: 'naruto',
        title: 'Naruto',
        cover: null,
        source: 'komikindo',
      );

      expect(LocalStorage.getFavorites(modeId: ContentMode.defaultRestrictedId).length, 1);
      expect(LocalStorage.getHistory(modeId: ContentMode.defaultRestrictedId).length, 1);
      expect(LocalStorage.getFavorites(modeId: ContentMode.defaultNormalId).length, 1);

      // Attempt to clear Normal mode (safeguarded)
      await LocalStorage.clearModeData(ContentMode.defaultNormalId);
      expect(LocalStorage.getFavorites(modeId: ContentMode.defaultNormalId).length, 1);

      // Clear Restricted mode
      await LocalStorage.clearModeData(ContentMode.defaultRestrictedId);
      expect(LocalStorage.getFavorites(modeId: ContentMode.defaultRestrictedId).isEmpty, true);
      expect(LocalStorage.getHistory(modeId: ContentMode.defaultRestrictedId).isEmpty, true);
      expect(LocalStorage.getFavoriteCategories(modeId: ContentMode.defaultRestrictedId).isEmpty, true);

      // Normal mode data remains completely intact!
      expect(LocalStorage.getFavorites(modeId: ContentMode.defaultNormalId).length, 1);
      expect(LocalStorage.isFavorite('naruto', modeId: ContentMode.defaultNormalId), true);
    });

    test('Custom Content Mode CRUD: create, update, delete custom modes (Normal cannot be deleted)', () async {
      final initialModes = LocalStorage.getContentModes();
      final initialCount = initialModes.length;

      // Create new custom mode
      final created = await LocalStorage.createContentMode(
        name: 'Webtoon Library',
        description: 'Koleksi khusus webtoon berwarna',
        enabledSources: ['komikindo', 'softkomik'],
        disabledSources: ['shinigami'],
      );

      var modes = LocalStorage.getContentModes();
      expect(modes.length, initialCount + 1);
      expect(created.name, 'Webtoon Library');
      expect(created.isDeletable, true);

      // Update custom mode
      await LocalStorage.updateContentMode(created.id, name: 'Super Webtoons');
      modes = LocalStorage.getContentModes();
      expect(modes.firstWhere((m) => m.id == created.id).name, 'Super Webtoons');

      // Attempt to delete Normal mode (MUST FAIL / NOT BE DELETED)
      await LocalStorage.deleteContentMode(ContentMode.defaultNormalId);
      modes = LocalStorage.getContentModes();
      expect(modes.any((m) => m.id == ContentMode.defaultNormalId), true);

      // Delete custom mode
      await LocalStorage.deleteContentMode(created.id);
      modes = LocalStorage.getContentModes();
      expect(modes.any((m) => m.id == created.id), false);
    });

    test('All sources are enabled by default across all content modes', () {
      final modes = LocalStorage.getContentModes();
      for (final mode in modes) {
        expect(mode.disabledSources.isEmpty, true);
        expect(LocalStorage.isSourceEnabled('shinigami', modeId: mode.id), true);
        expect(LocalStorage.isSourceEnabled('doujindesu', modeId: mode.id), true);
        expect(LocalStorage.isSourceEnabled('komiktap', modeId: mode.id), true);
        expect(LocalStorage.isSourceEnabled('komiku', modeId: mode.id), true);
      }
    });

    test('Mode-scoped Sources Configuration', () async {
      await LocalStorage.setDisabledSources(['shinigami'], modeId: ContentMode.defaultRestrictedId);

      expect(LocalStorage.isSourceEnabled('shinigami', modeId: ContentMode.defaultNormalId), true);
      expect(LocalStorage.isSourceEnabled('shinigami', modeId: ContentMode.defaultRestrictedId), false);
    });

    test('Transfer Manga preserves exact reading position (scrollOffset, pageHeights, pageOffset, ratio) across slug variations', () async {
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);

      // Save history with rich reading position under raw slug
      const rawSlug = '/manga/job-cleaning-service/';
      const cleanSlug = 'job-cleaning-service';

      await LocalStorage.saveFavorite(
        slug: rawSlug,
        title: 'Job: Cleaning Service',
        cover: 'https://example.com/cover.jpg',
        source: 'shinigami',
        category: 'Manhwa',
      );

      await LocalStorage.saveHistory(
        slug: rawSlug,
        title: 'Job: Cleaning Service',
        cover: 'https://example.com/cover.jpg',
        source: 'shinigami',
        chapterSlug: 'chapter-71',
        chapterTitle: 'Bab 71',
        page: 8,
        totalPages: 25,
        pageOffset: 450.0,
        scrollOffset: 7850.0,
        pageOffsetRatio: 0.32,
        percent: 0.68,
        pageHeights: {0: 1200.0, 1: 1500.0, 7: 1400.0},
      );

      // Mark chapters as read
      await LocalStorage.markChaptersAsRead(rawSlug, ['chapter-70', 'chapter-71']);

      // Transfer manga from Normal to Restricted
      final transferred = await LocalStorage.transferManga(
        slug: rawSlug,
        fromModeId: ContentMode.defaultNormalId,
        toModeId: ContentMode.defaultRestrictedId,
        targetCategory: 'Manhwa 18+',
      );
      expect(transferred, true);

      // Switch to Restricted mode
      await LocalStorage.setActiveContentModeId(ContentMode.defaultRestrictedId);

      // Verify query via clean slug works and returns exact reading position
      final histClean = LocalStorage.getHistoryItem(cleanSlug);
      expect(histClean, isNotNull);
      expect(histClean?['chapterSlug'], 'chapter-71');
      expect(histClean?['page'], 8);
      expect(histClean?['pageOffset'], 450.0);
      expect(histClean?['scrollOffset'], 7850.0);
      expect(histClean?['pageOffsetRatio'], 0.32);
      expect(histClean?['percent'], 0.68);
      expect(histClean?['pageHeights'], isNotNull);
      expect((histClean?['pageHeights'] as Map)['7'], 1400.0);

      // Verify query via raw slug works too
      final histRaw = LocalStorage.getHistoryItem(rawSlug);
      expect(histRaw, isNotNull);
      expect(histRaw?['scrollOffset'], 7850.0);

      // Verify read chapters transferred
      final readChapters = LocalStorage.getReadChapters(cleanSlug);
      expect(readChapters.contains('chapter-70'), true);
      expect(readChapters.contains('chapter-71'), true);

      // Verify favorite transferred with new category
      final fav = LocalStorage.getFavorite(cleanSlug);
      expect(fav, isNotNull);
      expect(fav?['category'], 'Manhwa 18+');
    });

    test('Sync Settings Isolation: Each content mode has independent login state and sync credentials', () async {
      // 1. Log in Normal mode
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);
      await LocalStorage.setSyncServerUrl('https://sync.normal.com');
      await LocalStorage.setSyncEmail('user1@normal.com');
      await LocalStorage.setSyncToken('token_normal_123');
      await LocalStorage.setSyncEnabled(true);
      await LocalStorage.setSyncFavoritesEnabled(true);
      await LocalStorage.setSyncHistoryEnabled(false);
      await LocalStorage.setSyncPeriodHours(3);

      expect(LocalStorage.isSyncLoggedIn(), true);
      expect(LocalStorage.isSyncEnabled(), true);
      expect(LocalStorage.getSyncEmail(), 'user1@normal.com');
      expect(LocalStorage.getSyncToken(), 'token_normal_123');
      expect(LocalStorage.getSyncServerUrl(), 'https://sync.normal.com');
      expect(LocalStorage.isSyncFavoritesEnabled(), true);
      expect(LocalStorage.isSyncHistoryEnabled(), false);
      expect(LocalStorage.getSyncPeriodHours(), 3);

      // 2. Switch to Restricted mode
      await LocalStorage.setActiveContentModeId(ContentMode.defaultRestrictedId);

      // Restricted mode MUST be logged out by default
      expect(LocalStorage.isSyncLoggedIn(), false);
      expect(LocalStorage.isSyncEnabled(), false);
      expect(LocalStorage.getSyncEmail(), isNull);
      expect(LocalStorage.getSyncToken(), isNull);
      expect(LocalStorage.isSyncFavoritesEnabled(), true); // default true
      expect(LocalStorage.isSyncHistoryEnabled(), true); // default true

      // 3. Log in Restricted mode with a different account & custom server
      await LocalStorage.setSyncServerUrl('https://sync.restricted.com');
      await LocalStorage.setSyncEmail('user2@restricted.com');
      await LocalStorage.setSyncToken('token_restricted_456');
      await LocalStorage.setSyncEnabled(true);
      await LocalStorage.setSyncFavoritesEnabled(false);
      await LocalStorage.setSyncHistoryEnabled(true);
      await LocalStorage.setSyncPeriodHours(12);

      expect(LocalStorage.isSyncLoggedIn(), true);
      expect(LocalStorage.getSyncEmail(), 'user2@restricted.com');
      expect(LocalStorage.getSyncToken(), 'token_restricted_456');
      expect(LocalStorage.getSyncServerUrl(), 'https://sync.restricted.com');
      expect(LocalStorage.isSyncFavoritesEnabled(), false);
      expect(LocalStorage.isSyncHistoryEnabled(), true);
      expect(LocalStorage.getSyncPeriodHours(), 12);

      // 4. Verify Normal mode credentials remain untouched
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);
      expect(LocalStorage.isSyncLoggedIn(), true);
      expect(LocalStorage.getSyncEmail(), 'user1@normal.com');
      expect(LocalStorage.getSyncToken(), 'token_normal_123');
      expect(LocalStorage.getSyncServerUrl(), 'https://sync.normal.com');
      expect(LocalStorage.isSyncFavoritesEnabled(), true);
      expect(LocalStorage.isSyncHistoryEnabled(), false);
      expect(LocalStorage.getSyncPeriodHours(), 3);

      // 5. Logout from Restricted mode
      await LocalStorage.setSyncToken(null, modeId: ContentMode.defaultRestrictedId);
      await LocalStorage.setSyncEmail(null, modeId: ContentMode.defaultRestrictedId);
      await LocalStorage.setSyncEnabled(false, modeId: ContentMode.defaultRestrictedId);

      expect(LocalStorage.isSyncLoggedIn(modeId: ContentMode.defaultRestrictedId), false);
      expect(LocalStorage.getSyncEmail(modeId: ContentMode.defaultRestrictedId), isNull);

      // Normal mode still logged in
      expect(LocalStorage.isSyncLoggedIn(modeId: ContentMode.defaultNormalId), true);
      expect(LocalStorage.getSyncEmail(modeId: ContentMode.defaultNormalId), 'user1@normal.com');
    });

    test('Feed Updates Isolation: Display and operations in Feed match active content mode', () async {
      // 1. Add updates for Mode Normal
      await LocalStorage.addFeedItem(FeedItem(
        id: 'normal_item_1',
        mangaSlug: 'one-piece',
        mangaTitle: 'One Piece',
        mangaSource: 'shinigami',
        newChaptersCount: 1,
        newChapters: ['Chapter 1120'],
        createdAt: 1000,
        isNew: true,
        modeId: ContentMode.defaultNormalId,
        modeName: 'Normal',
      ));

      // 2. Add updates for Mode Restricted
      await LocalStorage.addFeedItem(FeedItem(
        id: 'restricted_item_1',
        mangaSlug: 'job-cleaning',
        mangaTitle: 'Job: Cleaning Service',
        mangaSource: 'shinigami',
        newChaptersCount: 2,
        newChapters: ['Bab 71', 'Bab 72'],
        createdAt: 2000,
        isNew: true,
        modeId: ContentMode.defaultRestrictedId,
        modeName: 'Restricted',
      ));

      // In Normal mode:
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);
      final normalItems = LocalStorage.getFeedItems();
      expect(normalItems.length, 1);
      expect(normalItems.first.mangaSlug, 'one-piece');
      expect(LocalStorage.getUnreadFeedCount(), 1);

      // In Restricted mode:
      await LocalStorage.setActiveContentModeId(ContentMode.defaultRestrictedId);
      final restrictedItems = LocalStorage.getFeedItems();
      expect(restrictedItems.length, 1);
      expect(restrictedItems.first.mangaSlug, 'job-cleaning');
      expect(LocalStorage.getUnreadFeedCount(), 1);

      // Mark all read in Normal mode
      await LocalStorage.markAllFeedItemsAsRead(modeId: ContentMode.defaultNormalId);
      expect(LocalStorage.getUnreadFeedCount(modeId: ContentMode.defaultNormalId), 0);
      expect(LocalStorage.getUnreadFeedCount(modeId: ContentMode.defaultRestrictedId), 1);

      // Clear feed in Normal mode
      await LocalStorage.clearFeed(modeId: ContentMode.defaultNormalId);
      expect(LocalStorage.getFeedItems(modeId: ContentMode.defaultNormalId).isEmpty, true);
      expect(LocalStorage.getFeedItems(modeId: ContentMode.defaultRestrictedId).length, 1);
    });

    test('Deletion Tombstones are properly recorded for both Normal and Restricted modes', () async {
      final restricted = ContentMode.defaultRestrictedId;

      // 1. Setup favorite and history in Restricted mode
      await LocalStorage.saveFavorite(
        slug: 'silent-war',
        title: 'Silent War',
        cover: 'https://example.com/cover.jpg',
        source: 'shinigami',
        modeId: restricted,
      );
      await LocalStorage.saveHistory(
        slug: 'silent-war',
        title: 'Silent War',
        cover: 'https://example.com/cover.jpg',
        source: 'shinigami',
        chapterSlug: 'ch-50',
        chapterTitle: 'Chapter 50',
        page: 10,
        totalPages: 25,
        modeId: restricted,
      );

      expect(LocalStorage.isFavorite('silent-war', modeId: restricted), true);
      expect(LocalStorage.getHistoryItem('silent-war', modeId: restricted), isNotNull);

      // 2. Delete favorite in Restricted mode
      await LocalStorage.removeFavorite('silent-war', recordTombstone: true, modeId: restricted);
      expect(LocalStorage.isFavorite('silent-war', modeId: restricted), false);
      final favTombstones = LocalStorage.getDeletedFavoriteTombstones(modeId: restricted);
      expect(favTombstones.any((t) => t['slug'] == 'silent-war'), true);

      // 3. Delete history in Restricted mode
      await LocalStorage.deleteHistoryItem('silent-war', recordTombstone: true, modeId: restricted);
      expect(LocalStorage.getHistoryItem('silent-war', modeId: restricted), isNull);
      final histTombstones = LocalStorage.getDeletedHistoryTombstones(modeId: restricted);
      expect(histTombstones.any((t) => t['slug'] == 'silent-war'), true);
    });

    test('Transfer Manga records deletion tombstones in source mode to prevent cloud resurrect', () async {
      final normal = ContentMode.defaultNormalId;
      final restricted = ContentMode.defaultRestrictedId;

      await LocalStorage.saveFavorite(
        slug: 'boarding-diary',
        title: 'Boarding Diary',
        cover: 'https://example.com/bd.jpg',
        source: 'shinigami',
        modeId: normal,
      );
      await LocalStorage.saveHistory(
        slug: 'boarding-diary',
        title: 'Boarding Diary',
        cover: 'https://example.com/bd.jpg',
        source: 'shinigami',
        chapterSlug: 'ch-1',
        chapterTitle: 'Chapter 1',
        page: 1,
        totalPages: 10,
        modeId: normal,
      );

      // Transfer from Normal to Restricted
      final ok = await LocalStorage.transferManga(
        slug: 'boarding-diary',
        fromModeId: normal,
        toModeId: restricted,
      );
      expect(ok, true);

      // Must exist in Restricted
      expect(LocalStorage.isFavorite('boarding-diary', modeId: restricted), true);
      expect(LocalStorage.getHistoryItem('boarding-diary', modeId: restricted), isNotNull);

      // Must be gone from Normal
      expect(LocalStorage.isFavorite('boarding-diary', modeId: normal), false);
      expect(LocalStorage.getHistoryItem('boarding-diary', modeId: normal), isNull);

      // Must have recorded tombstones in Normal mode!
      final normalFavTombstones = LocalStorage.getDeletedFavoriteTombstones(modeId: normal);
      expect(normalFavTombstones.any((t) => t['slug'] == 'boarding-diary'), true);
      final normalHistTombstones = LocalStorage.getDeletedHistoryTombstones(modeId: normal);
      expect(normalHistTombstones.any((t) => t['slug'] == 'boarding-diary'), true);
    });
  });
}
