import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/shared/models/chapter.dart';

void main() {
  group('Chapter Model & Sorting Tests', () {
    test('extracts chapterNumber correctly across various formats', () {
      expect(Chapter(chapter: '1', title: 'Chapter 1', slug: 'ch-1').chapterNumber, 1.0);
      expect(Chapter(chapter: '2.5', title: 'Chapter 2.5', slug: 'ch-2-5').chapterNumber, 2.5);
      expect(Chapter(chapter: 'ch-28', title: 'Bab 28', slug: 'bab-28').chapterNumber, 28.0);
      expect(Chapter(chapter: '', title: 'Chapter 94 - Final', slug: 'slug-94').chapterNumber, 94.0);
      expect(Chapter(chapter: 'prologue', title: 'Prolog', slug: 'prologue').chapterNumber, 0.0);
    });

    test('sortChronological reverses descending parser lists to ascending order', () {
      final descendingList = [
        Chapter(chapter: '', title: 'Pengumuman Libur', slug: 'notice'),
        Chapter(chapter: '3', title: 'Bab 3', slug: 'ch-3'),
        Chapter(chapter: '2', title: 'Bab 2', slug: 'ch-2'),
        Chapter(chapter: '1', title: 'Bab 1', slug: 'ch-1'),
      ];

      final sorted = Chapter.sortChronological(descendingList);
      expect(sorted.first.slug, 'ch-1');
      expect(sorted[1].slug, 'ch-2');
      expect(sorted[2].slug, 'ch-3');
      expect(sorted.last.slug, 'notice');
    });

    test('sortChronological preserves already ascending lists', () {
      final ascendingList = [
        Chapter(chapter: '1', title: 'Bab 1', slug: 'ch-1'),
        Chapter(chapter: '2', title: 'Bab 2', slug: 'ch-2'),
        Chapter(chapter: '3', title: 'Bab 3', slug: 'ch-3'),
      ];

      final sorted = Chapter.sortChronological(ascendingList);
      expect(sorted.first.slug, 'ch-1');
      expect(sorted[1].slug, 'ch-2');
      expect(sorted.last.slug, 'ch-3');
    });
  });
}
