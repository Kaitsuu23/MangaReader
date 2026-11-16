import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:manga_app/shared/models/manga_item.dart';
import 'package:manga_app/shared/widgets/manga_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('yomika_meta_test_');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('MangaItem Title Slug Formatting Tests', () {
    test('formatTitleFromSlug formats kebab-case slug into Title Case', () {
      expect(
        MangaItem.formatTitleFromSlug('beyond-myriad-peoples'),
        'Beyond Myriad Peoples',
      );
      expect(
        MangaItem.formatTitleFromSlug('nano-machine'),
        'Nano Machine',
      );
      expect(
        MangaItem.formatTitleFromSlug('do-you-want-to-be-friends-forever'),
        'Do You Want To Be Friends Forever',
      );
    });

    test('formatTitleFromSlug preserves existing spaced titles', () {
      expect(
        MangaItem.formatTitleFromSlug('Beyond Myriad Peoples'),
        'Beyond Myriad Peoples',
      );
      expect(
        MangaItem.formatTitleFromSlug('Supreme Curse-mancer'),
        'Supreme Curse-mancer',
      );
    });

    test('formatTitleFromSlug handles empty string', () {
      expect(MangaItem.formatTitleFromSlug(''), 'Tanpa Judul');
    });

    test('displayTitle getter returns formatted title', () {
      final item = MangaItem(
        title: 'beyond-myriad-peoples',
        slug: 'beyond-myriad-peoples',
      );
      expect(item.displayTitle, 'Beyond Myriad Peoples');
    });
  });

  group('LocalStorage Favorite & History Metadata Protection & Healing', () {
    test('saveFavorite preserves existing cover when incoming cover is null or empty', () async {
      await LocalStorage.saveFavorite(
        slug: 'beyond-myriad-peoples',
        title: 'Beyond Myriad Peoples',
        cover: 'https://example.com/cover.jpg',
        source: 'shinigami',
      );

      final fav1 = LocalStorage.getFavorite('beyond-myriad-peoples');
      expect(fav1!['cover'], 'https://example.com/cover.jpg');

      // Now simulate a sync from remote that has cover = null or empty
      await LocalStorage.saveFavorite(
        slug: 'beyond-myriad-peoples',
        title: 'beyond-myriad-peoples',
        cover: '',
        source: 'shinigami',
      );

      final fav2 = LocalStorage.getFavorite('beyond-myriad-peoples');
      // Should preserve the existing cover and title!
      expect(fav2!['cover'], 'https://example.com/cover.jpg');
      expect(fav2['title'], 'Beyond Myriad Peoples');
    });

    test('updateFavoriteMetadata updates title and cover without affecting categories', () async {
      await LocalStorage.saveFavorite(
        slug: 'beyond-myriad-peoples',
        title: 'beyond-myriad-peoples',
        cover: null,
        source: 'shinigami',
        category: 'Manhua',
        categories: ['Manhua', 'Membaca'],
      );

      await LocalStorage.updateFavoriteMetadata(
        slug: 'beyond-myriad-peoples',
        title: 'Beyond Myriad Peoples',
        cover: 'https://example.com/healed_cover.jpg',
        type: 'Manhua',
        latestChapter: 'Chapter 250',
      );

      final fav = LocalStorage.getFavorite('beyond-myriad-peoples');
      expect(fav, isNotNull);
      expect(fav!['title'], 'Beyond Myriad Peoples');
      expect(fav['cover'], 'https://example.com/healed_cover.jpg');
      expect(fav['category'], 'Manhua');
      expect(fav['categories'], ['Manhua', 'Membaca']);
      expect(fav['latestChapter'], 'Chapter 250');
    });

    test('updateHistoryMetadata updates title and cover correctly', () async {
      await LocalStorage.saveHistory(
        slug: 'beyond-myriad-peoples',
        title: 'beyond-myriad-peoples',
        cover: null,
        source: 'shinigami',
        chapterSlug: 'ch-1',
        chapterTitle: 'Chapter 1',
        page: 1,
        totalPages: 10,
      );

      await LocalStorage.updateHistoryMetadata(
        slug: 'beyond-myriad-peoples',
        title: 'Beyond Myriad Peoples',
        cover: 'https://example.com/healed_cover.jpg',
      );

      final hist = LocalStorage.getHistoryItem('beyond-myriad-peoples');
      expect(hist, isNotNull);
      expect(hist!['title'], 'Beyond Myriad Peoples');
      expect(hist['cover'], 'https://example.com/healed_cover.jpg');
      expect(hist['chapterSlug'], 'ch-1');
    });

    testWidgets('MangaCard displays formatted title when title is slug', (tester) async {
      final manga = MangaItem(
        title: 'beyond-myriad-peoples',
        slug: 'beyond-myriad-peoples',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MangaCard(
              item: manga,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Beyond Myriad Peoples'), findsOneWidget);
    });

    test('saveFavorite with empty categories does not default category to "Semua kesukaan"', () async {
      await LocalStorage.saveFavorite(
        slug: 'test-comic-no-cat',
        title: 'Test Comic No Category',
        cover: null,
        source: 'shinigami',
        categories: [],
      );

      final fav = LocalStorage.getFavorite('test-comic-no-cat');
      expect(fav, isNotNull);
      expect(fav!['category'], isNot('Semua kesukaan'));
      expect(fav['category'], '');
      expect(LocalStorage.getFavoriteCategoriesForSlug('test-comic-no-cat'), isEmpty);
    });

    test('getFavoriteCategories never includes "Semua kesukaan"', () async {
      await LocalStorage.saveFavoriteCategories(['Semua kesukaan', 'Action', 'Semua', 'Romance']);
      final cats = LocalStorage.getFavoriteCategories();
      expect(cats, equals(['Action', 'Romance']));
      expect(cats.contains('Semua kesukaan'), isFalse);
    });
  });
}
