class MangaItem {
  final String? id;
  final String title;
  final String slug;
  final String? cover;
  final String? type;
  final String? status;
  final String? latestChapter;
  final double? rating;
  final String? contentRating;
  final String? updatedAt;
  final String? source;
  final List<String> genres;

  MangaItem({
    this.id,
    required this.title,
    required this.slug,
    this.cover,
    this.type,
    this.status,
    this.latestChapter,
    this.rating,
    this.contentRating,
    this.updatedAt,
    this.source,
    this.genres = const [],
  });

  /// Converts slug or raw kebab-case / snake-case text (e.g. 'beyond-myriad-peoples') into clean Title Case.
  static String formatTitleFromSlug(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'Tanpa Judul';
    final clean = trimmed.replaceAll(RegExp(r'^/?manga/|/$'), '');
    if (!clean.contains(' ') && (clean.contains('-') || clean.contains('_'))) {
      return clean
          .split(RegExp(r'[-_]'))
          .where((part) => part.isNotEmpty)
          .map((part) => part.length == 1
              ? part.toUpperCase()
              : part[0].toUpperCase() + part.substring(1))
          .join(' ');
    }
    return clean;
  }

  /// Formatted title for UI presentation
  String get displayTitle => formatTitleFromSlug(title);

  factory MangaItem.fromJson(Map<String, dynamic> json, {String? defaultSource}) {
    double? parsedRating;
    if (json['rating'] != null) {
      if (json['rating'] is num) {
        parsedRating = (json['rating'] as num).toDouble();
      } else if (json['rating'] is String) {
        parsedRating = double.tryParse(json['rating']);
      } else if (json['rating'] is Map && json['rating']['value'] != null) {
        parsedRating = (json['rating']['value'] as num?)?.toDouble();
      }
    }

    final rawGenres = json['genres'] as List? ?? [];
    final genres = rawGenres
        .map((g) => g.toString())
        .where((g) => g.isNotEmpty)
        .toList();

    final rawSource = (json['source'] as String?)?.trim();
    final resolvedSource = (rawSource != null && rawSource.isNotEmpty)
        ? rawSource
        : (defaultSource != null && defaultSource.trim().isNotEmpty ? defaultSource.trim() : null);

    return MangaItem(
      id: json['id'] as String? ?? json['mangaId'] as String? ?? json['manga_id'] as String?,
      title: json['title'] as String? ?? 'Tanpa Judul',
      slug: json['slug'] as String? ?? json['title_slug'] as String? ?? '',
      cover: json['cover'] as String?,
      type: json['type'] as String?,
      status: json['status'] as String?,
      latestChapter:
          json['latestChapter']?.toString() ?? json['latest_chapter']?.toString(),
      rating: parsedRating,
      contentRating: json['contentRating'] as String?,
      updatedAt:
          json['updatedAt'] as String? ?? json['updated_at'] as String?,
      source: resolvedSource,
      genres: genres,
    );
  }

  MangaItem copyWith({
    String? id,
    String? title,
    String? slug,
    String? cover,
    String? type,
    String? status,
    String? latestChapter,
    double? rating,
    String? contentRating,
    String? updatedAt,
    String? source,
    List<String>? genres,
  }) {
    return MangaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      cover: cover ?? this.cover,
      type: type ?? this.type,
      status: status ?? this.status,
      latestChapter: latestChapter ?? this.latestChapter,
      rating: rating ?? this.rating,
      contentRating: contentRating ?? this.contentRating,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      genres: genres ?? this.genres,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'title': title,
        'slug': slug,
        'cover': cover,
        'type': type,
        'status': status,
        'latestChapter': latestChapter,
        'rating': rating,
        'contentRating': contentRating,
        'updatedAt': updatedAt,
        'source': source,
        'genres': genres,
      };
}
