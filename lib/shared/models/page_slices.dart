/// Models describing a page that has been split into vertical slices by the
/// native `ImageSlicer` (see `MangaChannel.getPageSlices`).
library;

/// One vertical slice of a tall webtoon/manga page, already written to a local
/// cache file by the native slicer.
class PageSlice {
  final String path;
  final int width;
  final int height;

  const PageSlice({
    required this.path,
    required this.width,
    required this.height,
  });

  factory PageSlice.fromJson(Map<String, dynamic> json) => PageSlice(
        path: json['path'] as String? ?? '',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
      );
}

/// Result of slicing a page.
///
/// When [sliced] is `false` the whole image already fits inside a single GPU
/// texture and [slices] holds one file containing the original bytes (no
/// re-encode). When `true` the page was cut into several slices.
class PageSlices {
  final int width;
  final int height;
  final bool sliced;
  final List<PageSlice> slices;

  const PageSlices({
    required this.width,
    required this.height,
    required this.sliced,
    required this.slices,
  });

  factory PageSlices.fromJson(Map<String, dynamic> json) {
    final raw = json['slices'] as List? ?? [];
    return PageSlices(
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      sliced: json['sliced'] as bool? ?? false,
      slices: raw
          .map((s) => PageSlice.fromJson(Map<String, dynamic>.from(s as Map)))
          .where((s) => s.path.isNotEmpty && s.width > 0 && s.height > 0)
          .toList(),
    );
  }
}
