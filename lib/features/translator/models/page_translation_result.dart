import 'package:flutter/material.dart';
import 'translated_block.dart';

/// Translation result for an entire manga page.
class PageTranslationResult {
  final String pageKey;
  final List<TranslatedBlock> blocks;
  final Size originalImageSize;
  final String sourceLangCode;
  final String targetLangCode;
  final DateTime timestamp;

  const PageTranslationResult({
    required this.pageKey,
    required this.blocks,
    required this.originalImageSize,
    required this.sourceLangCode,
    required this.targetLangCode,
    required this.timestamp,
  });

  bool get isEmpty => blocks.isEmpty;
  bool get isNotEmpty => blocks.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'pageKey': pageKey,
      'width': originalImageSize.width,
      'height': originalImageSize.height,
      'sourceLang': sourceLangCode,
      'targetLang': targetLangCode,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'blocks': blocks.map((b) => b.toJson()).toList(),
    };
  }

  factory PageTranslationResult.fromJson(Map<String, dynamic> json) {
    return PageTranslationResult(
      pageKey: json['pageKey'] as String? ?? '',
      originalImageSize: Size(
        (json['width'] as num?)?.toDouble() ?? 1000,
        (json['height'] as num?)?.toDouble() ?? 1400,
      ),
      sourceLangCode: json['sourceLang'] as String? ?? 'auto',
      targetLangCode: json['targetLang'] as String? ?? 'id',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map((e) => TranslatedBlock.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
