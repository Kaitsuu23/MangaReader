import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/manga_item.dart';
import '../../shared/models/genre.dart';

final popularMangaProvider =
    FutureProvider.family<List<MangaItem>, String>((ref, source) async {
  final parser = ref.watch(parserChannelProvider);
  final result = await parser.getPopular(source, page: 1);
  return result.data;
});

final latestMangaProvider =
    FutureProvider.family<List<MangaItem>, String>((ref, source) async {
  final parser = ref.watch(parserChannelProvider);
  final result = await parser.getLatest(source, page: 1);
  return result.data;
});

// Rating sort — falls back to popular if source doesn't support it
final ratingMangaProvider =
    FutureProvider.family<List<MangaItem>, String>((ref, source) async {
  final parser = ref.watch(parserChannelProvider);
  try {
    final result = await parser.getBySort(source, 'rating', page: 1);
    return result.data;
  } catch (_) {
    return [];
  }
});

final genresListProvider =
    FutureProvider.family<List<Genre>, String>((ref, source) async {
  final parser = ref.watch(parserChannelProvider);
  return parser.getGenres(source);
});
