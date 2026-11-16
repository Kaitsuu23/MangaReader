import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/local_storage.dart';
import '../models/translation_language.dart';
import '../services/manga_translation_service.dart';

// ── Auto Translate Toggle ──────────────────────────────────────────────────

final autoTranslateEnabledProvider =
    NotifierProvider<AutoTranslateEnabledNotifier, bool>(AutoTranslateEnabledNotifier.new);

class AutoTranslateEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => LocalStorage.isAutoTranslateEnabled();

  void toggle() {
    final next = !state;
    LocalStorage.setAutoTranslateEnabled(next);
    state = next;
  }

  void setEnabled(bool enabled) {
    LocalStorage.setAutoTranslateEnabled(enabled);
    state = enabled;
  }
}

// ── Source Language ────────────────────────────────────────────────────────

final sourceLanguageProvider =
    NotifierProvider<SourceLanguageNotifier, TranslationLanguage>(SourceLanguageNotifier.new);

class SourceLanguageNotifier extends Notifier<TranslationLanguage> {
  @override
  TranslationLanguage build() {
    final code = LocalStorage.getTranslatorSourceLang();
    return TranslationLanguage.fromCode(code);
  }

  void setLanguage(TranslationLanguage lang) {
    LocalStorage.setTranslatorSourceLang(lang.code);
    state = lang;
  }
}

// ── Target Language ────────────────────────────────────────────────────────

final targetLanguageProvider =
    NotifierProvider<TargetLanguageNotifier, TranslationLanguage>(TargetLanguageNotifier.new);

class TargetLanguageNotifier extends Notifier<TranslationLanguage> {
  @override
  TranslationLanguage build() {
    final code = LocalStorage.getTranslatorTargetLang();
    return TranslationLanguage.fromCode(code);
  }

  void setLanguage(TranslationLanguage lang) {
    LocalStorage.setTranslatorTargetLang(lang.code);
    state = lang;
  }
}

// ── Translation Mode ('translated' vs 'original') ──────────────────────────

final translationModeProvider =
    NotifierProvider<TranslationModeNotifier, String>(TranslationModeNotifier.new);

class TranslationModeNotifier extends Notifier<String> {
  @override
  String build() => LocalStorage.getTranslatorMode();

  void setMode(String mode) {
    LocalStorage.setTranslatorMode(mode);
    state = mode;
  }

  void toggle() {
    final next = state == 'translated' ? 'original' : 'translated';
    LocalStorage.setTranslatorMode(next);
    state = next;
  }
}

// ── Speech Bubble Inpainting ───────────────────────────────────────────────

final bubbleInpaintEnabledProvider =
    NotifierProvider<BubbleInpaintNotifier, bool>(BubbleInpaintNotifier.new);

class BubbleInpaintNotifier extends Notifier<bool> {
  @override
  bool build() => LocalStorage.isTranslatorBubbleInpaintEnabled();

  void toggle() {
    final next = !state;
    LocalStorage.setTranslatorBubbleInpaintEnabled(next);
    state = next;
  }
}

// ── Peek Original (Temporary Hold-To-View) ─────────────────────────────────

final peekOriginalActiveProvider =
    NotifierProvider<PeekOriginalNotifier, bool>(PeekOriginalNotifier.new);

class PeekOriginalNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setPeeking(bool peeking) {
    state = peeking;
  }
}

// ── Downloaded Models Manager ──────────────────────────────────────────────

final downloadedModelsProvider =
    NotifierProvider<DownloadedModelsNotifier, Map<String, bool>>(DownloadedModelsNotifier.new);

class DownloadedModelsNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() {
    _initCheck();
    return {};
  }

  Future<void> _initCheck() async {
    final statusMap = <String, bool>{};
    for (final lang in TranslationLanguage.supportedLanguages) {
      final bcp = lang.bcpCode;
      if (bcp != null) {
        statusMap[bcp] = await MangaTranslationService.isModelDownloaded(bcp);
      }
    }
    state = statusMap;
  }

  Future<void> refresh() => _initCheck();

  Future<bool> download(String bcpCode) async {
    final success = await MangaTranslationService.downloadModel(bcpCode);
    if (success) {
      state = {...state, bcpCode: true};
    }
    return success;
  }

  Future<bool> delete(String bcpCode) async {
    final success = await MangaTranslationService.deleteModel(bcpCode);
    if (success) {
      state = {...state, bcpCode: false};
    }
    return success;
  }
}

// ── Translation Engine ('groq' vs 'mlkit') ─────────────────────────────────

final translatorEngineProvider =
    NotifierProvider<TranslatorEngineNotifier, String>(TranslatorEngineNotifier.new);

class TranslatorEngineNotifier extends Notifier<String> {
  @override
  String build() => LocalStorage.getTranslatorEngine();

  void setEngine(String engine) {
    LocalStorage.setTranslatorEngine(engine);
    state = engine;
  }
}

// ── Groq API Key ───────────────────────────────────────────────────────────

final groqApiKeyProvider =
    NotifierProvider<GroqApiKeyNotifier, String>(GroqApiKeyNotifier.new);

class GroqApiKeyNotifier extends Notifier<String> {
  @override
  String build() => LocalStorage.getGroqApiKey();

  void setApiKey(String key) {
    LocalStorage.setGroqApiKey(key);
    state = key;
  }
}

// ── Groq Model Selection ───────────────────────────────────────────────────

final groqModelProvider =
    NotifierProvider<GroqModelNotifier, String>(GroqModelNotifier.new);

class GroqModelNotifier extends Notifier<String> {
  @override
  String build() => LocalStorage.getGroqModel();

  void setModel(String model) {
    LocalStorage.setGroqModel(model);
    state = model;
  }
}
