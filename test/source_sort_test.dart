import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/shared/models/manga_source.dart';

void main() {
  group('Source Sort Options Alignment with Backend Endpoints', () {
    test('Softkomik supports only latest and popular', () {
      final sorts = MangaSource.getSortOptionsForSource('softkomik');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'popular']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Populer']));
    });

    test('Komiku supports only latest and popular', () {
      final sorts = MangaSource.getSortOptionsForSource('komiku');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'popular']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Populer']));
    });

    test('Hwago supports latest, popular, rating, and az', () {
      final sorts = MangaSource.getSortOptionsForSource('hwago');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'popular', 'rating', 'az']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Populer', 'Rating', 'A-Z']));
    });

    test('DoujinDesu supports latest, oldest, popular, and az', () {
      final sorts = MangaSource.getSortOptionsForSource('doujindesu');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'oldest', 'popular', 'az']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Terlama', 'Populer', 'A-Z']));
    });

    test('Shinigami supports latest, oldest, popular, and rating', () {
      final sorts = MangaSource.getSortOptionsForSource('shinigami');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'oldest', 'popular', 'rating']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Terlama', 'Populer', 'Rating']));
    });

    test('Komikindo supports latest, popular, az, and za', () {
      final sorts = MangaSource.getSortOptionsForSource('komikindo');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'popular', 'az', 'za']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Populer', 'A-Z', 'Z-A']));
    });

    test('BacaKomik supports latest, newest, popular, az, and za', () {
      final sorts = MangaSource.getSortOptionsForSource('bacakomik');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'newest', 'popular', 'az', 'za']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Diperbarui', 'Populer', 'A-Z', 'Z-A']));
    });

    test('Lumos supports latest, popular, rating, and az', () {
      final sorts = MangaSource.getSortOptionsForSource('lumos');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'popular', 'rating', 'az']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Populer', 'Rating', 'A-Z']));
    });

    test('Holotoon supports latest, popular, rating, and az', () {
      final sorts = MangaSource.getSortOptionsForSource('holotoon');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'popular', 'rating', 'az']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Populer', 'Rating', 'A-Z']));
    });

    test('PixHentai supports latest, indonesia, and english', () {
      final sorts = MangaSource.getSortOptionsForSource('pixhentai');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'indonesia', 'english']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Indonesia', 'English']));
    });

    test('Ikiru supports latest, popular, rating, az, and za', () {
      final sorts = MangaSource.getSortOptionsForSource('ikiru');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'popular', 'rating', 'az', 'za']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Populer', 'Rating', 'A-Z', 'Z-A']));
    });

    test('HentaiCrot supports latest only', () {
      final sorts = MangaSource.getSortOptionsForSource('hentaicrot');
      expect(sorts.map((s) => s.id).toList(), equals(['latest']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru']));
    });

    test('Voratoon supports latest, newest, popular, rating, and az', () {
      final sorts = MangaSource.getSortOptionsForSource('voratoon');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'newest', 'popular', 'rating', 'az']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Diperbarui', 'Populer', 'Rating', 'A-Z']));
    });

    test('Luvyaa supports latest, newest, popular, az, and za', () {
      final sorts = MangaSource.getSortOptionsForSource('luvyaa');
      expect(sorts.map((s) => s.id).toList(), equals(['latest', 'newest', 'popular', 'az', 'za']));
      expect(sorts.map((s) => s.label).toList(), equals(['Terbaru', 'Diperbarui', 'Populer', 'A-Z', 'Z-A']));
    });

    test('MangaSource.fromJson parses dynamic sorts array from backend', () {
      final json = {
        'id': 'custom_source',
        'name': 'Custom Source',
        'sorts': [
          {'id': 'popular', 'name': 'Paling Populer'},
          {'id': 'top', 'name': 'Top All Time'}
        ]
      };
      final source = MangaSource.fromJson(json);
      expect(source.supportedSorts?.length, equals(2));
      expect(source.supportedSorts?[0].id, equals('popular'));
      expect(source.supportedSorts?[0].label, equals('Paling Populer'));
      expect(source.supportedSorts?[1].id, equals('top'));
      expect(source.supportedSorts?[1].label, equals('Top All Time'));
    });
  });

  group('Source Max Selectable Genres Configuration', () {
    test('Single-genre sources return 1', () {
      expect(MangaSource.getMaxSelectableGenres('holotoon'), equals(1));
      expect(MangaSource.getMaxSelectableGenres('pixhentai'), equals(1));
      expect(MangaSource.getMaxSelectableGenres('hentaicrot'), equals(1));
      expect(MangaSource.getMaxSelectableGenres('ikiru'), equals(1));
      expect(MangaSource.getMaxSelectableGenres('softkomik'), equals(1));
    });

    test('Multi-genre sources return their configured limits', () {
      expect(MangaSource.getMaxSelectableGenres('luvyaa'), equals(10));
      expect(MangaSource.getMaxSelectableGenres('bacakomik'), equals(10));
      expect(MangaSource.getMaxSelectableGenres('westmanga'), equals(10));
      expect(MangaSource.getMaxSelectableGenres('komiku'), equals(2));
      expect(MangaSource.getMaxSelectableGenres('voratoon'), equals(5));
    });

    test('Luvyaa supports pornhwa type filter', () {
      final types = MangaSource.getTypesForSource('luvyaa');
      expect(types.any((t) => t['val'] == 'pornhwa'), isTrue);
      expect(MangaSource.formatTypeLabel('pornhwa'), equals('Pornhwa'));
    });
  });
}
