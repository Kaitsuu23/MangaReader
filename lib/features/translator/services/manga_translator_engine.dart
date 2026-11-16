import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/page_translation_result.dart';
import '../models/translated_block.dart';
import '../models/translation_language.dart';
import 'manga_inpainting_service.dart';
import 'manga_ocr_service.dart';
import 'manga_translation_service.dart';
import 'translation_cache_service.dart';

/// Master translation engine coordinating OCR, language detection, translation, and inpainting.
class MangaTranslatorEngine {
  static final TranslationCacheService _cacheService = TranslationCacheService.instance;

  /// Process and translate a single manga page image.
  static Future<PageTranslationResult> processPage({
    required File imageFile,
    required String pageKey,
    required TranslationLanguage sourceLanguage,
    required TranslationLanguage targetLanguage,
    bool bypassCache = false,
  }) async {
    // 1. Check disk cache first unless explicitly bypassed
    if (!bypassCache) {
      final cached = await _cacheService.get(
        pageKey,
        sourceLang: sourceLanguage.code,
        targetLang: targetLanguage.code,
      );
      if (cached != null) {
        return cached;
      }
    }

    // 2. Decode image metadata for accurate coordinate scaling
    Size imageSize = const Size(1000, 1400);
    try {
      final bytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      imageSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      codec.dispose();
    } catch (_) {
      try {
        final bytes = await imageFile.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
        }
      } catch (_) {}
    }

    // 3. OCR Text Detection
    final ocrBlocks = await MangaOcrService.recognizeText(
      imageFile,
      language: sourceLanguage,
    );

    if (ocrBlocks.isEmpty) {
      final emptyResult = PageTranslationResult(
        pageKey: pageKey,
        blocks: [],
        originalImageSize: imageSize,
        sourceLangCode: sourceLanguage.code,
        targetLangCode: targetLanguage.code,
        timestamp: DateTime.now(),
      );
      await _cacheService.save(emptyResult);
      return emptyResult;
    }

    // 4. Resolve source language if 'auto'
    TranslationLanguage resolvedSource = sourceLanguage;
    if (sourceLanguage.isAuto) {
      // Aggregate all texts on the page for high-confidence language identification
      final allText = ocrBlocks.map((b) => b.text).join(' ');
      final detectedCode = await MangaTranslationService.identifyLanguage(allText);
      resolvedSource = TranslationLanguage.fromCode(detectedCode);
    }

    // 5. Batch Translate all detected blocks
    final originalTexts = ocrBlocks.map((b) => b.text).toList();
    final translatedTexts = await MangaTranslationService.translateBatch(
      texts: originalTexts,
      sourceLanguage: resolvedSource,
      targetLanguage: targetLanguage,
    );

    // 6. Inpainting background color sampling
    final boundingBoxes = ocrBlocks.map((b) => b.boundingBox).toList();
    final bubbleStyles = await MangaInpaintingService.batchAnalyzeBubbleColors(
      imageFile,
      boundingBoxes,
    );

    // 7. Assemble final translated blocks
    final translatedBlocks = <TranslatedBlock>[];
    for (int i = 0; i < ocrBlocks.length; i++) {
      final ocr = ocrBlocks[i];
      final trans = (i < translatedTexts.length) ? translatedTexts[i] : ocr.text;
      final style = (i < bubbleStyles.length)
          ? bubbleStyles[i]
          : const InpaintedBubbleStyle(bgColor: Colors.white, textColor: Colors.black);

      translatedBlocks.add(
        TranslatedBlock(
          boundingBox: ocr.boundingBox,
          originalText: ocr.text,
          translatedText: trans,
          textColor: style.textColor,
          bgColor: style.bgColor,
        ),
      );
    }

    final result = PageTranslationResult(
      pageKey: pageKey,
      blocks: translatedBlocks,
      originalImageSize: imageSize,
      sourceLangCode: resolvedSource.code,
      targetLangCode: targetLanguage.code,
      timestamp: DateTime.now(),
    );

    // 8. Cache result
    await _cacheService.save(result);

    return result;
  }
}
