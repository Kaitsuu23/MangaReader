import '../../core/storage/local_storage.dart';

/// Kotatsu-Redo inspired global chapter date formatter.
/// Emulates Kotatsu's [DateUtils.getRelativeTimeSpanString(uploadDate, now, DAY_IN_MILLIS)]
/// and formats chapter dates seamlessly based on user preference:
/// - 'relative_smart' (Default): Relative ("2 jam lalu", "Kemarin", "3 hari lalu") for recent chapters (< 7 days),
///   and clean compact calendar date ("15 Okt" for current year, "15 Okt 2023" for older years).
/// - 'relative': Always relative time ("2 jam lalu", "3 hari lalu", "2 bulan lalu").
/// - 'absolute': Always calendar date ("15 Oktober 2024").
/// - 'hidden': Date is hidden.
class ChapterDateFormatter {
  static const Map<String, int> _indonesianMonths = {
    'januari': 1, 'jan': 1,
    'februari': 2, 'feb': 2,
    'maret': 3, 'mar': 3,
    'april': 4, 'apr': 4,
    'mei': 5, 'may': 5,
    'juni': 6, 'jun': 6,
    'juli': 7, 'jul': 7,
    'agustus': 8, 'agt': 8, 'agu': 8, 'aug': 8, 'august': 8,
    'september': 9, 'sep': 9, 'sept': 9,
    'oktober': 10, 'okt': 10, 'oct': 10, 'october': 10,
    'november': 11, 'nov': 11,
    'desember': 12, 'des': 12, 'dec': 12, 'december': 12,
  };

