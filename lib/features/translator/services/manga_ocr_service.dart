import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/translation_language.dart';

/// Raw OCR detected text element before translation.
class OcrBlock {
  final Rect boundingBox;
  final String text;
  final List<String> lines;
  final List<Point<int>> cornerPoints;

  const OcrBlock({
    required this.boundingBox,
    required this.text,
    required this.lines,
    required this.cornerPoints,
  });
}

class _RawCandidateBlock {
  final Rect boundingBox;
  final List<String> lines;
  final List<Point<int>> cornerPoints;

  const _RawCandidateBlock({
    required this.boundingBox,
    required this.lines,
    required this.cornerPoints,
  });
}

/// Service handling Google ML Kit On-Device Text Recognition for manga.
/// Includes dialogue bubble clustering, OCR error normalization, de-hyphenation,
/// and automatic Sound Effects (SFX / onomatopoeia) filtering.
class MangaOcrService {
  static final Map<TextRecognitionScript, TextRecognizer> _recognizers = {};

  static TextRecognizer _getRecognizer(TextRecognitionScript script) {
    return _recognizers.putIfAbsent(script, () => TextRecognizer(script: script));
  }

  // ── SFX (Sound Effects) & Dialogue Filter Dictionaries ──────────────────────

  static final Set<String> _commonSfxWords = {
    'boom', 'bang', 'crash', 'clang', 'clank', 'click', 'clack', 'clap',
    'slash', 'smack', 'slap', 'snap', 'swoosh', 'whoosh', 'swish',
    'thud', 'thump', 'tap', 'tick', 'tock', 'wham', 'zap', 'pow', 'bam',
    'gasp', 'pant', 'sigh', 'sob', 'sniff', 'yawn', 'gulp', 'slurp',
    'munch', 'crunch', 'chew', 'rattle', 'rumble', 'creak', 'squeak',
    'screech', 'roar', 'rustle', 'flutter', 'flap', 'drip', 'drop',
    'splash', 'splat', 'buzz', 'beep', 'honk', 'ring', 'ding', 'dong',
    'glare', 'blush', 'twitch', 'shiver', 'tremble', 'step', 'dash',
    'skid', 'stomp', 'badump', 'doki', 'dokidoki', 'kyaa', 'gogogo', 'menacing',
    'shh', 'shhh', 'grr', 'grrr', 'brr', 'brrr', 'hmm', 'hmmm', 'pff', 'pfff',
    'tch', 'tsk', 'ugh', 'argh', 'gah', 'woah', 'whoa', 'ouch'
  };

  static final Set<String> _dialogueWhitelist = {
    'yes', 'no', 'wait', 'stop', 'help', 'look', 'listen', 'why', 'what',
    'who', 'how', 'when', 'where', 'please', 'thanks', 'sorry', 'hello',
    'hi', 'bye', 'ok', 'okay', 'sure', 'yeah', 'yep', 'nope', 'never',
    'always', 'maybe', 'hey', 'ah', 'oh', 'um', 'uh', 'well'
  };

  /// Check whether a detected text element represents an untranslated sound effect (SFX)
  static bool _isSoundEffect(String text, {required bool isCJK}) {
    final t = text.trim();
    if (t.isEmpty) return true;

    // 1. Japanese Katakana/Hiragana on a translated English/Latin page is 100% SFX
    if (!isCJK && RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(t)) {
      return true;
    }

    // 2. Sentences with 3 or more words are dialogue, not isolated SFX
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length > 2) {
      return false;
    }

