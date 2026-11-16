import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/shared/models/manga_details.dart';

void main() {
  group('MangaDetails Series Tests', () {
    test('Series parsing handles multipart doujinshi correctly', () {
      final json = {
        'id': 'maid-no-shirasaki-san-ni-gohoushi-shite-morau-hanashi-part-3',
        'source': 'pixhentai',
        'title': 'Maid no Shirasaki-san ni Gohoushi Shite Morau Hanashi part 3',
        'synopsis': 'Sinopsis...',
        'series': [
          {
            'title': 'Maid no Shirasaki-san ni Gohoushi Shite Morau Hanashi',
            'slug': 'maid-no-shirasaki-san-ni-gohoushi-shite-morau-hanashi',
          },
          {
            'title': 'Maid no Shirasaki-san ni Gohoushi Shite Morau Hanashi part 2',
            'slug': 'maid-no-shirasaki-san-ni-gohoushi-shite-morau-hanashi-part-2',
          },
          {
            'title': 'Maid no Shirasaki-san ni Gohoushi Shite Morau Hanashi part 3',
            'slug': null,
          },
        ],
        'chapters': [
          {
            'id': 'maid-no-shirasaki-san-ni-gohoushi-shite-morau-hanashi-part-3',
            'slug': 'maid-no-shirasaki-san-ni-gohoushi-shite-morau-hanashi-part-3',
            'title': 'Chapter 1 - Full',
            'chapterNumber': 1.0,
          }
        ],
        'genres': [],
        'similar': [],
      };

      final details = MangaDetails.fromJson(json, defaultSource: 'pixhentai');

      expect(details.slug, equals('maid-no-shirasaki-san-ni-gohoushi-shite-morau-hanashi-part-3'));
      expect(details.series.length, equals(3));
      expect(details.series[0].title, equals('Maid no Shirasaki-san ni Gohoushi Shite Morau Hanashi'));
      expect(details.series[0].slug, equals('maid-no-shirasaki-san-ni-gohoushi-shite-morau-hanashi'));
      expect(details.series[1].slug, equals('maid-no-shirasaki-san-ni-gohoushi-shite-morau-hanashi-part-2'));
      expect(details.series[2].slug, isNull);

      // Chapters must only contain single gallery chapter (not series parts)
      expect(details.chapters.length, equals(1));
      expect(details.chapters.first.title, equals('Chapter 1 - Full'));
    });
  });
}
