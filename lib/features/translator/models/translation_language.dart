import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// Represents a supported language for Manga OCR and On-Device Translation.
class TranslationLanguage {
  final String code; // BCP-47 / internal code, e.g. 'auto', 'id', 'en', 'ja'
  final String displayName;
  final String nativeName;
  final TranslateLanguage? mlKitLanguage;
  final TextRecognitionScript ocrScript;
  final bool isAuto;

  const TranslationLanguage({
    required this.code,
    required this.displayName,
    required this.nativeName,
    this.mlKitLanguage,
    this.ocrScript = TextRecognitionScript.latin,
    this.isAuto = false,
  });

  /// The BCP-47 code used by ML Kit ModelManager (e.g. 'id', 'en', 'ja')
  String? get bcpCode => mlKitLanguage?.bcpCode;

  /// 'Auto Detect' pseudo-language for source language selection
  static const auto = TranslationLanguage(
    code: 'auto',
    displayName: 'Auto Detect (Deteksi Otomatis)',
    nativeName: 'Auto Detect',
    isAuto: true,
  );

  /// Supported primary languages requested for Manga Reader (Indonesian & English only)
  static const List<TranslationLanguage> supportedLanguages = [
    TranslationLanguage(
      code: 'id',
      displayName: 'Indonesia',
      nativeName: 'Bahasa Indonesia',
      mlKitLanguage: TranslateLanguage.indonesian,
      ocrScript: TextRecognitionScript.latin,
    ),
    TranslationLanguage(
      code: 'en',
      displayName: 'English',
      nativeName: 'English',
      mlKitLanguage: TranslateLanguage.english,
      ocrScript: TextRecognitionScript.latin,
    ),
  ];

  /// Find language by code, with fallback to Indonesian
  static TranslationLanguage fromCode(String code) {
    if (code == 'auto') return auto;
    for (final lang in supportedLanguages) {
      if (lang.code.toLowerCase() == code.toLowerCase()) {
        return lang;
      }
    }
    // Check if matched by bcpCode
    for (final lang in supportedLanguages) {
      if (lang.bcpCode?.toLowerCase() == code.toLowerCase()) {
        return lang;
      }
    }
    return supportedLanguages.first; // Default Indonesian
  }

  /// Supported source languages (includes Auto Detect)
  static List<TranslationLanguage> get sourceLanguages => [auto, ...supportedLanguages];

  /// Supported target languages (excludes Auto Detect)
  static List<TranslationLanguage> get targetLanguages => supportedLanguages;
}
