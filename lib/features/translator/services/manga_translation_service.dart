import 'package:flutter/foundation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import '../../../core/storage/local_storage.dart';
import '../models/translation_language.dart';
import 'groq_translation_service.dart';

/// Service managing Google ML Kit On-Device Translation & Language Identification.
/// Runs 100% locally on Android without external APIs or internet access once models are downloaded.
class MangaTranslationService {
  static final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();
  static LanguageIdentifier? _languageIdentifier;
  static final Map<String, OnDeviceTranslator> _translators = {};

  static LanguageIdentifier _getLanguageIdentifier() {
    return _languageIdentifier ??= LanguageIdentifier(confidenceThreshold: 0.4);
  }

  // ── Language Model Management ──────────────────────────────────────────────

  /// Check whether the translation model for the given BCP-47 language code is downloaded.
  static Future<bool> isModelDownloaded(String bcpCode) async {
    try {
      return await _modelManager.isModelDownloaded(bcpCode);
    } catch (e) {
      debugPrint('[TranslationModel] Check failed for $bcpCode: $e');
      return false;
    }
  }

  /// Download a language model for offline use.
  static Future<bool> downloadModel(String bcpCode, {bool isWifiRequired = false}) async {
    try {
      return await _modelManager.downloadModel(bcpCode, isWifiRequired: isWifiRequired);
    } catch (e) {
      debugPrint('[TranslationModel] Download failed for $bcpCode: $e');
      return false;
    }
  }

  /// Delete a downloaded language model to free up storage space (~30MB per model).
  static Future<bool> deleteModel(String bcpCode) async {
    try {
      // Invalidate any active translator using this language
      _translators.removeWhere((key, translator) {
        if (key.startsWith('${bcpCode}_') || key.endsWith('_$bcpCode')) {
          translator.close();
          return true;
        }
        return false;
      });
      return await _modelManager.deleteModel(bcpCode);
    } catch (e) {
      debugPrint('[TranslationModel] Delete failed for $bcpCode: $e');
      return false;
    }
  }

  // ── Language Identification (Auto Detect) ──────────────────────────────────

  /// Identify language of the given text using ML Kit on-device language identifier.
  static Future<String> identifyLanguage(String text) async {
    if (text.trim().isEmpty) return 'en';

    // Heuristics: Check Japanese Kana/Kanji regex
    if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(text)) {
      return 'ja';
    }
    // Check Korean Hangul
    if (RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF]').hasMatch(text)) {
      return 'ko';
    }
    // Check Chinese characters
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(text)) {
      return 'zh';
    }

    try {
      final identifier = _getLanguageIdentifier();
      final langCode = await identifier.identifyLanguage(text);
      if (langCode != 'und' && langCode.isNotEmpty) {
        return langCode;
      }
    } catch (e) {
      debugPrint('[LanguageId] Error identifying text: $e');
    }

    return 'en';
  }

  // ── Translation Execution ──────────────────────────────────────────────────

  /// Get or create an on-device translator for the specific language pair.
  static OnDeviceTranslator _getTranslator(
    TranslateLanguage source,
    TranslateLanguage target,
  ) {
    final key = '${source.bcpCode}_${target.bcpCode}';
    return _translators.putIfAbsent(
      key,
      () => OnDeviceTranslator(
        sourceLanguage: source,
        targetLanguage: target,
      ),
    );
  }

  /// Translate a string of text from source to target language.
  static Future<String> translateText({
    required String text,
    required TranslationLanguage sourceLanguage,
    required TranslationLanguage targetLanguage,
  }) async {
    if (text.trim().isEmpty) return text;

    // Resolve source language if auto-detect is enabled
    TranslationLanguage resolvedSource = sourceLanguage;
    if (sourceLanguage.isAuto) {
      final detectedBcp = await identifyLanguage(text);
      resolvedSource = TranslationLanguage.fromCode(detectedBcp);
    }

    // If source and target are identical, return original
    if (resolvedSource.code == targetLanguage.code ||
        resolvedSource.bcpCode == targetLanguage.bcpCode) {
      return text;
    }

    final sourceMlKit = resolvedSource.mlKitLanguage;
    final targetMlKit = targetLanguage.mlKitLanguage;

    if (sourceMlKit == null || targetMlKit == null) {
      return text;
    }

    try {
      final translator = _getTranslator(sourceMlKit, targetMlKit);
      final translated = await translator.translateText(text);
      return translated.trim();
    } catch (e) {
      debugPrint('[Translation] Translation error: $e');
      return text;
    }
  }

  /// Batch translate multiple texts.
  /// Uses Groq AI if enabled in settings, with automatic seamless fallback to Google ML Kit offline.
  static Future<List<String>> translateBatch({
    required List<String> texts,
    required TranslationLanguage sourceLanguage,
    required TranslationLanguage targetLanguage,
  }) async {
    if (texts.isEmpty) return [];

    // 1. Check if Groq AI Engine is enabled
    final engine = LocalStorage.getTranslatorEngine();
    if (engine == 'groq') {
      final apiKey = LocalStorage.getGroqApiKey();
      if (apiKey.isNotEmpty) {
        try {
          final groqResults = await GroqTranslationService.translateBatch(
            texts: texts,
            targetLanguage: targetLanguage,
            apiKey: apiKey,
            model: LocalStorage.getGroqModel(),
          );
          if (groqResults.isNotEmpty) {
            return groqResults;
          }
        } catch (e) {
          debugPrint('[MangaTranslationService] Groq translation failed, falling back to ML Kit: $e');
        }
      }
    }

    // 2. Fallback to Google ML Kit On-Device Translation
    final results = <String>[];
    for (final t in texts) {
      final res = await translateText(
        text: t,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
      results.add(res);
    }
    return results;
  }

  /// Close all active translator instances
  static Future<void> dispose() async {
    for (final t in _translators.values) {
      await t.close();
    }
    _translators.clear();
    await _languageIdentifier?.close();
    _languageIdentifier = null;
  }
}
