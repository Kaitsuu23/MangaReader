import 'chapter.dart';
import 'genre.dart';
import 'manga_item.dart';

class SeriesItem {
  final String title;
  final String? slug;

  const SeriesItem({
    required this.title,
    this.slug,
  });

  factory SeriesItem.fromJson(Map<String, dynamic> json) {
    return SeriesItem(
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'slug': slug,
  };
}

class MangaDetails {
  final String? id;
  final String source;
  final String title;
  final String? altTitle;
  final String? cover;
  final String? synopsis;
  final String? author;
  final String? year;
  final String? status;
  final String? type;
  final List<Genre> genres;
  final double? rating;
  final int totalChapters;
  final List<Chapter> chapters;
  final List<MangaItem> similar;
  final List<SeriesItem> series;

  String get slug => (id != null && id!.isNotEmpty) ? id! : '';

  MangaDetails({
    this.id,
    required this.source,
    required this.title,
    this.altTitle,
    this.cover,
    this.synopsis,
    this.author,
    this.year,
    this.status,
    this.type,
    required this.genres,
    this.rating,
    required this.totalChapters,
    required this.chapters,
    required this.similar,
    this.series = const [],
  });

  factory MangaDetails.fromJson(Map<String, dynamic> json, {required String defaultSource}) {
    final rawGenres = json['genres'] as List? ?? json['Genre'] as List? ?? [];
    final genres = rawGenres.map((g) => Genre.fromJson(g)).toList();

    final rawChapters = json['chapters'] as List? ?? [];
    final chapters = rawChapters.map((ch) => Chapter.fromJson(Map<String, dynamic>.from(ch))).toList();

    final rawSimilar = (json['similar'] as List?) ?? (json['related'] as List?) ?? [];
    final similar = rawSimilar.map((s) => MangaItem.fromJson(Map<String, dynamic>.from(s), defaultSource: defaultSource)).toList();

    final rawSeries = json['series'] as List? ?? [];
    final series = rawSeries.map((s) => SeriesItem.fromJson(Map<String, dynamic>.from(s))).toList();

    double? parsedRating;
    if (json['rating'] != null) {
      if (json['rating'] is num) {
        parsedRating = (json['rating'] as num).toDouble();
      } else if (json['rating'] is String) {
        parsedRating = double.tryParse(json['rating']);
      }
    }

    return MangaDetails(
      id: json['id'] as String? ?? json['mangaId'] as String? ?? json['manga_id'] as String?,
      source: json['source'] as String? ?? defaultSource,
      title: json['title'] as String? ?? '',
      altTitle: json['altTitle'] as String? ?? json['title_alt'] as String?,
      cover: json['cover'] as String?,
      synopsis: json['synopsis'] as String? ?? json['sinopsis'] as String?,
      author: json['author'] as String?,
      year: json['year']?.toString() ?? json['tahun']?.toString(),
      status: json['status'] as String?,
      type: json['type'] as String?,
      genres: genres,
      rating: parsedRating,
      totalChapters: (json['totalChapters'] as num?)?.toInt() ?? chapters.length,
      chapters: chapters,
      similar: similar,
      series: series,
    );
  }
}
