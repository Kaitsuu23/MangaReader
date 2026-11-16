import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:manga_app/core/storage/local_storage.dart';
import 'package:manga_app/shared/models/manga_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('manga_alternatives_test_');
    await LocalStorage.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  setUp(() async {
    await LocalStorage.clearFavorites();
    await LocalStorage.clearHistory();
    await LocalStorage.saveFavoriteCategories(['Semua kesukaan', 'Manhwa & Manhua', 'Action']);
  });

  group('Alternatives & Migration Logic Tests', () {
    test('Favorite migration moves manga to target with preserved categories and removes old favorite', () async {
      const oldSlug = 'old-manga-slug';
      const newSlug = 'new-manga-slug';
      final oldCategories = ['Manhwa & Manhua', 'Action'];

      // 1. Simpan old manga sebagai favorit
      await LocalStorage.saveFavorite(
        slug: oldSlug,
        title: 'Original Title',
        cover: 'https://example.com/old_cover.jpg',
        source: 'komiku',
        categories: oldCategories,
        type: 'Manga',
        latestChapter: 'Chapter 10',
      );

      expect(LocalStorage.isFavorite(oldSlug), isTrue);
      expect(LocalStorage.getFavoriteCategoriesForSlug(oldSlug), containsAll(oldCategories));

      // 2. Simulasi migrasi ke new manga (seperti di AlternativesScreen._performMigration)
      final target = MangaItem(
        title: 'Alternative Title',
        slug: newSlug,
        cover: 'https://example.com/new_cover.jpg',
        source: 'komikindo',
        latestChapter: '12 bab',
        type: 'Manga',
      );

      final isFav = LocalStorage.isFavorite(oldSlug);
      expect(isFav, isTrue);

      final categories = LocalStorage.getFavoriteCategoriesForSlug(oldSlug);
      await LocalStorage.saveFavorite(
        slug: target.slug,
        title: target.title,
        cover: target.cover,
        source: target.source!,
        categories: categories,
        type: target.type,
        latestChapter: target.latestChapter,
      );
      await LocalStorage.removeFavorite(oldSlug, recordTombstone: true);

      // 3. Verifikasi hasil migrasi
      expect(LocalStorage.isFavorite(oldSlug), isFalse);
      expect(LocalStorage.isFavorite(newSlug), isTrue);
      expect(LocalStorage.getFavoriteCategoriesForSlug(newSlug), containsAll(oldCategories));

      final allFavs = LocalStorage.getFavorites();
      final newFav = allFavs.firstWhere((f) => f['slug'] == newSlug);
      expect(newFav['title'], equals('Alternative Title'));
      expect(newFav['source'], equals('komikindo'));
      expect(newFav['latestChapter'], equals('12 bab'));

      // Verifikasi tombstone dibuat agar sync server menghapus komik lama
      final favTombstones = LocalStorage.getDeletedFavoriteTombstones();
      expect(favTombstones.any((t) => t['slug'] == oldSlug), isTrue);
    });

    test('Reading history migration transfers progress, chapter info, and read chapters', () async {
      const oldSlug = 'reading-old-slug';
      const newSlug = 'reading-new-slug';

      // 1. Simpan riwayat bacaan pada old manga
      await LocalStorage.saveHistory(
        slug: oldSlug,
        title: 'Reading Original',
        cover: 'https://example.com/cover.jpg',
        source: 'komiku',
        chapterSlug: 'ch-5',
        chapterTitle: 'Chapter 5',
        page: 14,
        totalPages: 28,
        pageOffset: 120.0,
        scrollOffset: 340.0,
        percent: 0.5,
        totalChapters: 10,
        chapterNumber: 5,
        pageOffsetRatio: 0.5,
      );

      LocalStorage.markChapterAsRead(oldSlug, 'ch-1');
      LocalStorage.markChapterAsRead(oldSlug, 'ch-2');
      LocalStorage.markChapterAsRead(oldSlug, 'ch-5');

      final oldHist = LocalStorage.getHistoryItem(oldSlug);
      expect(oldHist, isNotNull);
      expect(oldHist!['chapterSlug'], equals('ch-5'));
      expect(oldHist['page'], equals(14));
      expect(oldHist['percent'], equals(0.5));
      expect(LocalStorage.getReadChapters(oldSlug), containsAll(['ch-1', 'ch-2', 'ch-5']));

      // 2. Simulasi migrasi riwayat ke new manga
      final target = MangaItem(
        title: 'Reading Alternative',
        slug: newSlug,
        cover: 'https://example.com/new_cover.jpg',
        source: 'komikindo',
        latestChapter: '10',
      );

      await LocalStorage.saveHistory(
        slug: target.slug,
        title: target.title,
        cover: target.cover,
        source: target.source!,
        chapterSlug: oldHist['chapterSlug'] as String? ?? '',
        chapterTitle: oldHist['chapterTitle'] as String? ?? '',
        page: (oldHist['page'] as num?)?.toInt() ?? 1,
        totalPages: (oldHist['totalPages'] as num?)?.toInt() ?? 1,
        pageOffset: (oldHist['pageOffset'] as num?)?.toDouble() ?? 0.0,
        scrollOffset: (oldHist['scrollOffset'] as num?)?.toDouble() ?? 0.0,
        percent: (oldHist['percent'] as num?)?.toDouble(),
        totalChapters: 10,
        chapterNumber: (oldHist['chapterNumber'] as num?)?.toInt(),
        pageOffsetRatio: (oldHist['pageOffsetRatio'] as num?)?.toDouble(),
      );

      final readChapters = LocalStorage.getReadChapters(oldSlug);
      for (final ch in readChapters) {
        LocalStorage.markChapterAsRead(target.slug, ch);
      }
      await LocalStorage.deleteHistoryItem(oldSlug);

      // 3. Verifikasi riwayat telah berpindah ke target manga
      expect(LocalStorage.getHistoryItem(oldSlug), isNull);
      final newHist = LocalStorage.getHistoryItem(newSlug);
      expect(newHist, isNotNull);
      expect(newHist!['title'], equals('Reading Alternative'));
      expect(newHist['source'], equals('komikindo'));
      expect(newHist['chapterSlug'], equals('ch-5'));
      expect(newHist['page'], equals(14));
      expect(newHist['percent'], equals(0.5));
      expect(LocalStorage.getReadChapters(newSlug), containsAll(['ch-1', 'ch-2', 'ch-5']));

      // Verifikasi tombstone riwayat dibuat agar sync server menghapus riwayat lama
      final histTombstones = LocalStorage.getDeletedHistoryTombstones();
      expect(histTombstones.any((t) => t['slug'] == oldSlug), isTrue);
    });

    test('Same-slug alternative migration (e.g. horimiya apkomik -> bacakomik) preserves position and does not record tombstone', () async {
      const slug = 'horimiya';
      const oldSource = 'apkomik';
      const newSource = 'bacakomik';
      const fixedAddedAt = 1600000000000;
      const fixedUpdatedAt = 1600000050000;
      const fixedCreatedAt = 1600000010000;

      // 1. Setup favorite and history with specific old timestamps
      await LocalStorage.saveFavorite(
        slug: slug,
        title: 'Horimiya',
        cover: 'https://example.com/apkomik_horimiya.jpg',
        source: oldSource,
        categories: ['Semua kesukaan', 'Romance'],
        addedAt: fixedAddedAt,
      );

      await LocalStorage.saveHistory(
        slug: slug,
        title: 'Horimiya',
        cover: 'https://example.com/apkomik_horimiya.jpg',
        source: oldSource,
        chapterSlug: 'chapter-122',
        chapterTitle: 'Chapter 122',
        page: 5,
        totalPages: 20,
        createdAt: fixedCreatedAt,
        updatedAt: fixedUpdatedAt,
      );

      expect(LocalStorage.isFavorite(slug, source: oldSource), isTrue);
      expect(LocalStorage.getFavorite(slug, source: oldSource)!['addedAt'], equals(fixedAddedAt));
      expect(LocalStorage.getHistoryItem(slug, source: oldSource)!['updatedAt'], equals(fixedUpdatedAt));

      // 2. Perform migration logic matching AlternativesScreen._performMigration
      final target = MangaItem(
        title: 'Horimiya',
        slug: slug,
        cover: 'https://example.com/bacakomik_horimiya.jpg',
        source: newSource,
        latestChapter: 'Chapter 125',
      );

      final shouldRecordTombstone = slug != target.slug; // false because slugs are identical

      // Favorite migration
      final oldFav = LocalStorage.getFavorite(slug, source: oldSource);
      expect(oldFav, isNotNull);
      final oldAddedAt = (oldFav!['addedAt'] as num?)?.toInt();
      final cats = LocalStorage.getFavoriteCategoriesForSlug(slug, source: oldSource);

      await LocalStorage.removeFavorite(slug, source: oldSource, recordTombstone: shouldRecordTombstone);
      await LocalStorage.saveFavorite(
        slug: target.slug,
        title: target.title,
        cover: target.cover,
        source: newSource,
        categories: cats,
        latestChapter: target.latestChapter,
        addedAt: oldAddedAt,
      );

      // History migration
      final histItem = LocalStorage.getHistoryItem(slug, source: oldSource);
      expect(histItem, isNotNull);
      final oldHistCreatedAt = (histItem!['createdAt'] as num?)?.toInt();
      final oldHistUpdatedAt = (histItem['updatedAt'] as num?)?.toInt();

      await LocalStorage.deleteHistoryItem(slug, source: oldSource, recordTombstone: shouldRecordTombstone);
      await LocalStorage.saveHistory(
        slug: target.slug,
        title: target.title,
        cover: target.cover,
        source: newSource,
        chapterSlug: histItem['chapterSlug'] as String? ?? '',
        chapterTitle: histItem['chapterTitle'] as String? ?? '',
        page: (histItem['page'] as num?)?.toInt() ?? 1,
        totalPages: (histItem['totalPages'] as num?)?.toInt() ?? 1,
        createdAt: oldHistCreatedAt,
        updatedAt: oldHistUpdatedAt,
      );

      // 3. Verify target exists and retains exact timestamps
      expect(LocalStorage.isFavorite(slug), isTrue);
      expect(LocalStorage.isFavorite(slug, source: newSource), isTrue);
      expect(LocalStorage.isFavorite(slug, source: oldSource), isFalse);

      final newFav = LocalStorage.getFavorite(slug, source: newSource);
      expect(newFav, isNotNull);
      expect(newFav!['source'], equals(newSource));
      expect(newFav['addedAt'], equals(fixedAddedAt)); // Card position in favorites preserved!

      final newHist = LocalStorage.getHistoryItem(slug, source: newSource);
      expect(newHist, isNotNull);
      expect(newHist!['source'], equals(newSource));
      expect(newHist['createdAt'], equals(fixedCreatedAt));
      expect(newHist['updatedAt'], equals(fixedUpdatedAt)); // Card position in history preserved!

      // 4. Verify NO tombstone exists for this slug so sync server will NOT delete it!
      final favTombstones = LocalStorage.getDeletedFavoriteTombstones();
      expect(favTombstones.any((t) => t['slug'] == slug), isFalse);

      final histTombstones = LocalStorage.getDeletedHistoryTombstones();
      expect(histTombstones.any((t) => t['slug'] == slug), isFalse);
    });

    test('Chapter parsing correctly extracts number from varied string formats', () {
      int? parseChapterCount(String? latestChapter) {
        if (latestChapter == null || latestChapter.isEmpty) return null;
        final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(latestChapter);
        if (match != null) {
          final val = double.tryParse(match.group(1)!);
          if (val != null) return val.round();
        }
        return null;
      }

      expect(parseChapterCount('10'), equals(10));
      expect(parseChapterCount('Chapter 10'), equals(10));
      expect(parseChapterCount('Ch. 25.5'), equals(26));
      expect(parseChapterCount('10 bab'), equals(10));
      expect(parseChapterCount('Vol. 2 Ch. 45 End'), equals(2)); // matches first number or chapter
      expect(parseChapterCount(''), isNull);
      expect(parseChapterCount(null), isNull);
    });

    test('Title matching score ranks exact match, prefix, contains, and token overlap', () {
      int titleMatchScore(String title, String query) {
        String normalize(String s) => s
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');

        final normTitle = normalize(title);
        final normQuery = normalize(query);
        if (normQuery.isEmpty || normTitle.isEmpty) return 0;

        if (normTitle == normQuery) return 100;
        if (normTitle.startsWith(normQuery) || normQuery.startsWith(normTitle)) return 85;
        if (normTitle.contains(normQuery) || normQuery.contains(normTitle)) return 75;

        final queryTokens = normQuery.split(' ').where((s) => s.isNotEmpty).toSet();
        final titleTokens = normTitle.split(' ').where((s) => s.isNotEmpty).toSet();
        final total = queryTokens.length > titleTokens.length ? queryTokens.length : titleTokens.length;
        if (total == 0) return 0;
        final intersect = queryTokens.intersection(titleTokens).length;
        if (queryTokens.length > 1 && (intersect < 2 || intersect / queryTokens.length < 0.5)) {
          return 0;
        }
        return (intersect * 60) ~/ total;
      }

      const query = 'Tsuki no Joou no Nekashitsukekata';
      // Exact match
      expect(titleMatchScore('Tsuki no Joou no Nekashitsukekata', query), equals(100));
      // Prefix
      expect(titleMatchScore('Tsuki no Joou no Nekashitsukekata (Official)', query), equals(85));
      // Substring
      expect(titleMatchScore('Komik Tsuki no Joou no Nekashitsukekata', query), equals(75));
      // Partial token overlap (3 of 4 tokens match >= 0.5)
      expect(titleMatchScore('Tsuki no Joou', query), greaterThan(0));

      // Irrelevant partial match on multi-word query (only 1 word matches)
      const nanoQuery = 'Nano Machine';
      expect(titleMatchScore('Sozoshu nano de Motto Yasashikute Kudasai!', nanoQuery), equals(0));
      expect(titleMatchScore('Botsuraku Yotei nano de Kaji Shokunin wo Mezasu', nanoQuery), equals(0));
      expect(titleMatchScore('Nano Machine', nanoQuery), equals(100));
      expect(titleMatchScore('Nano Machine (Official)', nanoQuery), equals(85));
    });
  });
}
