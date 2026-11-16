import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum ReaderModeIconKind { ltr, rtl, vertical, webtoon }

class ReaderModeIcon extends StatelessWidget {
  final ReaderModeIconKind kind;
  final Color color;
  final double size;

  const ReaderModeIcon({
    super.key,
    required this.kind,
    required this.color,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svgFor(kind),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  String _svgFor(ReaderModeIconKind kind) {
    switch (kind) {
      case ReaderModeIconKind.ltr:
        return _ltr;
      case ReaderModeIconKind.rtl:
        return _rtl;
      case ReaderModeIconKind.vertical:
        return _vertical;
      case ReaderModeIconKind.webtoon:
        return _webtoon;
    }
  }
}

/// Kotatsu `ic_reader_ltr.xml`
const _ltr = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="black" fill-rule="evenodd" d="m18,2c1.11,0 2,0.9 2,2v16c0,1.11 -0.89,2 -2,2L6,22C4.89,22 4,21.11 4,20L4,4C4,2.9 4.89,2 6,2ZM18,4L6,4v3.844h-0.002v8.229L6,16.072L6,20L18,20L18,16.072 18,16 18,8 18,7.844Z"/>
  <path fill="black" d="M17.009,8l-4,0l-0,8l4,0z"/>
</svg>
''';

/// Kotatsu `ic_reader_rtl.xml`
const _rtl = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="black" fill-rule="evenodd" d="M6,2C4.89,2 4,2.9 4,4L4,20C4,21.11 4.89,22 6,22L18,22C19.11,22 20,21.11 20,20L20,4C20,2.9 19.11,2 18,2L6,2zM6,4L18,4L18,7.844L18.002,7.844L18.002,16.072L18,16.072L18,20L6,20L6,16.072L6,16L6,8L6,7.844L6,4z"/>
  <path fill="black" d="M6.991,8h4v8h-4z"/>
</svg>
''';

/// Kotatsu `ic_reader_vertical.xml`: filled middle band, open top and bottom.
const _vertical = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="black" fill-rule="evenodd" d="M18 2H6C4.89 2 4 2.9 4 4V20C4 21.11 4.89 22 6 22H18C19.11 22 20 21.11 20 20V4C20 2.9 19.11 2 18 2M18 20H6V16H18V20M18 8H6V4H18V8Z"/>
</svg>
''';

/// Kotatsu `ic_script.xml` (MDI script-text) with even-odd so the 3 lines cut through.
const _webtoon = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="black" fill-rule="evenodd" d="M15 20a1 1 0 0 0 1-1V4H8a1 1 0 0 0-1 1v11H5V5a3 3 0 0 1 3-3h11a3 3 0 0 1 3 3v1h-2V5a1 1 0 0 0-1-1 1 1 0 0 0-1 1v14a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3v-1h11a2 2 0 0 0 2 2M9 6h5v2H9V6m0 4h5v2H9v-2m0 4h5v2H9v-2z"/>
</svg>
''';
