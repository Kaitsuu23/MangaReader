import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/shared/models/pagination.dart';

void main() {
  group('Pagination Model parsing', () {
    test('parses backend response with nextPage correctly as hasNextPage=true', () {
      final json = {
        'page': 1,
        'maxPage': 362,
        'nextPage': 2,
        'prevPage': null,
      };
      final p = Pagination.fromJson(json);
      expect(p.page, equals(1));
      expect(p.maxPage, equals(362));
      expect(p.nextPage, equals(2));
      expect(p.prevPage, isNull);
      expect(p.hasNextPage, isTrue);
    });

    test('parses backend response without maxPage but with nextPage correctly', () {
      final json = {
        'page': 1,
        'nextPage': 2,
        'prevPage': null,
      };
      final p = Pagination.fromJson(json);
      expect(p.hasNextPage, isTrue);
    });

    test('parses last page correctly as hasNextPage=false', () {
      final json = {
        'page': 42,
        'maxPage': 42,
        'nextPage': null,
        'prevPage': 41,
      };
      final p = Pagination.fromJson(json);
      expect(p.hasNextPage, isFalse);
      expect(p.nextPage, isNull);
      expect(p.prevPage, equals(41));
    });

    test('respects explicit hasNextPage boolean if provided', () {
      final jsonTrue = {
        'page': 1,
        'hasNextPage': true,
      };
      expect(Pagination.fromJson(jsonTrue).hasNextPage, isTrue);

      final jsonFalse = {
        'page': 1,
        'hasNextPage': false,
      };
      expect(Pagination.fromJson(jsonFalse).hasNextPage, isFalse);
    });
  });
}
