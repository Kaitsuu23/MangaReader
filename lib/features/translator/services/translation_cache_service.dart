import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/page_translation_result.dart';

/// Disk caching service for translated manga pages.
/// Avoids repeated OCR and translation execution on revisited pages.
class TranslationCacheService {
  static TranslationCacheService? _instance;
  static TranslationCacheService get instance => _instance ??= TranslationCacheService._();

  TranslationCacheService._();

  Directory? _cacheDir;

  Future<Directory> _getCacheDirectory() async {
    if (_cacheDir != null && _cacheDir!.existsSync()) {
      return _cacheDir!;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/manga_translations');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  String _generateFileName(String pageKey, String sourceLang, String targetLang) {
    final raw = '${pageKey}_${sourceLang}_$targetLang';
    final safeKey = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final hash = raw.hashCode.abs().toString();
    return 'trans_v6_${safeKey}_$hash.json';
  }

  /// Retrieve cached translation result if available
  Future<PageTranslationResult?> get(
    String pageKey, {
    required String sourceLang,
    required String targetLang,
  }) async {
    try {
      final dir = await _getCacheDirectory();
      final file = File('${dir.path}/${_generateFileName(pageKey, sourceLang, targetLang)}');
      if (!await file.exists()) return null;

      final contents = await file.readAsString();
      if (contents.isEmpty) return null;

      final data = jsonDecode(contents) as Map<String, dynamic>;
      return PageTranslationResult.fromJson(data);
    } catch (e) {
      debugPrint('[TranslationCacheService] Read error for $pageKey: $e');
      return null;
    }
  }

  /// Save translation result to disk cache
  Future<void> save(PageTranslationResult result) async {
    try {
      final dir = await _getCacheDirectory();
      final file = File(
        '${dir.path}/${_generateFileName(result.pageKey, result.sourceLangCode, result.targetLangCode)}',
      );
      final jsonStr = jsonEncode(result.toJson());
      await file.writeAsString(jsonStr, flush: true);
    } catch (e) {
      debugPrint('[TranslationCacheService] Save error for ${result.pageKey}: $e');
    }
  }

  /// Clear all cached translation files
  Future<void> clearAll() async {
    try {
      final dir = await _getCacheDirectory();
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('[TranslationCacheService] Clear error: $e');
    }
  }

  /// Get total cache size in bytes
  Future<int> getCacheSizeBytes() async {
    try {
      final dir = await _getCacheDirectory();
      if (!dir.existsSync()) return 0;
      var total = 0;
      await for (final file in dir.list(recursive: false, followLinks: false)) {
        if (file is File) {
          total += await file.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
