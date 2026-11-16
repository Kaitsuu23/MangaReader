import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_sync');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Sync Tombstone Deletion Tests', () {
    test('recordDeletedHistoryTombstone tracks deleted history items', () async {
      await LocalStorage.saveHistory(
        slug: 'manga-test-1',
        title: 'Manga Test 1',
        cover: null,
        chapterSlug: 'ch-1',
        chapterTitle: 'Bab 1',
        source: 'shinigami',
        page: 5,
        totalPages: 20,
      );

      expect(LocalStorage.getHistory().length, 1);
      expect(LocalStorage.getDeletedHistoryTombstones().isEmpty, true);

      await LocalStorage.deleteHistoryItem('manga-test-1');

      expect(LocalStorage.getHistory().isEmpty, true);
      final tombstones = LocalStorage.getDeletedHistoryTombstones();
      expect(tombstones.length, 1);
      expect(tombstones.first['slug'], 'manga-test-1');
      expect(tombstones.first['deletedAt'] > 0, true);

      await LocalStorage.clearDeletedHistoryTombstones();
      expect(LocalStorage.getDeletedHistoryTombstones().isEmpty, true);
    });

    test('removeFavorite records deleted favorite tombstone', () async {
      await LocalStorage.saveFavorite(
        slug: 'fav-manga-1',
        title: 'Fav Manga 1',
        cover: null,
        source: 'komiku',
      );

      expect(LocalStorage.isFavorite('fav-manga-1'), true);
      expect(LocalStorage.getDeletedFavoriteTombstones().isEmpty, true);

      await LocalStorage.removeFavorite('fav-manga-1');

      expect(LocalStorage.isFavorite('fav-manga-1'), false);
      final tombstones = LocalStorage.getDeletedFavoriteTombstones();
      expect(tombstones.length, 1);
      expect(tombstones.first['slug'], 'fav-manga-1');

      await LocalStorage.clearDeletedFavoriteTombstones();
      expect(LocalStorage.getDeletedFavoriteTombstones().isEmpty, true);
    });

    test('Remote category IDs correctly map to local categories on clean sync', () async {
      // Simulate clean sync response from server where remote categories has ID 2 = 'Manhwa & Manhua & Manga'
      final remoteCats = [
        {'category_id': 1, 'title': 'Semua kesukaan', 'deleted_at': 0},
        {'category_id': 2, 'title': 'Manhwa & Manhua & Manga', 'deleted_at': 0},
        {'category_id': 3, 'title': 'nanti', 'deleted_at': 0},
      ];

      final categoryMap = <String, int>{};
      final categoryIdToName = <int, String>{};

      for (final c in remoteCats) {
        final catId = (c['category_id'] as num?)?.toInt();
        final t = c['title'] as String?;
        if (catId != null && t != null && t.isNotEmpty) {
          categoryMap[t] = catId;
          categoryIdToName[catId] = t;
        }
      }

      await LocalStorage.saveSyncCategoryIds(categoryMap);
      await LocalStorage.saveFavoriteCategories(['Manhwa & Manhua & Manga', 'nanti']);

      expect(LocalStorage.getSyncCategoryIds()['Manhwa & Manhua & Manga'], 2);
      expect(categoryIdToName[2], 'Manhwa & Manhua & Manga');

      // Now process remote favourite with category_id 2
      final remoteFavs = [
        {
          'manga_id': 101,
          'category_id': 2,
          'deleted_at': 0,
          'manga': {
            'title': 'High Class',
            'url': '/manga/high-class',
            'cover_url': 'https://cover.jpg',
            'source': 'softkomik',
          }
        }
      ];

      final catNames = <String>[];
      for (final r in remoteFavs) {
        final catId = (r['category_id'] as num?)?.toInt() ?? 1;
        final catName = categoryIdToName[catId];
        if (catName != null &&
            catName.isNotEmpty &&
            catName != 'Semua kesukaan' &&
            catName != 'Semua' &&
            catName != 'Default') {
          catNames.add(catName);
        }
      }

      await LocalStorage.saveFavorite(
        slug: 'high-class',
        title: 'High Class',
        cover: 'https://cover.jpg',
        source: 'softkomik',
        category: catNames.first,
        categories: catNames,
      );

      final favsAll = LocalStorage.getFavorites();
      expect(favsAll.length, 1);

      final favsCategory = LocalStorage.getFavorites(category: 'Manhwa & Manhua & Manga');
      expect(favsCategory.length, 1);
      expect(favsCategory.first['title'], 'High Class');
    });

    test('deleteFavoriteCategory records tombstone, removes from syncCatIds and updates comics', () async {
      await LocalStorage.addFavoriteCategory('Action Shonen');
      await LocalStorage.saveSyncCategoryIds({'Action Shonen': 5});
      await LocalStorage.saveFavorite(
        slug: 'jujutsu-kaisen',
        title: 'Jujutsu Kaisen',
        cover: null,
        source: 'kiryuu',
        category: 'Action Shonen',
        categories: ['Action Shonen'],
      );

      expect(LocalStorage.getFavoriteCategories().contains('Action Shonen'), true);
      expect(LocalStorage.getSyncCategoryIds()['Action Shonen'], 5);
      expect(LocalStorage.getDeletedCategoryTombstones().isEmpty, true);

      // Delete the category
      await LocalStorage.deleteFavoriteCategory('Action Shonen');

      // Verify category removed from local list
      expect(LocalStorage.getFavoriteCategories().contains('Action Shonen'), false);
      // Verify category tombstone recorded with categoryId 5
      final tombstones = LocalStorage.getDeletedCategoryTombstones();
      expect(tombstones.length, 1);
      expect(tombstones.first['name'], 'Action Shonen');
      expect(tombstones.first['categoryId'], 5);
      expect(tombstones.first['deletedAt'] > 0, true);
      // Verify removed from active syncCatIds
      expect(LocalStorage.getSyncCategoryIds().containsKey('Action Shonen'), false);

      // Verify comic category cleaned up (no longer has Action Shonen)
      final fav = LocalStorage.getFavorite('jujutsu-kaisen');
      expect(fav, isNotNull);
      expect(fav?['category'], isNull);
      expect(fav?['categories'], isEmpty);
      // But still in favorites collection
      expect(LocalStorage.isFavorite('jujutsu-kaisen'), true);

      // Clear tombstones
      await LocalStorage.clearDeletedCategoryTombstones();
      expect(LocalStorage.getDeletedCategoryTombstones().isEmpty, true);
    });
  });
}
