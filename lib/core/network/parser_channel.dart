import 'package:flutter/services.dart';
import '../../shared/models/manga_source.dart';
import '../../shared/models/manga_item.dart';
import '../../shared/models/manga_details.dart';
import '../../shared/models/chapter_pages.dart';
import '../../shared/models/genre.dart';
import '../../shared/models/page_slices.dart';
import '../../shared/models/pagination.dart';

/// Flutter-side client that calls the Kotlin manga parsers via MethodChannel.
/// Drop-in replacement for [ApiClient] — same method signatures.
class ParserChannel {
  static const _channel = MethodChannel('org.dhiksn.yomika/manga');

  // ── Sources ───────────────────────────────────────────────────────────────

  Future<List<MangaSource>> getSources() async {
    final list = await _channel.invokeListMethod<Map>('getSources') ?? [];
    return list.map((m) => MangaSource.fromJson(Map<String, dynamic>.from(m))).toList();
  }

  // ── List pages ────────────────────────────────────────────────────────────

  Future<({List<MangaItem> data, Pagination? pagination})> getPopular(
    String source, {
    int page = 1,
    String? status,
  }) async {
    final res = await _invoke('getPopular', {
      'source': source,
      'page': page,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return _parseListResult(res, source);
  }

  Future<({List<MangaItem> data, Pagination? pagination})> getLatest(
    String source, {
    int page = 1,
    String? category,
    String? status,
  }) async {
    final res = await _invoke('getLatest', {
      'source': source,
      'page': page,
      'category': category ?? 'all',
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return _parseListResult(res, source);
  }

  Future<({List<MangaItem> data, Pagination? pagination})> search(
    String source,
    String query, {
    int page = 1,
  }) async {
    final res = await _invoke('search', {'source': source, 'query': query, 'page': page});
    return _parseListResult(res, source);
  }

  // ── Unified list query & sort dispatch ───────────────────────────────────

  Future<({List<MangaItem> data, Pagination? pagination})> getList(
    String source, {
    int page = 1,
    String? sort,
    String? status,
    String? genre,
    String? type,
    String? category,
    String? tema,
    String? demografis,
  }) async {
    final res = await _invoke('getList', {
      'source': source,
      'page': page,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
      if (status != null && status.isNotEmpty) 'status': status,
      if (genre != null && genre.isNotEmpty) 'genre': genre,
      if (type != null && type.isNotEmpty) 'type': type,
      if (category != null && category.isNotEmpty) 'category': category,
      if (tema != null && tema.isNotEmpty) 'tema': tema,
      if (demografis != null && demografis.isNotEmpty) 'demografis': demografis,
    });
    return _parseListResult(res, source);
  }

  Future<({List<MangaItem> data, Pagination? pagination})> getBySort(
    String source,
    String sortId, {
    int page = 1,
    String? category,
    String? status,
    String? genre,
    String? type,
    String? tema,
    String? demografis,
  }) async {
    return getList(
      source,
      page: page,
      sort: sortId,
      status: status,
      genre: genre,
      type: type,
      category: category,
      tema: tema,
      demografis: demografis,
    );
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  final Map<String, List<Genre>> _genresCache = {};
  final Map<String, List<Genre>> _temaCache = {};
  final Map<String, List<Genre>> _demografisCache = {};

  Future<List<Genre>> getGenres(String source) async {
    if (_genresCache.containsKey(source)) return _genresCache[source]!;
    final list = await _channel.invokeListMethod<Map>('getGenres', {'source': source}) ?? [];
    final genres = list.map((m) => Genre.fromJson(Map<String, dynamic>.from(m))).toList();
    if (genres.isNotEmpty) _genresCache[source] = genres;
    return genres;
  }

  Future<List<Genre>> getTema(String source) async {
    if (_temaCache.containsKey(source)) return _temaCache[source]!;
    final list = await _channel.invokeListMethod<Map>('getTema', {'source': source}) ?? [];
    final items = list.map((m) => Genre.fromJson(Map<String, dynamic>.from(m))).toList();
    if (items.isNotEmpty) _temaCache[source] = items;
    return items;
  }

  Future<List<Genre>> getDemografis(String source) async {
    if (_demografisCache.containsKey(source)) return _demografisCache[source]!;
    final list = await _channel.invokeListMethod<Map>('getDemografis', {'source': source}) ?? [];
    final items = list.map((m) => Genre.fromJson(Map<String, dynamic>.from(m))).toList();
    if (items.isNotEmpty) _demografisCache[source] = items;
    return items;
  }

  Future<({List<MangaItem> data, Pagination? pagination})> getByGenre(
    String source,
    String genre, {
    int page = 1,
    String? status,
  }) async {
    final res = await _invoke('getByGenre', {
      'source': source,
      'genre': genre,
      'page': page,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return _parseListResult(res, source);
  }

  Future<List<String>> getTypes(String source) async {
    final list = await _channel.invokeListMethod<String>('getTypes', {'source': source});
    return list ?? ['manga', 'manhwa', 'manhua'];
  }

  Future<({List<MangaItem> data, Pagination? pagination})> getByType(
    String source,
    String type, {
    int page = 1,
    String? status,
  }) async {
    final res = await _invoke('getByType', {
      'source': source,
      'type': type,
      'page': page,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return _parseListResult(res, source);
  }

  // ── Details & pages ───────────────────────────────────────────────────────

  Future<MangaDetails> getDetails(String source, String slug) async {
    final res = await _invoke('getDetails', {'source': source, 'slug': slug});
    return MangaDetails.fromJson(res, defaultSource: source);
  }

  Future<ChapterPages> getPages(
    String source,
    String slug,
    String chapter, {
    String? cdn,
    int? server,
  }) async {
    final serverNum = server ??
        (cdn != null ? int.tryParse(cdn.replaceAll(RegExp(r'\D'), '')) : null) ??
        1;
    final res = await _invoke('getPages', {
      'source': source,
      'slug': slug,
      'chapter': chapter,
      'server': serverNum,
    });
    return ChapterPages.fromJson(res);
  }

  // ── Images ────────────────────────────────────────────────────────────────

  /// Splits a very tall page into smaller vertical slices natively.
  ///
  /// Flutter's Impeller renderer squashes images taller than the GPU max
  /// texture size, so tall webtoon pages are sliced before they reach Flutter.
  /// Returns `null` when slicing is not available for this URL/format.
  Future<PageSlices?> getPageSlices(
    String url, {
    String? referer,
    int? sliceHeight,
  }) async {
    final Map<String, dynamic>? res;
    try {
      res = await _channel.invokeMapMethod<String, dynamic>('getPageSlices', {
        'url': url,
        if (referer != null && referer.isNotEmpty) 'referer': referer,
        'sliceHeight': ?sliceHeight,
      });
    } catch (_) {
      return null;
    }
    if (res == null) return null;
    final slices = PageSlices.fromJson(res);
    return slices.slices.isEmpty ? null : slices;
  }

  /// Clears the native on-disk page-slice cache.
  Future<void> clearPageSliceCache() async {
    try {
      await _channel.invokeMethod('clearPageSliceCache');
    } catch (_) {}
  }

  /// Configures DNS over HTTPS on the native OkHttp client.
  static Future<void> setDohConfig(String provider, {String? customUrl}) async {
    try {
      await _channel.invokeMethod('setDohConfig', {
        'provider': provider,
        if (customUrl != null && customUrl.isNotEmpty) 'customUrl': customUrl,
      });
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _invoke(String method, Map<String, dynamic> args) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(method, args);
    return raw ?? {};
  }

  ({List<MangaItem> data, Pagination? pagination}) _parseListResult(
    Map<String, dynamic> res,
    String source,
  ) {
    final rawList = res['data'] as List? ?? [];
    final data = rawList
        .map((i) => MangaItem.fromJson(Map<String, dynamic>.from(i), defaultSource: source))
        .toList();

    final page = (res['page'] as num?)?.toInt() ?? 1;
    final hasNext = res['hasNextPage'] as bool? ?? false;
    final pagination = Pagination(
      page: page,
      hasNextPage: hasNext,
      nextPage: hasNext ? page + 1 : null,
      prevPage: page > 1 ? page - 1 : null,
    );
    return (data: data, pagination: pagination);
  }
}
