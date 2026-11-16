class MangaPage {
  final int page;
  final String url;
  final String? directUrl;
  final String? proxyUrl;

  MangaPage({
    required this.page,
    required this.url,
    this.directUrl,
    this.proxyUrl,
  });

  factory MangaPage.fromJson(Map<String, dynamic> json) {
    return MangaPage(
      page: (json['page'] as num?)?.toInt() ?? 1,
      url: json['url'] as String? ?? json['proxyUrl'] as String? ?? '',
      directUrl: json['directUrl'] as String?,
      proxyUrl: json['proxyUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'page': page,
    'url': url,
    'directUrl': directUrl,
    'proxyUrl': proxyUrl,
  };
}

class ChapterPages {
  final String? manga;
  final String? chapter;
  final int totalPages;
  final List<MangaPage> pages;
  final String? referer;

  ChapterPages({
    this.manga,
    this.chapter,
    required this.totalPages,
    required this.pages,
    this.referer,
  });

  factory ChapterPages.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'] as List? ?? [];
    final pages = rawPages.map((p) => MangaPage.fromJson(Map<String, dynamic>.from(p))).toList();

    return ChapterPages(
      manga: json['manga'] as String?,
      chapter: json['chapter']?.toString(),
      totalPages: (json['totalPages'] as num?)?.toInt() ?? pages.length,
      pages: pages,
      referer: json['referer'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'manga': manga,
    'chapter': chapter,
    'totalPages': totalPages,
    'pages': pages.map((p) => p.toJson()).toList(),
    if (referer != null) 'referer': referer,
  };
}
