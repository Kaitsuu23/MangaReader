import 'package:flutter/material.dart';

/// Represents a single translated text bubble / block within a manga page.
class TranslatedBlock {
  final Rect boundingBox;
  final String originalText;
  final String translatedText;
  final Color textColor;
  final Color bgColor;
  final double confidence;

  const TranslatedBlock({
    required this.boundingBox,
    required this.originalText,
    required this.translatedText,
    this.textColor = Colors.black,
    this.bgColor = Colors.white,
    this.confidence = 1.0,
  });

  TranslatedBlock copyWith({
    Rect? boundingBox,
    String? originalText,
    String? translatedText,
    Color? textColor,
    Color? bgColor,
    double? confidence,
  }) {
    return TranslatedBlock(
      boundingBox: boundingBox ?? this.boundingBox,
      originalText: originalText ?? this.originalText,
      translatedText: translatedText ?? this.translatedText,
      textColor: textColor ?? this.textColor,
      bgColor: bgColor ?? this.bgColor,
      confidence: confidence ?? this.confidence,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'box': [
        boundingBox.left,
        boundingBox.top,
        boundingBox.width,
        boundingBox.height,
      ],
      'original': originalText,
      'translated': translatedText,
      'textColor': textColor.toARGB32(),
      'bgColor': bgColor.toARGB32(),
      'confidence': confidence,
    };
  }

  factory TranslatedBlock.fromJson(Map<String, dynamic> json) {
    final boxList = (json['box'] as List<dynamic>?)?.cast<num>() ?? [0, 0, 0, 0];
    return TranslatedBlock(
      boundingBox: Rect.fromLTWH(
        boxList[0].toDouble(),
        boxList[1].toDouble(),
        boxList[2].toDouble(),
        boxList[3].toDouble(),
      ),
      originalText: json['original'] as String? ?? '',
      translatedText: json['translated'] as String? ?? '',
      textColor: Color(json['textColor'] as int? ?? 0xFF000000),
      bgColor: Color(json['bgColor'] as int? ?? 0xFFFFFFFF),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
