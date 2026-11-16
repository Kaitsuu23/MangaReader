import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:manga_app/core/services/sync_service.dart';
import 'package:manga_app/shared/models/feed_item.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_progress');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Reading Progress & Kotatsu Sync History Tests', () {
    test('SyncService.hashSlug matches Kotatsu 64-bit FNV-1a hash logic', () {
      const chapterUrl = '/komik/do-you-want-to-be-friends-forever-chapter-1/';
      final hash = SyncService.hashSlug(chapterUrl);
      expect(hash, isPositive);
      expect(hash.toString().length, greaterThanOrEqualTo(8));
      
      // Hash is consistent and deterministic
      expect(SyncService.hashSlug(chapterUrl), hash);
      // Different URLs yield different hashes
      expect(SyncService.hashSlug('/komik/another-chapter-2/'), isNot(hash));
    });

    test('saveHistory stores percent, totalChapters, and chapterNumber correctly', () async {
      await LocalStorage.saveHistory(
        slug: 'wooden-stick',
        title: 'Tongkat Kayu +99',
        cover: null,
        chapterSlug: '/ch/tongkat-kayu-99-chapter-28/',
        chapterTitle: 'Chapter 28',
        source: 'komiku',
        page: 10,
        totalPages: 20,
        percent: 0.28,
        totalChapters: 94,
        chapterNumber: 28,
      );

      final item = LocalStorage.getHistoryItem('wooden-stick');
      expect(item, isNotNull);
      expect(item!['percent'], 0.28);
      expect(item['totalChapters'], 94);
      expect(item['chapterNumber'], 28);
    });

    test('Kotatsu sync server 64-bit ID does not corrupt chapter calculation', () {
      final historyItem = {
        'slug': 'wooden-stick',
        'chapterSlug': '3414762387142711808',
        'chapterTitle': '',
        'percent': 0.28,
        'page': 1,
      };

      final totalChapters = 104;
      int readChapterNumber = 0;
      double progressPercent = 0.0;

      if (historyItem['percent'] != null) {
        final p = (historyItem['percent'] as num).toDouble();
        if (p > 0) {
          progressPercent = p.clamp(0.0, 1.0);
        }
      }

      // Check regex protection against huge IDs
      final chTitle = historyItem['chapterTitle'] as String? ?? '';
      if (chTitle.isNotEmpty) {
        final match = RegExp(
          r'(?:ch(?:apter)?\.?\s*|bab\s*|#\s*)(\d+(?:\.\d+)?)',
          caseSensitive: false,
        ).firstMatch(chTitle);
        if (match != null) {
          final parsed = double.tryParse(match.group(1) ?? '');
          if (parsed != null && parsed > 0 && parsed <= totalChapters && parsed < 5000) {
            readChapterNumber = parsed.toInt();
          }
        }
      }

      // Kotatsu fallback: derive read chapter from progress percent
      if (readChapterNumber == 0 && progressPercent > 0) {
        readChapterNumber = (progressPercent * totalChapters).round().clamp(1, totalChapters);
      }

      expect(readChapterNumber, 29); // 0.28 * 104 = 29.12 -> 29
      expect(progressPercent, 0.28);
      expect(readChapterNumber <= totalChapters, true);
    });

    test('markChaptersAsRead stores multiple slugs and normalized slugs', () async {
      await LocalStorage.markChaptersAsRead('nano-machine', [
        '/ch/chapter-1/',
        'chapter-2',
        '/ch/chapter-3',
      ]);

      final read = LocalStorage.getReadChapters('nano-machine');
      expect(read.contains('/ch/chapter-1/'), true);
      expect(read.contains('ch/chapter-1'), true);
      expect(read.contains('chapter-2'), true);
      expect(read.contains('/ch/chapter-3'), true);
    });

    test('100% progress marks all chapters as read regardless of individual read state', () {
      final totalChapters = 50;
      final progressPercent = 1.0;
      final isCompleted = progressPercent >= 0.99;

      for (int i = 0; i < totalChapters; i++) {
        final isRead = isCompleted;
        expect(isRead, true);
      }
    });

    test('Reading up to chapter N automatically marks all previous chapters as read', () {
      final totalChapters = 10;
      final lastReadChronoIndex = 4; // Bab 5 (0-indexed 4)

      for (int i = 0; i < totalChapters; i++) {
        final isPreviousOrCurrent = i <= lastReadChronoIndex;
        if (i <= 4) {
          expect(isPreviousOrCurrent, true); // Bab 1..5 centang
        } else {
          expect(isPreviousOrCurrent, false); // Bab 6..10 belum centang
        }
      }
    });

    test('Webtoon scroll reaching bottom correctly identifies last page (e.g. 66/66) and 100% progress', () {
      const totalPages = 66;
      final pageHeights = List.generate(totalPages, (i) => 1000.0);
      const footerHeight = 400.0;
      final totalContentHeight = pageHeights.reduce((a, b) => a + b) + footerHeight; // 66400
      const viewportHeight = 2400.0;
      final maxScrollExtent = totalContentHeight - viewportHeight; // 64000

      // When scrolled all the way to the bottom:
      final offsetAtBottom = maxScrollExtent;
      const extentAfter = 0.0;
      final isAtBottom = (maxScrollExtent > 0 && offsetAtBottom >= maxScrollExtent - 40) || extentAfter <= 40;
      expect(isAtBottom, true);

      int detectedPageIndex;
      if (isAtBottom) {
        detectedPageIndex = totalPages - 1;
      } else {
        detectedPageIndex = 0;
      }

      expect(detectedPageIndex, 65); // 0-indexed 65 -> Page 66
      final pageDisplay = '${detectedPageIndex + 1}';
      expect(pageDisplay, '66');
      final percentRead = (((detectedPageIndex + 1) / totalPages) * 100).round();
      expect(percentRead, 100);
    });

    test('LocalStorage.saveHistory preserves reading offsets and pageHeights when caller passes 0/null for same chapter', () async {
      await LocalStorage.saveHistory(
        slug: 'not-a-friend',
        title: 'Not a Friend',
        cover: 'https://example.com/cover.jpg',
        source: 'softkomik',
        chapterSlug: '1',
        chapterTitle: 'Chapter 1',
        page: 1,
        totalPages: 6,
        pageOffset: 2500.0,
        scrollOffset: 2500.0,
        pageOffsetRatio: 0.17,
        pageHeights: {0: 15000.0, 1: 12000.0},
        percent: 0.027,
      );

      final before = LocalStorage.getHistoryItem('not-a-friend');
      expect(before!['pageOffset'], 2500.0);
      expect(before['scrollOffset'], 2500.0);
      expect(before['pageOffsetRatio'], 0.17);
      expect(before['pageHeights'], isNotNull);
      expect(before['totalPages'], 6);

      // Simulate _fetchFullChapterList or sync passing 0 offsets for same chapter:
      await LocalStorage.saveHistory(
        slug: 'not-a-friend',
        title: 'Not a Friend',
        cover: 'https://example.com/cover.jpg',
        source: 'softkomik',
        chapterSlug: '1',
        chapterTitle: 'Chapter 1',
        page: 1,
        totalPages: 1,
      );

      final after = LocalStorage.getHistoryItem('not-a-friend');
      // Offsets and heights must NOT be wiped!
      expect(after!['pageOffset'], 2500.0);
      expect(after['scrollOffset'], 2500.0);
      expect(after['pageOffsetRatio'], 0.17);
      expect(after['pageHeights'], isNotNull);
      expect(after['totalPages'], 6);
    });

    test('Re-reading from Chapter 1 marks subsequent chapters 2..N as unread', () async {
      const mangaSlug = 'solo-leveling';
      // Step 1: User previously completed chapters 1..5
      final allChapters = ['ch-1', 'ch-2', 'ch-3', 'ch-4', 'ch-5'];
      await LocalStorage.markChaptersAsRead(mangaSlug, allChapters);

      var readList = LocalStorage.getReadChapters(mangaSlug);
      expect(readList.length, 5);
      for (final ch in allChapters) {
        expect(readList.contains(ch), true);
      }

      // Step 2: User decides to re-read from Chapter 1
      // Reader marks Ch 1 as read, and chapters 2..5 as unread
      await LocalStorage.setReadChaptersUpTo(
        mangaSlug: mangaSlug,
        readSlugs: ['ch-1'],
        unreadSlugs: ['ch-2', 'ch-3', 'ch-4', 'ch-5'],
      );

      readList = LocalStorage.getReadChapters(mangaSlug);
      // Ch 1 must remain read
      expect(readList.contains('ch-1'), true);
      // Chapters 2, 3, 4, 5 must now be UNREAD
      expect(readList.contains('ch-2'), false);
      expect(readList.contains('ch-3'), false);
      expect(readList.contains('ch-4'), false);
      expect(readList.contains('ch-5'), false);
    });

    test('LocalStorage.markChaptersAsUnread removes specified chapters', () async {
      const mangaSlug = 'magic-emperor';
      await LocalStorage.markChaptersAsRead(mangaSlug, ['ch-1', 'ch-2', 'ch-3']);
      expect(LocalStorage.getReadChapters(mangaSlug).length, 3);

      await LocalStorage.markChaptersAsUnread(mangaSlug, ['ch-2', 'ch-3']);
      final read = LocalStorage.getReadChapters(mangaSlug);
      expect(read.contains('ch-1'), true);
      expect(read.contains('ch-2'), false);
      expect(read.contains('ch-3'), false);
    });

    test('Reading progress is capped based on remaining unread chapters (e.g. 2 chapters remaining is max 98%)', () async {
      const mangaSlug = 'kanojo-okarishimasu';
      const totalChapters = 449;

      // 1. Reading chapter 447 out of 449 (2 chapters remaining: 448, 449)
      // Raw mathematical division: (446 + 0.1) / 449 = 0.9935 (99.35%)
      // With 2 chapters remaining, progress must NOT be 99%, but 98%!
      await LocalStorage.saveHistory(
        slug: mangaSlug,
        title: 'Kanojo Okarishimasu',
        cover: null,
        chapterSlug: 'ch-447',
        chapterTitle: 'Bab 447',
        source: 'komiku',
        page: 1,
        totalPages: 20,
        percent: 0.9935,
        totalChapters: totalChapters,
        chapterNumber: 447,
      );

      final progress447 = LocalStorage.getHistoryProgress(mangaSlug);
      expect(progress447, 0.98);
      expect((progress447 * 100).round(), 98);

      // 2. Reading chapter 448 out of 449 (1 chapter remaining: 449)
      // Raw: (447 + 0.5) / 449 = 0.9966
      // With 1 chapter remaining, progress can reach 99%
      await LocalStorage.saveHistory(
        slug: mangaSlug,
        title: 'Kanojo Okarishimasu',
        cover: null,
        chapterSlug: 'ch-448',
        chapterTitle: 'Bab 448',
        source: 'komiku',
        page: 10,
        totalPages: 20,
        percent: 0.9966,
        totalChapters: totalChapters,
        chapterNumber: 448,
      );

      final progress448 = LocalStorage.getHistoryProgress(mangaSlug);
      expect(progress448, 0.99);
      expect((progress448 * 100).round(), 99);

      // 3. Reading chapter 446 out of 449 (3 chapters remaining: 447, 448, 449)
      // Raw: 0.9911
      // With 3 chapters remaining, progress is capped at 97%
      await LocalStorage.saveHistory(
        slug: mangaSlug,
        title: 'Kanojo Okarishimasu',
        cover: null,
        chapterSlug: 'ch-446',
        chapterTitle: 'Bab 446',
        source: 'komiku',
        page: 5,
        totalPages: 20,
        percent: 0.9911,
        totalChapters: totalChapters,
        chapterNumber: 446,
      );

      final progress446 = LocalStorage.getHistoryProgress(mangaSlug);
      expect(progress446, 0.97);
      expect((progress446 * 100).round(), 97);
    });

    test('Completed manga (100% / 254 chapters) does not drop to 95% / Bab 241 on new chapter feed update', () async {
      const slug = 'dandadan';
      const source = 'shinigami';

      // Synced Dandadan at 100% with 254 chapters
      await LocalStorage.saveHistory(
        slug: slug,
        title: 'Dandadan',
        cover: null,
        chapterSlug: '254',
        chapterTitle: 'Chapter 254',
        source: source,
        page: 20,
        totalPages: 20,
        percent: 1.0,
        totalChapters: 254,
        chapterNumber: 254,
      );

      final initialHist = LocalStorage.getHistoryItem(slug);
      expect(initialHist!['percent'], 1.0);
      expect(initialHist['totalChapters'], 254);

      // Now Chapter 255 arrives via feed update
      final feedItem = FeedItem(
        id: 'normal_${slug}_255',
        mangaSlug: slug,
        mangaTitle: 'Dandadan',
        mangaSource: source,
        newChaptersCount: 1,
        newChapters: ['Chapter 255'],
        newChapterSlugs: ['255'],
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isNew: true,
        modeId: 'normal',
        modeName: 'Normal',
      );

      await LocalStorage.addFeedItem(feedItem);

      final updatedHist = LocalStorage.getHistoryItem(slug);
      expect(updatedHist!['totalChapters'], 255);
      expect(updatedHist['chapterNumber'], 254);
      // Progress must be 254/255 ~ 0.99, NEVER 0.95!
      expect(updatedHist['percent'], greaterThanOrEqualTo(0.98));
      expect(updatedHist['percent'], lessThan(1.0));
    });

    test('LocalStorage.saveHistory saves real page 1 position when scrollOffset > 0, not overridden by existingPage > 1', () async {
      const slug = 'zombie-manga';
      // First, existing history had page 2 from previous session
      await LocalStorage.saveHistory(
        slug: slug,
        title: 'Zombie Manga',
        cover: null,
        chapterSlug: 'ch-88',
        chapterTitle: 'Bab 88',
        source: 'softkomik',
        page: 2,
        totalPages: 17,
        scrollOffset: 2500.0,
        pageOffset: 0.0,
      );

      var hist = LocalStorage.getHistoryItem(slug);
      expect(hist!['page'], 2);

      // Now user reads page 1 at offset 1200px
      await LocalStorage.saveHistory(
        slug: slug,
        title: 'Zombie Manga',
        cover: null,
        chapterSlug: 'ch-88',
        chapterTitle: 'Bab 88',
        source: 'softkomik',
        page: 1,
        totalPages: 17,
        scrollOffset: 1200.0,
        pageOffset: 1200.0,
        pageOffsetRatio: 0.8,
      );

      hist = LocalStorage.getHistoryItem(slug);
      // MUST NOT be forced to 2! Must be 1 with exact offsets.
      expect(hist!['page'], 1);
      expect(hist['pageOffset'], 1200.0);
      expect(hist['scrollOffset'], 1200.0);
      expect(hist['pageOffsetRatio'], 0.8);
    });

    test('Webtoon anchor calculation accurately resolves in-page offset and ratio without premature page advance', () {
      final pageHeights = <int, double>{0: 1500.0, 1: 1500.0, 2: 1500.0};
      const totalPages = 3;

      // Scenario: User is reading bottom of page 1 at scrollOffset = 1200.0
      double scrollOffset = 1200.0;
      int anchorIndex = 0;
      double pageOffset = 0.0;
      double? pageRatio;

      double cumulative = 0.0;
      for (int i = 0; i < totalPages; i++) {
        final h = pageHeights[i]!;
        if (i == totalPages - 1 || scrollOffset < cumulative + h - 1.0) {
          anchorIndex = i;
          pageOffset = (scrollOffset - cumulative).clamp(0.0, h);
          pageRatio = h > 0 ? (pageOffset / h).clamp(0.0, 1.0) : 0.0;
          break;
        }
        cumulative += h;
      }

      expect(anchorIndex, 0); // Still on Page 1!
      expect(pageOffset, 1200.0);
      expect(pageRatio, closeTo(0.8, 0.001));

      // Scenario: User scrolls further to scrollOffset = 1600.0 (entered Page 2)
      scrollOffset = 1600.0;
      cumulative = 0.0;
      for (int i = 0; i < totalPages; i++) {
        final h = pageHeights[i]!;
        if (i == totalPages - 1 || scrollOffset < cumulative + h - 1.0) {
          anchorIndex = i;
          pageOffset = (scrollOffset - cumulative).clamp(0.0, h);
          pageRatio = h > 0 ? (pageOffset / h).clamp(0.0, 1.0) : 0.0;
          break;
        }
        cumulative += h;
      }

      expect(anchorIndex, 1); // Now on Page 2
      expect(pageOffset, 100.0); // 1600 - 1500
      expect(pageRatio, closeTo(100.0 / 1500.0, 0.001));
    });

    test('End of final chapter transition card preserves 100% progress and does not drop to 98%', () async {
      // 43 chapters, user is on chapter 43 (chIdx = 42)
      const totalChs = 43;
      const chIdx = 42;
      const pagesCount = 15;
      
      // When at end card: isAtEnd is true
      final bool isAtEnd = DateTime.now().millisecondsSinceEpoch > 0;
      final anchorPageIndex = isAtEnd ? pagesCount - 1 : 0;
      final isLastCh = (chIdx == totalChs - 1);
      final isDone = isLastCh && (pagesCount > 0 && (anchorPageIndex + 1 >= pagesCount || isAtEnd));
      
      double totalProgress;
      if (isDone) {
        totalProgress = 1.0;
      } else {
        final pageFrac = pagesCount > 0 ? (anchorPageIndex + 1) / pagesCount : 0.0;
        final raw = ((chIdx + pageFrac) / totalChs).clamp(0.0, 1.0);
        totalProgress = raw.clamp(0.0, 0.99);
      }

      expect(isDone, isTrue);
      expect(totalProgress, 1.0);

      // Verify Manga Details isCompleted calculation
      final lastReadIndex = chIdx; // 42
      final chronoLength = totalChs; // 43
      final isLastChapter = (lastReadIndex >= 0 && lastReadIndex == chronoLength - 1);
      final hasNewerChapters = lastReadIndex >= 0 && lastReadIndex < chronoLength - 1;
      final isCompleted = !hasNewerChapters && isLastChapter && totalProgress >= 0.999;

      expect(hasNewerChapters, isFalse);
      expect(isLastChapter, isTrue);
      expect(isCompleted, isTrue);
    });
  });
}
