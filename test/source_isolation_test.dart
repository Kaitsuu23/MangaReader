import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:manga_app/core/storage/local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('source_iso_test_');
    await LocalStorage.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Source Isolation & Collision Prevention Tests', () {
    test('Identical slug across different sources maintains independent favorites', () async {
      const slug = 'sono-bisque-doll-wa-koi-wo-suru';

      // 1. Apkomik is added to favorite with category "Tamat"
      await LocalStorage.saveFavorite(
        slug: slug,
        title: 'Sono Bisque Doll wa Koi wo suru (Apkomik)',
        cover: 'https://apkomik.com/cover.jpg',
        source: 'apkomik',
        category: 'Tamat',
      );

      // Verify Apkomik favorite status
      expect(LocalStorage.isFavorite(slug, source: 'apkomik'), isTrue);
      expect(LocalStorage.getFavoriteCategory(slug, source: 'apkomik'), 'Tamat');
      final apkomikFav = LocalStorage.getFavorite(slug, source: 'apkomik');
      expect(apkomikFav?['source'], 'apkomik');

      // 2. Shinigami with the same slug must NOT be favorite!
      expect(LocalStorage.isFavorite(slug, source: 'shinigami'), isFalse);
      expect(LocalStorage.getFavoriteCategory(slug, source: 'shinigami'), isNull);
      expect(LocalStorage.getFavorite(slug, source: 'shinigami'), isNull);

      // 3. Komiku with the same slug must NOT be favorite!
      expect(LocalStorage.isFavorite(slug, source: 'komiku'), isFalse);

      // 4. Now add Shinigami to favorite with category "Sedang Dibaca"
      await LocalStorage.saveFavorite(
        slug: slug,
        title: 'Sono Bisque Doll wa Koi wo suru (Shinigami)',
        cover: 'https://shinigami.id/cover.jpg',
        source: 'shinigami',
        category: 'Sedang Dibaca',
      );

      // Both must exist independently without overwriting each other
      expect(LocalStorage.isFavorite(slug, source: 'apkomik'), isTrue);
      expect(LocalStorage.getFavoriteCategory(slug, source: 'apkomik'), 'Tamat');

      expect(LocalStorage.isFavorite(slug, source: 'shinigami'), isTrue);
      expect(LocalStorage.getFavoriteCategory(slug, source: 'shinigami'), 'Sedang Dibaca');

      final allFavs = LocalStorage.getFavorites();
      expect(allFavs.length, 2);

      // 5. Removing Apkomik should NOT remove Shinigami
      await LocalStorage.removeFavorite(slug, source: 'apkomik');
      expect(LocalStorage.isFavorite(slug, source: 'apkomik'), isFalse);
      expect(LocalStorage.isFavorite(slug, source: 'shinigami'), isTrue);
      expect(LocalStorage.getFavoriteCategory(slug, source: 'shinigami'), 'Sedang Dibaca');
    });

    test('Identical slug across different sources maintains independent reading history', () async {
      const slug = 'sono-bisque-doll-wa-koi-wo-suru';

      // Read Chapter 10 on Apkomik (50% progress)
      await LocalStorage.saveHistory(
        slug: slug,
        title: 'Sono Bisque Doll (Apkomik)',
        cover: 'https://apkomik.com/cover.jpg',
        source: 'apkomik',
        chapterSlug: 'chapter-10',
        chapterTitle: 'Chapter 10',
        page: 15,
        totalPages: 30,
        percent: 0.5,
      );

      // Verify Apkomik has history
      final apkomikHist = LocalStorage.getHistoryItem(slug, source: 'apkomik');
      expect(apkomikHist, isNotNull);
      expect(apkomikHist?['chapterSlug'], 'chapter-10');
      expect(LocalStorage.getHistoryProgress(slug, source: 'apkomik'), 0.5);
      expect(LocalStorage.getReadChapters(slug, source: 'apkomik'), contains('chapter-10'));

      // Shinigami must NOT have history!
      expect(LocalStorage.getHistoryItem(slug, source: 'shinigami'), isNull);
      expect(LocalStorage.getHistoryProgress(slug, source: 'shinigami'), 0.0);
      expect(LocalStorage.getReadChapters(slug, source: 'shinigami'), isEmpty);

      // Read Chapter 1 on Shinigami (10% progress)
      await LocalStorage.saveHistory(
        slug: slug,
        title: 'Sono Bisque Doll (Shinigami)',
        cover: 'https://shinigami.id/cover.jpg',
        source: 'shinigami',
        chapterSlug: 'ch-01-indo',
        chapterTitle: 'Chapter 01',
        page: 2,
        totalPages: 20,
        percent: 0.1,
      );

      // Both histories must remain completely separate
      final shinigamiHist = LocalStorage.getHistoryItem(slug, source: 'shinigami');
      expect(shinigamiHist?['chapterSlug'], 'ch-01-indo');
      expect(LocalStorage.getHistoryProgress(slug, source: 'shinigami'), 0.1);
      expect(LocalStorage.getReadChapters(slug, source: 'shinigami'), contains('ch-01-indo'));
      expect(LocalStorage.getReadChapters(slug, source: 'shinigami'), isNot(contains('chapter-10')));

      final apkomikHistAfter = LocalStorage.getHistoryItem(slug, source: 'apkomik');
      expect(apkomikHistAfter?['chapterSlug'], 'chapter-10');
      expect(LocalStorage.getHistoryProgress(slug, source: 'apkomik'), 0.5);

      // Deleting history for Shinigami should keep Apkomik intact
      await LocalStorage.deleteHistoryItem(slug, source: 'shinigami');
      expect(LocalStorage.getHistoryItem(slug, source: 'shinigami'), isNull);
      expect(LocalStorage.getHistoryItem(slug, source: 'apkomik'), isNotNull);
    });

    test('Deletion tombstones are isolated per source', () async {
      const slug = 'solo-leveling';

      await LocalStorage.saveFavorite(
        slug: slug,
        title: 'Solo Leveling (Apkomik)',
        cover: 'https://apkomik.com/cover.jpg',
        source: 'apkomik',
        category: 'Tamat',
      );
      await LocalStorage.saveFavorite(
        slug: slug,
        title: 'Solo Leveling (Shinigami)',
        cover: 'https://shinigami.id/cover.jpg',
        source: 'shinigami',
        category: 'Favorit',
      );

      // Delete only Apkomik
      await LocalStorage.removeFavorite(slug, source: 'apkomik', recordTombstone: true);

      final tombstones = LocalStorage.getDeletedFavoriteTombstones();
      expect(tombstones.any((t) => t['slug'] == slug && t['source'] == 'apkomik'), isTrue);
      expect(tombstones.any((t) => t['slug'] == slug && t['source'] == 'shinigami'), isFalse);

      // Shinigami must still be favorite
      expect(LocalStorage.isFavorite(slug, source: 'shinigami'), isTrue);
    });
  });
}
