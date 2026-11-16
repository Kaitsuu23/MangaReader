class SourceSortOption {
  final String id;
  final String label;

  const SourceSortOption({
    required this.id,
    required this.label,
  });

  factory SourceSortOption.fromJson(Map<String, dynamic> json) {
    return SourceSortOption(
      id: json['id'] as String? ?? '',
      label: json['name'] as String? ?? json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': label,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceSortOption && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class MangaSource {
  final String id;
  final String name;
  final String? icon;
  final List<SourceSortOption>? supportedSorts;

  MangaSource({
    required this.id,
    required this.name,
    this.icon,
    this.supportedSorts,
  });

  factory MangaSource.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    List<SourceSortOption>? sorts;
    if (json['sorts'] is List) {
      sorts = (json['sorts'] as List)
          .map((item) => SourceSortOption.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    return MangaSource(
      id: id,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String?,
      supportedSorts: sorts ?? getSortOptionsForSource(id),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    if (supportedSorts != null)
      'sorts': supportedSorts!.map((s) => s.toJson()).toList(),
  };

  /// Returns the specific sort options supported by each backend source endpoint.
  static List<SourceSortOption> getSortOptionsForSource(String sourceId) {
    switch (sourceId.toLowerCase()) {
      case 'softkomik':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
        ];
      case 'komiku':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
        ];
      case 'hwago':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
          SourceSortOption(id: 'az', label: 'A-Z'),
        ];
      case 'doujindesu':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'oldest', label: 'Terlama'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
        ];
      case 'shinigami':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'oldest', label: 'Terlama'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
        ];
      case 'kiryuu':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'oldest', label: 'Terlama'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'komiktap':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'westmanga':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'komikindo':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'apkomik':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'bacakomik':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'lumos':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
          SourceSortOption(id: 'az', label: 'A-Z'),
        ];
      case 'holotoon':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
          SourceSortOption(id: 'az', label: 'A-Z'),
        ];
      case 'pixhentai':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'indonesia', label: 'Indonesia'),
          SourceSortOption(id: 'english', label: 'English'),
        ];
      case 'ikiru':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'hentaicrot':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
        ];
      case 'voratoon':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
          SourceSortOption(id: 'az', label: 'A-Z'),
        ];
      case 'luvyaa':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'crotpedia':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'mihentai':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'ainz':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'soulscans':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'komikstation':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'komikindoch':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'sasangeyou':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'kanzenin':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'mangasusuku':
      case 'mangsusuku':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'izanamiscans':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'az', label: 'A-Z'),
        ];
      case 'cgbum':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'oldest', label: 'Terlama'),
          SourceSortOption(id: 'popular', label: 'Populer'),
        ];
      case 'lepoytl':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
        ];
      case 'yurilab':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
        ];
      case 'maid':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'natsu':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'komikremaja':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'az', label: 'A-Z'),
          SourceSortOption(id: 'za', label: 'Z-A'),
        ];
      case 'shirodoujin':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'rating', label: 'Rating'),
        ];
      case 'komikapk':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'popular18', label: 'Popular18'),
        ];
      case 'mangapill':
        return const [
          SourceSortOption(id: 'latest', label: 'Chapter Terbaru'),
          SourceSortOption(id: 'newest', label: 'Manga Terbaru'),
        ];
      case 'fanfox':
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'newest', label: 'Diperbarui'),
          SourceSortOption(id: 'popular', label: 'Populer'),
          SourceSortOption(id: 'rating', label: 'Rating'),
        ];
      default:
        return const [
          SourceSortOption(id: 'latest', label: 'Terbaru'),
          SourceSortOption(id: 'popular', label: 'Populer'),
        ];
    }
  }

  /// Returns maximum number of selectable genres for the given source:
  /// - 1: Single-select only (radio button behavior)
  /// - >1: Multi-select up to the returned limit (checkbox behavior)
  static int getMaxSelectableGenres(String sourceId) {
    switch (sourceId.toLowerCase()) {
      case 'softkomik':
      case 'holotoon':
      case 'pixhentai':
      case 'hentaicrot':
      case 'ikiru':
      case 'ainz':
      case 'soulscans':
      case 'komikindoch':
      case 'yurilab':
      case 'komikapk':
      case 'fanfox':
        return 1;
      case 'lepoytl':
        return 0;
      case 'komiku':
        return 2;
      case 'westmanga':
      case 'bacakomik':
      case 'luvyaa':
      case 'crotpedia':
      case 'mihentai':
      case 'komikstation':
      case 'sasangeyou':
      case 'kanzenin':
      case 'mangasusuku':
      case 'mangsusuku':
      case 'izanamiscans':
      case 'cgbum':
      case 'maid':
      case 'natsu':
      case 'komikremaja':
      case 'shirodoujin':
      case 'mangapill':
        return 10;
      default:
        return 5;
    }
  }

  static List<Map<String, String>> getTypesForSource(String sourceId) {
    switch (sourceId.toLowerCase()) {
      case 'lepoytl':
      case 'fanfox':
        return const [];
      case 'komikapk':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
        ];
      case 'mangapill':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Novel', 'val': 'novel'},
          {'label': 'One-Shot', 'val': 'one-shot'},
          {'label': 'Doujinshi', 'val': 'doujinshi'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
          {'label': 'OEL', 'val': 'oel'},
        ];
      case 'ainz':
      case 'soulscans':
      case 'komikstation':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
        ];
      case 'maid':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
          {'label': 'Doujin', 'val': 'doujin'},
        ];
      case 'natsu':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
          {'label': 'Comic', 'val': 'comic'},
          {'label': 'Novel', 'val': 'novel'},
        ];
      case 'komikremaja':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
        ];
      case 'shirodoujin':
        return const [
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Doujinshi', 'val': 'doujinshi'},
        ];
      case 'crotpedia':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Doujinshi', 'val': 'doujinshi'},
        ];
      case 'mihentai':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
        ];
      case 'sasangeyou':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
          {'label': 'Comic', 'val': 'comic'},
          {'label': 'Game', 'val': 'game'},
        ];
      case 'doujindesu':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Doujinshi', 'val': 'doujinshi'},
        ];
      case 'kiryuu':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
          {'label': 'Mangatoon', 'val': 'mangatoon'},
        ];
      case 'komiktap':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
          {'label': 'Comic', 'val': 'comic'},
        ];
      case 'voratoon':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
          {'label': 'Mangatoon', 'val': 'mangatoon'},
        ];
      case 'luvyaa':
      case 'cgbum':
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
          {'label': 'Pornhwa', 'val': 'pornhwa'},
        ];
      default:
        return const [
          {'label': 'Manga', 'val': 'manga'},
          {'label': 'Komik Korea (Manhwa)', 'val': 'manhwa'},
          {'label': 'Komik Mandarin (Manhua)', 'val': 'manhua'},
        ];
    }
  }

  static String formatTypeLabel(String? type) {
    if (type == null) return '';
    switch (type.toLowerCase()) {
      case 'manga':
        return 'Manga';
      case 'manhwa':
        return 'Komik Korea (Manhwa)';
      case 'manhua':
        return 'Komik Mandarin (Manhua)';
      case 'doujinshi':
        return 'Doujinshi';
      case 'comic':
        return 'Comic';
      case 'novel':
        return 'Novel';
      case 'mangatoon':
        return 'Mangatoon';
      case 'pornhwa':
        return 'Pornhwa';
      default:
        return type;
    }
  }

  /// Returns the primary website URL for the given source ID
  static String getBaseUrlForSource(String sourceId) {
    switch (sourceId.toLowerCase()) {
      case 'shinigami':
        return 'https://11.shinigami.asia';
      case 'softkomik':
        return 'https://softkomik.app';
      case 'kiryuu':
        return 'https://v7.kiryuu.to';
      case 'komiku':
        return 'https://komiku.org';
      case 'hwago':
        return 'https://01.hwago.com';
      case 'doujindesu':
        return 'https://doujin.desu.xxx';
      case 'komiktap':
        return 'https://komiktap.info';
      case 'westmanga':
        return 'https://v1.westmanga.my';
      case 'komikindo':
        return 'https://komikindo.click';
      case 'apkomik':
        return 'https://01.apkomik.com';
      case 'bacakomik':
        return 'https://bacakomik.my';
      case 'lumos':
        return 'https://03.lumosgg.com';
      case 'holotoon':
        return 'https://holodek.run';
      case 'pixhentai':
        return 'https://pixhentai.com';
      case 'ikiru':
        return 'https://09.ikiru.wtf';
      case 'hentaicrot':
        return 'https://hentaicrot.com';
      case 'voratoon':
        return 'https://v10.voratoon.com';
      case 'luvyaa':
        return 'https://v5.luvyaa.co';
      case 'crotpedia':
        return 'https://crotpedia.net';
      case 'mihentai':
        return 'https://mihentai.net';
      case 'ainz':
        return 'https://v3.ainzscans01.com';
      case 'soulscans':
        return 'https://v1.soulscans.asia';
      case 'komikstation':
        return 'https://komikstation.org';
      case 'komikindoch':
        return 'https://komikindo.ch';
      case 'sasangeyou':
        return 'https://sasangeyou.net';
      case 'kanzenin':
        return 'https://kanzenin.info';
      case 'mangasusuku':
      case 'mangsusuku':
        return 'https://mangasusuku.com';
      case 'izanamiscans':
        return 'https://izanamiscans.my.id';
      case 'cgbum':
        return 'https://cgbum.com';
      case 'lepoytl':
        return 'https://www.lepoytl.my.id';
      case 'yurilab':
        return 'https://yurilab.top';
      case 'maid':
        return 'https://www.maid.my.id';
      case 'natsu':
        return 'https://natsu.one';
      case 'komikremaja':
        return 'https://komikremaja.art';
      case 'shirodoujin':
        return 'https://shirodoujin.com';
      case 'komikapk':
        return 'https://komikapk.app';
      case 'mangapill':
        return 'https://mangapill.com';
      case 'fanfox':
        return 'https://newm.fanfox.net';
      default:
        return 'https://$sourceId.com';
    }
  }
}
