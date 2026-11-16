class Genre {
  final String name;
  final String slug;

  Genre({
    required this.name,
    required this.slug,
  });

  factory Genre.fromJson(dynamic json) {
    if (json is String) {
      final clean = json.trim();
      return Genre(
        name: clean,
        slug: clean.toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
      );
    }
    if (json is Map) {
      final name = json['name'] as String? ?? json['label'] as String? ?? '';
      final slug = json['slug'] as String? ?? name.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
      return Genre(name: name, slug: slug);
    }
    return Genre(name: '', slug: '');
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'slug': slug,
  };
}
