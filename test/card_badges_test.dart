import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:manga_app/shared/models/manga_item.dart';
import 'package:manga_app/shared/models/feed_item.dart';
import 'package:manga_app/shared/widgets/manga_card.dart';
import 'package:manga_app/shared/widgets/manga_card_badges.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('badges_test_');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Manga Card Badges & Storage Tests', () {
    testWidgets('FavoriteBadge and ReadingProgressBadge render properly in widget tree', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: const [
                Positioned(top: 6, left: 6, child: FavoriteBadge()),
                Positioned(top: 6, right: 6, child: ReadingProgressBadge(progress: 0.75)),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(FavoriteBadge), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      expect(find.byType(ReadingProgressBadge), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
    });

    testWidgets('ReadingProgressBadge shows check icon when progress is 100%', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReadingProgressBadge(progress: 1.0),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('ReadingProgressBadge shows 99% and not checkmark when progress is 0.9985 (unfinished)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReadingProgressBadge(progress: 0.9985),
          ),
        ),
      );

      expect(find.text('99%'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    test('LocalStorage.getHistoryProgress calculates progress correctly', () async {
      // 1. When not in history
      expect(LocalStorage.getHistoryProgress('unknown-manga'), 0.0);

      // 2. When stored with percent
      await LocalStorage.saveHistory(
        slug: 'one-piece',
        title: 'One Piece',
        cover: null,
        source: 'komikindo',
        chapterSlug: '1000',
        chapterTitle: 'Chapter 1000',
        page: 5,
        totalPages: 20,
        percent: 0.65,
      );

      expect(LocalStorage.getHistoryProgress('one-piece'), 0.65);

      // 3. When stored without percent, calculate page / totalPages
      await LocalStorage.saveHistory(
        slug: 'naruto',
        title: 'Naruto',
        cover: null,
        source: 'komikindo',
        chapterSlug: '500',
        chapterTitle: 'Chapter 500',
        page: 10,
        totalPages: 20,
      );

      expect(LocalStorage.getHistoryProgress('naruto'), 0.5);
    });

    test('LocalStorage.isFavorite handles slug normalization', () async {
      await LocalStorage.saveFavorite(
        slug: 'bleach',
        title: 'Bleach',
        cover: null,
        source: 'komikindo',
      );

      expect(LocalStorage.isFavorite('bleach'), isTrue);
      expect(LocalStorage.isFavorite('/manga/bleach/'), isTrue);
      expect(LocalStorage.isFavorite('manga/bleach'), isTrue);
      expect(LocalStorage.isFavorite('unknown'), isFalse);
    });

    test('LocalStorage.isFavorite and getHistoryProgress handle empty string source gracefully', () async {
      await LocalStorage.saveFavorite(
        slug: 'hunter-x-hunter',
        title: 'Hunter x Hunter',
        cover: null,
        source: 'shinigami',
      );

      await LocalStorage.saveHistory(
        slug: 'hunter-x-hunter',
        title: 'Hunter x Hunter',
        cover: null,
        source: 'shinigami',
        chapterSlug: '400',
        chapterTitle: 'Chapter 400',
        page: 15,
        totalPages: 20,
      );

      // Verify that passing source: "" does NOT fail to match
      expect(LocalStorage.isFavorite('hunter-x-hunter', source: ''), isTrue);
      expect(LocalStorage.getHistoryProgress('hunter-x-hunter', source: ''), 0.75);

      // And passing explicit matching source matches
      expect(LocalStorage.isFavorite('hunter-x-hunter', source: 'shinigami'), isTrue);
      expect(LocalStorage.getHistoryProgress('hunter-x-hunter', source: 'shinigami'), 0.75);
    });

    test('MangaItem.fromJson falls back to defaultSource when source is empty string', () {
      final json = {
        'title': 'Jujutsu Kaisen',
        'slug': 'jujutsu-kaisen',
        'source': '',
      };

      final item = MangaItem.fromJson(json, defaultSource: 'shinigami');
      expect(item.source, 'shinigami');
    });

    testWidgets('MangaCard dynamically displays favorite and progress badges reactively', (tester) async {
      final item = MangaItem(
        title: 'Solo Leveling',
        slug: 'solo-leveling',
        source: 'softkomik',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 150,
              height: 250,
              child: MangaCard(
                item: item,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      // Initially, neither badge exists
      expect(find.byType(FavoriteBadge), findsNothing);
      expect(find.byType(ReadingProgressBadge), findsNothing);

      // Save to favorite inside runAsync for stream dispatch
      await tester.runAsync(() async {
        await LocalStorage.saveFavorite(
          slug: 'solo-leveling',
          title: 'Solo Leveling',
          cover: null,
          source: 'softkomik',
        );
      });

      await tester.pump();

      // Favorite badge now appears!
      expect(find.byType(FavoriteBadge), findsOneWidget);
      expect(find.byType(ReadingProgressBadge), findsNothing);

      // Now save reading history (e.g. read chapter 50) inside runAsync
      await tester.runAsync(() async {
        await LocalStorage.saveHistory(
          slug: 'solo-leveling',
          title: 'Solo Leveling',
          cover: null,
          source: 'softkomik',
          chapterSlug: '50',
          chapterTitle: 'Chapter 50',
          page: 10,
          totalPages: 20,
        );
      });

      await tester.pump();

      // Both badges now appear simultaneously!
      expect(find.byType(FavoriteBadge), findsOneWidget);
      expect(find.byType(ReadingProgressBadge), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('MangaCard uses fallbackSource when item.source is empty or null', (tester) async {
      await tester.runAsync(() async {
        await LocalStorage.saveFavorite(
          slug: 'tower-of-god',
          title: 'Tower of God',
          cover: null,
          source: 'shinigami',
        );
        await LocalStorage.saveHistory(
          slug: 'tower-of-god',
          title: 'Tower of God',
          cover: null,
          source: 'shinigami',
          chapterSlug: '10',
          chapterTitle: 'Chapter 10',
          page: 20,
          totalPages: 20,
        );
      });

      final itemWithoutSource = MangaItem(
        title: 'Tower of God',
        slug: 'tower-of-god',
        source: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 150,
              height: 250,
              child: MangaCard(
                item: itemWithoutSource,
                fallbackSource: 'shinigami',
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      // Badges must appear via fallbackSource
      expect(find.byType(FavoriteBadge), findsOneWidget);
      expect(find.byType(ReadingProgressBadge), findsOneWidget);
      // Completed progress shows checkmark icon
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('MangaCard shows +1 badge to the left of FavoriteBadge, and removes it when read', (tester) async {
      final item = MangaItem(
        title: 'Chainsaw Man',
        slug: 'chainsaw-man',
        source: 'shinigami',
      );

      // 1. Initially save favorite and reading history (progress = 50%)
      await tester.runAsync(() async {
        await LocalStorage.saveFavorite(
          slug: 'chainsaw-man',
          title: 'Chainsaw Man',
          cover: null,
          source: 'shinigami',
        );
        await LocalStorage.saveHistory(
          slug: 'chainsaw-man',
          title: 'Chainsaw Man',
          cover: null,
          source: 'shinigami',
          chapterSlug: 'ch-100',
          chapterTitle: 'Chapter 100',
          page: 10,
          totalPages: 20,
          percent: 0.5,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 150,
              height: 250,
              child: MangaCard(
                item: item,
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      // Favorite and reading progress are visible, +1 is NOT visible yet
      expect(find.byType(FavoriteBadge), findsOneWidget);
      expect(find.byType(ReadingProgressBadge), findsOneWidget);
      expect(find.byType(NewChaptersBadge), findsNothing);

      // 2. A new chapter update arrives (Chapter 101)
      await tester.runAsync(() async {
        await LocalStorage.addFeedItem(FeedItem(
          id: 'csm_feed_1',
          mangaSlug: 'chainsaw-man',
          mangaTitle: 'Chainsaw Man',
          mangaSource: 'shinigami',
          newChaptersCount: 1,
          newChapters: ['Chapter 101'],
          newChapterSlugs: ['ch-101'],
          createdAt: DateTime.now().millisecondsSinceEpoch,
          isNew: true,
          modeId: 'normal',
        ));
      });

      await tester.pump();

      // Now +1 indicator appears alongside FavoriteBadge and ReadingProgressBadge!
      expect(find.byType(NewChaptersBadge), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.byType(FavoriteBadge), findsOneWidget);
      expect(find.byType(ReadingProgressBadge), findsOneWidget);

      // 3. User reads Chapter 101
      await tester.runAsync(() async {
        await LocalStorage.markChaptersAsRead(
          'chainsaw-man',
          ['ch-101'],
          source: 'shinigami',
          modeId: 'normal',
        );
      });

      await tester.pump();

      // +1 badge disappears, favorite badge remains alone at the left corner!
      expect(find.byType(NewChaptersBadge), findsNothing);
      expect(find.text('+1'), findsNothing);
      expect(find.byType(FavoriteBadge), findsOneWidget);
      expect(find.byType(ReadingProgressBadge), findsOneWidget);
    });
  });
}
