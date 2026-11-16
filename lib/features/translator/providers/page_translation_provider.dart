import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/page_translation_result.dart';
import '../models/translation_language.dart';
import '../services/manga_translator_engine.dart';

class TranslationPageRequest {
  final File imageFile;
  final String pageKey;
  final TranslationLanguage sourceLanguage;
  final TranslationLanguage targetLanguage;
  final bool bypassCache;

  const TranslationPageRequest({
    required this.imageFile,
    required this.pageKey,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.bypassCache = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationPageRequest &&
          runtimeType == other.runtimeType &&
          pageKey == other.pageKey &&
          sourceLanguage.code == other.sourceLanguage.code &&
          targetLanguage.code == other.targetLanguage.code &&
          bypassCache == other.bypassCache;

  @override
  int get hashCode => Object.hash(pageKey, sourceLanguage.code, targetLanguage.code, bypassCache);
}

/// FutureProvider family that translates a page image.
final pageTranslationProvider =
    FutureProvider.family<PageTranslationResult, TranslationPageRequest>((ref, request) async {
  return await MangaTranslatorEngine.processPage(
    imageFile: request.imageFile,
    pageKey: request.pageKey,
    sourceLanguage: request.sourceLanguage,
    targetLanguage: request.targetLanguage,
    bypassCache: request.bypassCache,
  );
});