    // Strip trailing/leading punctuation
    final clean = t.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '').toLowerCase();
    if (clean.isEmpty) return true;

    // Whitelist check: Never filter common dialogue words
    if (_dialogueWhitelist.contains(clean)) {
      return false;
    }

    // Check against standard comic SFX dictionary
    if (_commonSfxWords.contains(clean)) {
      return true;
    }

    // Repeated laugh / scream onomatopoeia: e.g. "hahaha", "hehehe", "kyaaa", "fufufu"
    if (RegExp(r'^(ha|he|hu|fu|wa|ya|ga|ku|nya|hya){2,}!*$', caseSensitive: false).hasMatch(clean)) {
      return true;
    }

    // Repeated single letter: e.g. "aaaaa", "zzzzz", "eeee"
    if (RegExp(r'^([a-zA-Z])\1{2,}!*$').hasMatch(clean)) {
      return true;
    }

    // Consonant clusters with no vowels of length >= 2: e.g. "zzz", "grrr", "tch", "brrr"
    if (!RegExp(r'[aeiouyAEIOUY]').hasMatch(clean) && clean.length >= 2) {
      return true;
    }

    return false;
  }

  /// Recognize all text blocks inside an image file and merge blocks belonging to the same speech bubble.
  /// Automatically filters out sound effects (SFX) so only dialogue is translated.
  static Future<List<OcrBlock>> recognizeText(
    File imageFile, {
    TranslationLanguage? language,
  }) async {
    final script = language?.ocrScript ?? TextRecognitionScript.latin;
    final recognizer = _getRecognizer(script);

    final inputImage = InputImage.fromFile(imageFile);
    final recognizedText = await recognizer.processImage(inputImage);

    final isCJK = script == TextRecognitionScript.japanese ||
        script == TextRecognitionScript.chinese ||
        script == TextRecognitionScript.korean;

    final rawBlocks = <_RawCandidateBlock>[];

    // Iterate through individual text lines rather than blocks.
    // Google ML Kit's blocks frequently merge separate dialogue columns or adjacent panels together.
    // Operating at the line level allows our intelligent clustering to accurately isolate speech bubbles.
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;

        // Filter out single-symbol noise (stray dots, punctuation marks)
        if (text.length <= 1 && !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) {
          continue;
        }

        // Filter out Sound Effects (SFX / onomatopoeia)
        if (_isSoundEffect(text, isCJK: isCJK)) {
          continue;
        }

        rawBlocks.add(
          _RawCandidateBlock(
            boundingBox: line.boundingBox,
            lines: [text],
            cornerPoints: line.cornerPoints,
          ),
        );
      }
    }

    if (rawBlocks.isEmpty) return [];

    // Cluster blocks that belong to the same speech bubble
    final clusters = _clusterBlocks(rawBlocks, isCJK: isCJK);

    final result = <OcrBlock>[];

    for (final cluster in clusters) {
      if (cluster.isEmpty) continue;

      double left = double.infinity;
      double top = double.infinity;
      double right = -double.infinity;
      double bottom = -double.infinity;
      final allPoints = <Point<int>>[];

      for (final b in cluster) {
        left = min(left, b.boundingBox.left);
        top = min(top, b.boundingBox.top);
        right = max(right, b.boundingBox.right);
        bottom = max(bottom, b.boundingBox.bottom);
        allPoints.addAll(b.cornerPoints);
      }

      // Order blocks logically
      if (isCJK) {
        // Vertical reading in manga: right-to-left columns, top-to-bottom
        cluster.sort((a, b) {
          final dx = b.boundingBox.center.dx.compareTo(a.boundingBox.center.dx);
          if (dx != 0) return dx;
          return a.boundingBox.top.compareTo(b.boundingBox.top);
        });
      } else {
        // Horizontal reading: top-to-bottom
        cluster.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      }

      final sortedLines = <String>[];
      for (final b in cluster) {
        sortedLines.addAll(b.lines);
      }

      final cleanText = _cleanAndJoinLines(sortedLines, isCJK: isCJK);
      final normalizedText = isCJK ? cleanText : _normalizeMangaEnglishText(cleanText);
      if (normalizedText.trim().isEmpty) continue;

      // Final SFX check on the clustered result
      if (_isSoundEffect(normalizedText, isCJK: isCJK)) {
        continue;
      }

      result.add(
        OcrBlock(
          boundingBox: Rect.fromLTRB(left, top, right, bottom),
          text: normalizedText,
          lines: sortedLines,
          cornerPoints: allPoints,
        ),
      );
    }

    return result;
  }

  /// Removes word-splitting hyphens at line endings and joins lines cleanly.
  static String _cleanAndJoinLines(List<String> lines, {required bool isCJK}) {
    if (lines.isEmpty) return '';
    if (isCJK) {
      return lines.join('').replaceAll(RegExp(r'\s+'), '');
    }

    final buffer = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (buffer.isEmpty) {
        buffer.write(line);
      } else {
        final currentStr = buffer.toString().trimRight();
        // Check if previous line ended with a hyphen or dash (e.g. "TOMOR-", "CERTA -")
        if (RegExp(r'[-–—]\s*$').hasMatch(currentStr) &&
            line.isNotEmpty &&
            RegExp(r'^[a-zA-Z]').hasMatch(line)) {
          final withoutHyphen = currentStr.replaceAll(RegExp(r'[-–—]\s*$'), '');
          buffer.clear();
          buffer.write(withoutHyphen);
          buffer.write(line);
        } else {
          buffer.write(' ');
          buffer.write(line);
        }
      }
    }
    return buffer.toString().trim();
  }

  /// Fix common OCR misrecognitions in English manga (missing apostrophes in all-caps text).
  static String _normalizeMangaEnglishText(String text) {
    var s = text;

    // Normalize quotes and stylized apostrophes to standard ASCII apostrophe
    s = s.replaceAll(RegExp(r"[`'‘’]"), "'");
    s = s.replaceAll(RegExp(r'[“”]'), '"');

    // Fix missing apostrophe in "ILL" -> "I'LL" (prevents translating to "Sakit")
    s = s.replaceAll(RegExp(r'\bILL\b', caseSensitive: true), "I'LL");
    s = s.replaceAll(RegExp(r'\bIll\b'), "I'll");

    // Fix missing apostrophes in common English all-caps manga contractions
    s = s.replaceAll(RegExp(r'\bIM\b', caseSensitive: true), "I'M");
    s = s.replaceAll(RegExp(r'\bIm\b'), "I'm");
    s = s.replaceAll(RegExp(r'\bIVE\b', caseSensitive: false), "I'VE");
    s = s.replaceAll(RegExp(r'\bDONT\b', caseSensitive: false), "DON'T");
    s = s.replaceAll(RegExp(r'\bCANT\b', caseSensitive: false), "CAN'T");
    s = s.replaceAll(RegExp(r'\bWONT\b', caseSensitive: false), "WON'T");
    s = s.replaceAll(RegExp(r'\bDIDNT\b', caseSensitive: false), "DIDN'T");
    s = s.replaceAll(RegExp(r'\bDOESNT\b', caseSensitive: false), "DOESN'T");
    s = s.replaceAll(RegExp(r'\bISNT\b', caseSensitive: false), "ISN'T");
    s = s.replaceAll(RegExp(r'\bARENT\b', caseSensitive: false), "AREN'T");
    s = s.replaceAll(RegExp(r'\bWASN\b', caseSensitive: false), "WASN'T");
    s = s.replaceAll(RegExp(r'\bCOULDNT\b', caseSensitive: false), "COULDN'T");
    s = s.replaceAll(RegExp(r'\bWOULDNT\b', caseSensitive: false), "WOULDN'T");
    s = s.replaceAll(RegExp(r'\bSHOULDNT\b', caseSensitive: false), "SHOULDN'T");
    s = s.replaceAll(RegExp(r'\bYOU\s*RE\b', caseSensitive: false), "YOU'RE");
    s = s.replaceAll(RegExp(r'\bYOULL\b', caseSensitive: false), "YOU'LL");
    s = s.replaceAll(RegExp(r'\bYOUVE\b', caseSensitive: false), "YOU'VE");
    s = s.replaceAll(RegExp(r'\bTHEY\s*RE\b', caseSensitive: false), "THEY'RE");
    s = s.replaceAll(RegExp(r'\bTHEYLL\b', caseSensitive: false), "THEY'LL");
    s = s.replaceAll(RegExp(r'\bTHEYVE\b', caseSensitive: false), "THEY'VE");
    s = s.replaceAll(RegExp(r'\bWE\s*RE\b', caseSensitive: false), "WE'RE");
    s = s.replaceAll(RegExp(r'\bIT\s*S\b', caseSensitive: false), "IT'S");
    s = s.replaceAll(RegExp(r'\bTHAT\s*S\b', caseSensitive: false), "THAT'S");
    s = s.replaceAll(RegExp(r'\bWHAT\s*S\b', caseSensitive: false), "WHAT'S");
    s = s.replaceAll(RegExp(r'\bLET\s*S\b', caseSensitive: false), "LET'S");

    // Clean redundant spaces around punctuation
    s = s.replaceAll(RegExp(r'\s+([,.\?!])'), r'$1');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Groups nearby blocks that belong to the same dialogue bubble using connected components.
  static List<List<_RawCandidateBlock>> _clusterBlocks(
    List<_RawCandidateBlock> blocks, {
    required bool isCJK,
  }) {
    final n = blocks.length;
    final parent = List.generate(n, (i) => i);

    int find(int i) {
      if (parent[i] == i) return i;
      return parent[i] = find(parent[i]);
    }

    void union(int i, int j) {
      final rootI = find(i);
      final rootJ = find(j);
      if (rootI != rootJ) {
        parent[rootI] = rootJ;
      }
    }

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (_shouldMerge(blocks[i], blocks[j], isCJK: isCJK)) {
          union(i, j);
        }
      }
    }

    final groups = <int, List<_RawCandidateBlock>>{};
    for (int i = 0; i < n; i++) {
      final root = find(i);
      groups.putIfAbsent(root, () => []).add(blocks[i]);
    }

    return groups.values.toList();
  }

  static bool _shouldMerge(
    _RawCandidateBlock a,
    _RawCandidateBlock b, {
    required bool isCJK,
  }) {
    final boxA = a.boundingBox;
    final boxB = b.boundingBox;

    // 1. Box containment or heavy intersection
    final intersect = boxA.intersect(boxB);
    if (intersect.width > 0 && intersect.height > 0) {
      final intersectArea = intersect.width * intersect.height;
      final minArea = min(boxA.width * boxA.height, boxB.width * boxB.height);
      if (minArea > 0 && (intersectArea / minArea) > 0.35) {
        return true;
      }
    }

    // Line height estimate
    final lineHA = boxA.height / max(1, a.lines.length);
    final lineHB = boxB.height / max(1, b.lines.length);
    final avgLineH = max(12.0, (lineHA + lineHB) / 2);

    if (!isCJK) {
      // Horizontal text: Must have significant horizontal overlap to be in the same speech bubble
      final overlapX = min(boxA.right, boxB.right) - max(boxA.left, boxB.left);
      final minW = min(boxA.width, boxB.width);

      // Do NOT merge if there is no horizontal overlap (different columns / bubbles)
      if (overlapX <= 0 || (overlapX / minW) < 0.35) {
        return false;
      }

      // Check vertical proximity (one line directly under another in the bubble)
      final verticalGap = (boxA.top < boxB.top)
          ? (boxB.top - boxA.bottom)
          : (boxA.top - boxB.bottom);

      // Adjacent lines in speech bubble
      if (verticalGap <= avgLineH * 1.4) {
        return true;
      }
    } else {
      // Vertical Japanese/Chinese text: Check horizontal proximity (columns side-by-side)
      final overlapY = min(boxA.bottom, boxB.bottom) - max(boxA.top, boxB.top);
      final minH = min(boxA.height, boxB.height);

      if (overlapY <= 0 || (overlapY / minH) < 0.35) {
        return false;
      }

      final horizontalGap = (boxA.left < boxB.left)
          ? (boxB.left - boxA.right)
          : (boxA.left - boxB.right);

      final colWA = boxA.width / max(1, a.lines.length);
      final colWB = boxB.width / max(1, b.lines.length);
      final avgColW = max(12.0, (colWA + colWB) / 2);

      if (horizontalGap <= avgColW * 1.4) {
        return true;
      }
    }

    return false;
  }

  /// Close and dispose all active TextRecognizers
  static Future<void> dispose() async {
    for (final recognizer in _recognizers.values) {
      await recognizer.close();
    }
    _recognizers.clear();
  }
}