  static const List<String> _monthNamesShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'
  ];

  static const List<String> _monthNamesFull = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  /// Format raw chapter date according to preference.
  static String? format(String? raw, {String? mode}) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    final formatMode = mode ?? LocalStorage.getChapterDateFormat();
    if (formatMode == 'hidden') return null;

    final dateTime = parse(text);
    if (dateTime == null) {
      return _cleanUpRawString(text);
    }

    final now = DateTime.now();
    final diff = now.difference(dateTime);

    switch (formatMode) {
      case 'relative':
        return _formatAlwaysRelative(diff, dateTime);
      case 'absolute':
        return _formatAlwaysAbsolute(dateTime);
      case 'relative_smart':
      default:
        return _formatKotatsuSmart(diff, dateTime, now);
    }
  }

  /// Kotatsu-Redo default behavior:
  /// Relative for recent dates (< 7 days), compact calendar date without year
  /// if current year ("15 Okt"), or with year if previous year ("15 Okt 2023").
  static String _formatKotatsuSmart(Duration diff, DateTime date, DateTime now) {
    if (diff.isNegative) return 'Baru saja';

    if (diff.inSeconds < 60) {
      return 'Baru saja';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} menit lalu';
    } else if (diff.inHours < 24) {
      if (date.day == now.day && date.month == now.month && date.year == now.year) {
        return '${diff.inHours} jam lalu';
      }
      return 'Kemarin';
    }

    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(date.year, date.month, date.day);
    final daysDiff = today.difference(targetDay).inDays;

    if (daysDiff == 1) {
      return 'Kemarin';
    } else if (daysDiff > 1 && daysDiff < 7) {
      return '$daysDiff hari lalu';
    }

    // Older than 7 days: calendar date including year (e.g. "23 Okt 2026")
    final m = _monthNamesShort[date.month - 1];
    return '${date.day} $m ${date.year}';
  }

  /// Always relative (e.g. "2 jam lalu", "3 hari lalu", "2 bulan lalu", "1 tahun lalu")
  static String _formatAlwaysRelative(Duration diff, DateTime date) {
    if (diff.isNegative || diff.inSeconds < 60) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays < 30) return '${diff.inDays} hari lalu';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} bulan lalu';
    return '${(diff.inDays / 365).floor()} tahun lalu';
  }

  /// Always absolute date (e.g. "15 Oktober 2024")
  static String _formatAlwaysAbsolute(DateTime date) {
    final m = _monthNamesFull[date.month - 1];
    return '${date.day} $m ${date.year}';
  }

  /// Parse any incoming date string into a DateTime
  static DateTime? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. Epoch timestamp (millis or seconds)
    final numeric = int.tryParse(trimmed);
    if (numeric != null) {
      if (numeric < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(numeric * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(numeric);
    }

    // 2. ISO 8601 parsing (e.g. "2024-05-12T04:22:11.000Z" or "2024-05-12")
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    final lower = trimmed.toLowerCase();

    // 3. Special relative keywords
    if (lower == 'baru saja' || lower == 'just now' || lower == 'right now') {
      return DateTime.now();
    }
    if (lower == 'hari ini' || lower == 'today') {
      return DateTime.now();
    }
    if (lower == 'kemarin' || lower == 'yesterday') {
      return DateTime.now().subtract(const Duration(days: 1));
    }

    // 4. Indonesian / English relative dates (e.g. "2 jam yang lalu", "3 days ago", "5m ago")
    final numMatch = RegExp(r'\d+').firstMatch(lower);
    if (numMatch != null) {
      final n = int.parse(numMatch.group(0)!);
      final now = DateTime.now();

      if (lower.contains('detik') || lower.contains('second') || lower.contains('sec')) {
        return now.subtract(Duration(seconds: n));
      }
      if (lower.contains('menit') || lower.contains('minute') || lower.contains('min') || lower.contains('mnt') || RegExp(r'\b\d+\s*m\b').hasMatch(lower)) {
        return now.subtract(Duration(minutes: n));
      }
      if (lower.contains('jam') || lower.contains('hour') || RegExp(r'\b\d+\s*h\b').hasMatch(lower)) {
        return now.subtract(Duration(hours: n));
      }
      if (lower.contains('hari') || lower.contains('day') || RegExp(r'\b\d+\s*d\b').hasMatch(lower)) {
        return now.subtract(Duration(days: n));
      }
      if (lower.contains('minggu') || lower.contains('week') || RegExp(r'\b\d+\s*w\b').hasMatch(lower)) {
        return now.subtract(Duration(days: n * 7));
      }
      if (lower.contains('bulan') || lower.contains('month') || RegExp(r'\b\d+\s*mo\b').hasMatch(lower)) {
        return now.subtract(Duration(days: n * 30));
      }
      if (lower.contains('tahun') || lower.contains('year') || RegExp(r'\b\d+\s*y\b').hasMatch(lower)) {
        return now.subtract(Duration(days: n * 365));
      }
    }

    // 5. Formatted date strings: "15/05/2024", "15-05-2024"
    final slashMatch = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{2,4})$').firstMatch(trimmed);
    if (slashMatch != null) {
      final p1 = int.parse(slashMatch.group(1)!);
      final p2 = int.parse(slashMatch.group(2)!);
      var year = int.parse(slashMatch.group(3)!);
      if (year < 100) year += 2000;
      final day = (p2 > 12) ? p2 : p1;
      final month = (p2 > 12) ? p1 : p2;
      return DateTime(year, month, day);
    }

    // 6. Named month: "15 Mei 2024", "Mei 15, 2024", "October 12, 2023", "10 Mar"
    for (final entry in _indonesianMonths.entries) {
      if (RegExp(r'\b' + RegExp.escape(entry.key) + r'\b').hasMatch(lower)) {
        final nums = RegExp(r'\d+').allMatches(trimmed).map((m) => int.parse(m.group(0)!)).toList();
        if (nums.isNotEmpty) {
          int? year = nums.firstWhere((n) => n >= 1000, orElse: () => -1);
          if (year == -1) {
            if (nums.length >= 2 && nums.last < 100) {
              year = nums.last + 2000;
            } else {
              year = DateTime.now().year;
            }
          }
          final remaining = nums.where((n) => n != year && n != (year! - 2000)).toList();
          final day = remaining.isNotEmpty ? remaining.first : 1;
          if (day >= 1 && day <= 31 && year >= 1990 && year <= 2100) {
            return DateTime(year, entry.value, day);
          }
        }
      }
    }

    return null;
  }

  static String _cleanUpRawString(String text) {
    return text.replaceAll(' yang lalu', ' lalu').trim();
  }
}
