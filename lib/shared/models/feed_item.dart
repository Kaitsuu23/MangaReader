class FeedItem {
  final String id;
  final String mangaSlug;
  final String mangaTitle;
  final String? mangaCover;
  final String mangaSource;
  final int newChaptersCount;
  final List<String> newChapters;
  final List<String> newChapterSlugs;
  final int createdAt; // epoch ms
  final bool isNew; // unread flag
  final String? modeId;
  final String? modeName;

  FeedItem({
    required this.id,
    required this.mangaSlug,
    required this.mangaTitle,
    this.mangaCover,
    required this.mangaSource,
    required this.newChaptersCount,
    this.newChapters = const [],
    this.newChapterSlugs = const [],
    required this.createdAt,
    this.isNew = true,
    this.modeId,
    this.modeName,
  });

  bool get isValid =>
      mangaSlug.trim().isNotEmpty &&
      mangaTitle.trim().isNotEmpty &&
      mangaSource.trim().isNotEmpty &&
      mangaSource.toLowerCase() != 'unknown';

  FeedItem copyWith({
    String? id,
    String? mangaSlug,
    String? mangaTitle,
    String? mangaCover,
    String? mangaSource,
    int? newChaptersCount,
    List<String>? newChapters,
    List<String>? newChapterSlugs,
    int? createdAt,
    bool? isNew,
    String? modeId,
    String? modeName,
  }) {
    return FeedItem(
      id: id ?? this.id,
      mangaSlug: mangaSlug ?? this.mangaSlug,
      mangaTitle: mangaTitle ?? this.mangaTitle,
      mangaCover: mangaCover ?? this.mangaCover,
      mangaSource: mangaSource ?? this.mangaSource,
      newChaptersCount: newChaptersCount ?? this.newChaptersCount,
      newChapters: newChapters ?? this.newChapters,
      newChapterSlugs: newChapterSlugs ?? this.newChapterSlugs,
      createdAt: createdAt ?? this.createdAt,
      isNew: isNew ?? this.isNew,
      modeId: modeId ?? this.modeId,
      modeName: modeName ?? this.modeName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mangaSlug': mangaSlug,
    'mangaTitle': mangaTitle,
    'mangaCover': mangaCover,
    'mangaSource': mangaSource,
    'newChaptersCount': newChaptersCount,
    'newChapters': newChapters,
    'newChapterSlugs': newChapterSlugs,
    'createdAt': createdAt,
    'isNew': isNew,
    if (modeId != null) 'modeId': modeId,
    if (modeName != null) 'modeName': modeName,
  };

  factory FeedItem.fromJson(Map<String, dynamic> json) => FeedItem(
    id: json['id'] as String? ?? '${json['mangaSlug']}_${json['createdAt']}',
    mangaSlug: json['mangaSlug'] as String? ?? '',
    mangaTitle: json['mangaTitle'] as String? ?? '',
    mangaCover: json['mangaCover'] as String?,
    mangaSource: json['mangaSource'] as String? ?? 'unknown',
    newChaptersCount: json['newChaptersCount'] as int? ?? 1,
    newChapters: (json['newChapters'] as List?)?.map((e) => e.toString()).toList() ?? [],
    newChapterSlugs: (json['newChapterSlugs'] as List?)?.map((e) => e.toString()).toList() ?? [],
    createdAt: json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    isNew: json['isNew'] as bool? ?? true,
    modeId: json['modeId'] as String?,
    modeName: json['modeName'] as String?,
  );
}
