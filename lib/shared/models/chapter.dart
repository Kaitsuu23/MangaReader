import '../utils/chapter_date_formatter.dart';

class Chapter {
  final String chapter;
  final String title;
  final String slug;
  final String? date;

  Chapter({
    required this.chapter,
    required this.title,
    required this.slug,
    this.date,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    final rawChapter = json['chapter']?.toString().trim() ?? '';
    String rawSlug = json['slug']?.toString().trim() ??
        json['chapterSlug']?.toString().trim() ??
        '';

    if (rawSlug.isEmpty && rawChapter.isNotEmpty) {
      rawSlug = rawChapter;
    }
    if (rawSlug.isEmpty && json['endpoint'] != null) {
      final endpointStr = json['endpoint'].toString().trim().replaceAll(RegExp(r'/+$'), '');
      final parts = endpointStr.split('/');
      if (parts.isNotEmpty && parts.last.isNotEmpty) {
        rawSlug = parts.last;
      }
    }
    if (rawSlug.isEmpty && json['title'] != null) {
      final match = RegExp(r'Chapter\s+([0-9.]+)', caseSensitive: false)
          .firstMatch(json['title'].toString());
      if (match != null) {
        rawSlug = match.group(1)!;
      }
    }

    final rawTitle = json['title'] as String? ?? (rawChapter.isNotEmpty ? 'Chapter $rawChapter' : 'Chapter');

    return Chapter(
      chapter: rawChapter.isNotEmpty ? rawChapter : rawSlug,
      title: rawTitle,
      slug: rawSlug,
      date: json['date'] as String?
          ?? json['uploadDate'] as String?
          ?? json['releaseDate'] as String?
          ?? json['createdAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'chapter': chapter,
    'title': title,
    'slug': slug,
    'date': date,
  };

  /// Format tanggal bab terpadu bergaya Kotatsu-Redo
  String? get formattedDate {
    if (date == null || date!.trim().isEmpty) return null;
    return ChapterDateFormatter.format(date);
  }

  /// Subtitle bab terpadu bergaya Kotatsu-Redo (e.g. "#124 • 2 jam lalu", "#124 • 15 Okt", atau "15 Okt")
  String? get chapterSubtitle {
    final fDate = formattedDate;
    final num = chapterNumber;

    final parts = <String>[];
    if (num != null && num > 0) {
      final numStr = (num % 1 == 0) ? num.toInt().toString() : num.toString();
      parts.add('#$numStr');
    }
    if (fDate != null && fDate.isNotEmpty) {
      parts.add(fDate);
    }

    if (parts.isEmpty) return null;
    return parts.join(' • ');
  }

  /// Ekstraksi nomor chapter secara cerdas untuk pengurutan kronologis
  double? get chapterNumber {
    // 1. Coba parse langsung jika chapter adalah angka murni ("1", "2.5", "100")
    final direct = double.tryParse(chapter.trim());
    if (direct != null) return direct;

    // 2. Deteksi prologue / bab pengantar
    final lowerTitle = title.toLowerCase();
    final lowerChapter = chapter.toLowerCase();
    final lowerSlug = slug.toLowerCase();
    if (lowerTitle.contains('prolog') ||
        lowerChapter.contains('prolog') ||
        lowerSlug.contains('prolog')) {
      return 0.0;
    }

    // 3. Regex pada field chapter: misal "Ch. 1", "Chapter 25", "Bab 10"
    final chMatch = RegExp(r'(?:ch(?:apter)?\.?|bab|#)\s*([0-9]+(?:\.[0-9]+)?)', caseSensitive: false)
        .firstMatch(chapter);
    if (chMatch != null) return double.tryParse(chMatch.group(1)!);

    // 4. Regex pada field title: misal "Chapter 25: Judul", "Bab 3 - Pertarungan"
    final titleMatch = RegExp(r'(?:ch(?:apter)?\.?|bab|#)\s*([0-9]+(?:\.[0-9]+)?)', caseSensitive: false)
        .firstMatch(title);
    if (titleMatch != null) return double.tryParse(titleMatch.group(1)!);

    // 5. Regex pada slug: misal "chapter-25-bahasa-indonesia", "bab-1.5"
    final slugMatch = RegExp(r'(?:chapter|ch|bab)[-_]?([0-9]+(?:[-.][0-9]+)?)', caseSensitive: false)
        .firstMatch(slug);
    if (slugMatch != null) {
      final clean = slugMatch.group(1)!.replaceAll('-', '.');
      return double.tryParse(clean);
    }

    // 6. Angka standalone pada chapter
    final numMatch = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(chapter);
    if (numMatch != null) return double.tryParse(numMatch.group(1)!);

    // 7. Angka standalone berbatas kata pada title
    final numTitleMatch = RegExp(r'\b([0-9]+(?:\.[0-9]+)?)\b').firstMatch(title);
    if (numTitleMatch != null) return double.tryParse(numTitleMatch.group(1)!);

    return null;
  }

  /// Memastikan urutan list bab kronologis dari bab paling awal (Bab 1) sampai terbaru
  static List<Chapter> sortChronological(List<Chapter> chapters) {
    if (chapters.length <= 1) return List<Chapter>.from(chapters);

    // Cari bab pertama yang memiliki nomor valid
    double? firstNum;
    for (final ch in chapters) {
      final n = ch.chapterNumber;
      if (n != null) {
        firstNum = n;
        break;
      }
    }

    // Cari bab terakhir yang memiliki nomor valid
    double? lastNum;
    for (final ch in chapters.reversed) {
      final n = ch.chapterNumber;
      if (n != null) {
        lastNum = n;
        break;
      }
    }

    // Jika bab di awal lebih besar daripada bab di akhir (misal Bab 100 di awal, Bab 1 di akhir),
    // artinya list dari parser adalah descending. Kita balik agar Bab 1 berada di index 0.
    if (firstNum != null && lastNum != null && firstNum > lastNum) {
      return chapters.reversed.toList();
    }

    return List<Chapter>.from(chapters);
  }
}
