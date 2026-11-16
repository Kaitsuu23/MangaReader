import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:manga_app/core/services/backup_service.dart';
import 'package:manga_app/shared/models/content_mode.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:archive/archive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kotatsu_backup_test');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Kotatsu Redo Backup & Restore Engine Tests', () {
    test('createBackupZip creates a valid Kotatsu-compatible .bk.zip file', () async {
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);

      // Populate test data
      await LocalStorage.addFavoriteCategory('Action Shonen');
      await LocalStorage.saveFavorite(
        slug: 'one-piece',
        title: 'One Piece',
        cover: 'https://cdn.example.com/op.jpg',
        source: 'shinigami',
        category: 'Action Shonen',
        type: 'Manga',
      );
      await LocalStorage.saveHistory(
        slug: 'one-piece',
        title: 'One Piece',
        cover: 'https://cdn.example.com/op.jpg',
        source: 'shinigami',
        chapterSlug: 'ch-1100',
        chapterTitle: 'Chapter 1100',
        page: 15,
        totalPages: 20,
        percent: 0.75,
      );
      await LocalStorage.saveBookmark(
        slug: 'one-piece',
        mangaTitle: 'One Piece',
        chapterSlug: 'ch-1100',
        chapterTitle: 'Chapter 1100',
        page: 15,
      );

      // Create Kotatsu zip
      final zipBytes = KotatsuBackupService.createBackupZip();
      expect(zipBytes.isNotEmpty, true);

      // Validate ZIP header ('PK\x03\x04')
      expect(zipBytes[0], 0x50);
      expect(zipBytes[1], 0x4B);
      expect(zipBytes[2], 0x03);
      expect(zipBytes[3], 0x04);

      // Decode with ZipDecoder to inspect entry names
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final entryNames = archive.map((f) => f.name).toSet();

      expect(entryNames.contains('index'), true);
      expect(entryNames.contains('categories'), true);
      expect(entryNames.contains('favourites'), true);
      expect(entryNames.contains('history'), true);
      expect(entryNames.contains('bookmarks'), true);
      expect(entryNames.contains('settings'), true);
      expect(entryNames.contains('sources'), true);

      // Parse with parseBackup
      final preview = KotatsuBackupService.parseBackup(zipBytes, fileName: 'kotatsu_test.bk.zip');
      expect(preview.isKotatsuZip, true);
      expect(preview.appId, 'org.koitharu.kotatsu');
      expect(preview.appVersion, 984);
      expect(preview.favoritesCount, 1);
      expect(preview.historyCount, 1);
      expect(preview.bookmarksCount, 1);
      expect(preview.categories.any((c) => c['title'] == 'Action Shonen'), true);
    });

    test('restoreBackup restores Kotatsu zip into a target content mode cleanly', () async {
      await LocalStorage.setActiveContentModeId(ContentMode.defaultNormalId);

      // Setup source data
      await LocalStorage.addFavoriteCategory('Isekai');
      await LocalStorage.saveFavorite(
        slug: 'mushoku-tensei',
        title: 'Mushoku Tensei',
        cover: 'https://cdn.example.com/mt.jpg',
        source: 'kiryuu',
        category: 'Isekai',
      );
      await LocalStorage.saveHistory(
        slug: 'mushoku-tensei',
        title: 'Mushoku Tensei',
        cover: 'https://cdn.example.com/mt.jpg',
        source: 'kiryuu',
        chapterSlug: 'ch-50',
        chapterTitle: 'Chapter 50',
        page: 10,
        totalPages: 20,
        percent: 0.5,
      );

      final zipBytes = KotatsuBackupService.createBackupZip();
      final preview = KotatsuBackupService.parseBackup(zipBytes);

      // Now restore into Restricted mode
      final result = await KotatsuBackupService.restoreBackup(
        preview,
        targetModeId: ContentMode.defaultRestrictedId,
        restoreFavorites: true,
        restoreHistory: true,
        restoreCategories: true,
      );

      expect(result.success, true);
      expect(result.favoritesRestored, 1);
      expect(result.historyRestored, 1);

      // Verify Restricted mode has the data
      expect(LocalStorage.isFavorite('mushoku-tensei', modeId: ContentMode.defaultRestrictedId), true);
      final fav = LocalStorage.getFavorite('mushoku-tensei', modeId: ContentMode.defaultRestrictedId);
      expect(fav?['category'], 'Isekai');

      final hist = LocalStorage.getHistoryItem('mushoku-tensei', modeId: ContentMode.defaultRestrictedId);
      expect(hist, isNotNull);
      expect(hist?['chapterSlug'], 'ch-50');
      expect(hist?['percent'], 0.5);

      final cats = LocalStorage.getFavoriteCategories(modeId: ContentMode.defaultRestrictedId);
      expect(cats.contains('Isekai'), true);
    });
  });
}
