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
    tempDir = await Directory.systemTemp.createTemp('yomika_favorites_test_');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Favorites Selection and Move Category Tests', () {
    test('updateFavoriteCategory correctly updates single and multiple comics', () async {
      await LocalStorage.saveFavorite(
        slug: 'manga-1',
        title: 'Manga One',
        cover: 'https://example.com/cover1.jpg',
        source: 'softkomik',
        category: 'Semua kesukaan',
      );

      await LocalStorage.saveFavorite(
        slug: 'manga-2',
        title: 'Manga Two',
        cover: 'https://example.com/cover2.jpg',
        source: 'softkomik',
        category: 'Semua kesukaan',
      );

      expect(LocalStorage.getFavorites(category: 'Semua kesukaan').length, 2);
      expect(LocalStorage.getFavorites(category: 'Manhwa').length, 0);

      // Multi move to "Manhwa"
      final selectedSlugs = {'manga-1', 'manga-2'};
      for (final slug in selectedSlugs) {
        await LocalStorage.updateFavoriteCategory(slug, 'Manhwa');
      }

      // Check they now appear in "Manhwa"
      final manhwaList = LocalStorage.getFavorites(category: 'Manhwa');
      expect(manhwaList.length, 2);
      expect(manhwaList.map((e) => e['slug']).toSet(), equals({'manga-1', 'manga-2'}));

      // Also still in "Semua kesukaan" since all items belong to all
      expect(LocalStorage.getFavorites(category: 'Semua kesukaan').length, 2);

      // Check single favorite retrieval
      final fav1 = LocalStorage.getFavorite('manga-1');
      expect(fav1, isNotNull);
      expect(fav1!['title'], 'Manga One');
      expect(fav1['category'], 'Manhwa');
    });

    testWidgets('MangaCard renders properly with isSelected: true', (tester) async {
      final manga = MangaItem(
        title: 'Selected Manga',
        slug: 'selected-slug',
        cover: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MangaCard(
              item: manga,
              isSelected: true,
              onTap: () {},
            ),
          ),
        ),
      );

      // Verify the check icon is displayed inside selection badge
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('Selected Manga'), findsOneWidget);
    });
  });
}
