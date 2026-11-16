import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/translation_language.dart';

/// Result of testing an individual Groq AI model.
class GroqModelTestResult {
  final String modelId;
  final bool isSuccess;
  final int latencyMs;
  final String? errorMessage;

  const GroqModelTestResult({
    required this.modelId,
    required this.isSuccess,
    required this.latencyMs,
    this.errorMessage,
  });
}

/// Service managing Groq AI API for fast and natural manga dialogue translations.
class GroqTranslationService {
  static const String defaultEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const String modelsEndpoint = 'https://api.groq.com/openai/v1/models';
  static const String defaultModel = 'openai/gpt-oss-120b';

  /// Default free chat models offered on Groq for manga translation
  static const List<String> fallbackCandidateModels = [
    'openai/gpt-oss-120b',
    'qwen/qwen3.8-27b',
    'openai/gpt-oss-20b',
    'allam-2-7b',
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'llama3-70b-8192',
    'llama3-8b-8192',
    'gemma2-9b-it',
    'mixtral-8x7b-32768',
  ];

  /// Translate a batch of manga dialogue strings using Groq AI.
  static Future<List<String>> translateBatch({
    required List<String> texts,
    required TranslationLanguage targetLanguage,
    required String apiKey,
    String? model,
  }) async {
    if (texts.isEmpty) return [];
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      throw Exception('Groq API Key is empty');
    }

    final selectedModel = (model != null && model.isNotEmpty) ? model : defaultModel;
    final targetLangName = targetLanguage.displayName;

    final systemPrompt =
        'You are an expert manga localizer and scanlator translating comic dialogues into natural $targetLangName.\n'
        'Guidelines:\n'
        '1. Natural Dialogue: Use expressive, colloquial manga scanlation Indonesian (aku/kamu, natural expressions, appropriate slang, emotion). Never sound like a literal machine translation.\n'
        '2. OCR Noise & Typo Healing: Inputs are OCR recognized from manga pages and may contain slight OCR errors or broken hyphens (e.g., "ILL" means "I\'LL", "100 SEX PARTNERS" means "100 pasangan seks", "CERE-MONY" means "CEREMONY"). Intelligently deduce intended manga dialogue and translate cleanly.\n'
        '3. Sound Effects: If an item is an untranslated sound effect or screaming noise that has no direct meaning, keep it brief or localize it naturally.\n'
        '4. Format: Return ONLY a valid JSON array of translated strings matching input array order and length exactly. Example: ["terjemahan 1", "terjemahan 2"]. Do not add Markdown backticks or commentary.';

    final payload = {
      'model': selectedModel,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': jsonEncode(texts)},
      ],
      'temperature': 0.1,
    };

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);

    try {
      final request = await client.postUrl(Uri.parse(defaultEndpoint));
      request.headers.set('Authorization', 'Bearer $cleanKey');
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('User-Agent', 'MangaReader/1.0');
      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        debugPrint('[GroqTranslationService] HTTP ${response.statusCode}: $body');
        throw Exception('Groq API error HTTP ${response.statusCode}');
      }

      final jsonResp = jsonDecode(body) as Map<String, dynamic>;
      final choices = jsonResp['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw Exception('Groq returned empty choices');
      }

      var content = choices[0]['message']['content'] as String? ?? '';
      content = content.trim();

      // Clean markdown code blocks if model wrapped it in ```json ... ```
      if (content.startsWith('```')) {
        content = content.replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: false), '');
        content = content.replaceAll(RegExp(r'\s*```$', multiLine: false), '');
        content = content.trim();
      }

      final decoded = jsonDecode(content);
      if (decoded is List) {
        final list = decoded.map((e) => e.toString().trim()).toList();
        if (list.length == texts.length) {
          return list;
        }
      }

      // If array count differs slightly, return decoded as list if non-empty
      if (decoded is List && decoded.isNotEmpty) {
        final list = decoded.map((e) => e.toString().trim()).toList();
        return list;
      }

      throw Exception('Failed to parse translated array from Groq');
    } finally {
      client.close();
    }
  }

  /// Dynamically fetch active chat models available on this API Key from Groq
  static Future<List<String>> fetchAvailableChatModels(String apiKey) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) return fallbackCandidateModels;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 6);

    try {
      final request = await client.getUrl(Uri.parse(modelsEndpoint));
      request.headers.set('Authorization', 'Bearer $cleanKey');
      request.headers.set('User-Agent', 'MangaReader/1.0');

      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final data = json['data'] as List<dynamic>? ?? [];

        final chatModels = <String>[];
        for (final item in data) {
          final id = item['id'] as String? ?? '';
          final active = item['active'] as bool? ?? true;
          if (!active || id.isEmpty) continue;

          // Filter out audio, whisper, and guardrail models
          final lower = id.toLowerCase();
          if (lower.contains('whisper') ||
              lower.contains('guard') ||
              lower.contains('orpheus') ||
              lower.contains('vision') ||
              lower.contains('embedding')) {
            continue;
          }
          chatModels.add(id);
        }

        if (chatModels.isNotEmpty) {
          return chatModels;
        }
      }
    } catch (e) {
      debugPrint('[GroqTranslationService] fetchAvailableChatModels failed: $e');
    } finally {
      client.close();
    }

    return fallbackCandidateModels;
  }

  /// Test a specific Groq model with the provided API key and calculate round-trip latency.
  static Future<GroqModelTestResult> testModel(String apiKey, String modelId) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      return GroqModelTestResult(
        modelId: modelId,
        isSuccess: false,
        latencyMs: 0,
        errorMessage: 'API Key kosong',
      );
    }

    final stopwatch = Stopwatch()..start();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final payload = {
        'model': modelId,
        'messages': [
          {'role': 'user', 'content': 'Halo'},
        ],
        'max_tokens': 10,
        'temperature': 0.1,
      };

      final request = await client.postUrl(Uri.parse(defaultEndpoint));
      request.headers.set('Authorization', 'Bearer $cleanKey');
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('User-Agent', 'MangaReader/1.0');
      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close();
      await response.drain();
      stopwatch.stop();

      if (response.statusCode == 200) {
        return GroqModelTestResult(
          modelId: modelId,
          isSuccess: true,
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      } else if (response.statusCode == 429) {
        return GroqModelTestResult(
          modelId: modelId,
          isSuccess: false,
          latencyMs: stopwatch.elapsedMilliseconds,
          errorMessage: 'Rate Limit (429)',
        );
      } else if (response.statusCode == 404) {
        return GroqModelTestResult(
          modelId: modelId,
          isSuccess: false,
          latencyMs: stopwatch.elapsedMilliseconds,
          errorMessage: 'Model tidak tersedia (404)',
        );
      } else {
        return GroqModelTestResult(
          modelId: modelId,
          isSuccess: false,
          latencyMs: stopwatch.elapsedMilliseconds,
          errorMessage: 'HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      stopwatch.stop();
      return GroqModelTestResult(
        modelId: modelId,
        isSuccess: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      client.close();
    }
  }

  /// Test connection to Groq API using the provided key and model.
  static Future<bool> testConnection(String apiKey, {String? model}) async {
    try {
      final res = await translateBatch(
        texts: ['Hello!'],
        targetLanguage: TranslationLanguage.fromCode('id'),
        apiKey: apiKey,
        model: model,
      );
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
