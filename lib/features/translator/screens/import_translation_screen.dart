import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/page_translation_result.dart';
import '../models/translation_language.dart';
import '../providers/translator_settings_provider.dart';
import '../services/manga_translator_engine.dart';
import '../widgets/translated_page_overlay.dart';
import '../widgets/translation_model_manager_dialog.dart';

/// Screen allowing users to import any manga image from gallery or storage,
/// translate it offline, zoom/pan, toggle original/translated, and copy text.
class ImportTranslationScreen extends ConsumerStatefulWidget {
  const ImportTranslationScreen({super.key});

  @override
  ConsumerState<ImportTranslationScreen> createState() => _ImportTranslationScreenState();
}

class _ImportTranslationScreenState extends ConsumerState<ImportTranslationScreen> {
  File? _selectedFile;
  bool _isProcessing = false;
  PageTranslationResult? _translationResult;
  bool _showOriginal = false;

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        _setFile(File(picked.path));
      }
    } catch (e) {
      debugPrint('[ImportTranslation] Pick gallery error: $e');
    }
  }

  Future<void> _pickFromFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (result.isNotEmpty && result.first.path != null) {
        _setFile(File(result.first.path!));
      }
    } catch (e) {
      debugPrint('[ImportTranslation] Pick file error: $e');
    }
  }

  void _setFile(File file) {
    setState(() {
      _selectedFile = file;
      _translationResult = null;
      _showOriginal = false;
    });
    _translateImage();
  }

  Future<void> _translateImage() async {
    if (_selectedFile == null) return;

    final sourceLang = ref.read(sourceLanguageProvider);
    final targetLang = ref.read(targetLanguageProvider);

    setState(() => _isProcessing = true);

    try {
      final result = await MangaTranslatorEngine.processPage(
        imageFile: _selectedFile!,
        pageKey: 'imported_${_selectedFile!.path.hashCode}',
        sourceLanguage: sourceLang,
        targetLanguage: targetLang,
        bypassCache: true, // Always re-run or fresh on manual import
      );

      if (mounted) {
        setState(() {
          _translationResult = result;
          _isProcessing = false;
        });

        if (result.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak ada teks manga yang terdeteksi pada gambar ini.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menerjemahkan: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceLang = ref.watch(sourceLanguageProvider);
    final targetLang = ref.watch(targetLanguageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terjemahkan Gambar Manga'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: 'Model Offline',
            onPressed: () => TranslationModelManagerDialog.show(context),
          ),
          if (_selectedFile != null)
            IconButton(
              icon: Icon(_showOriginal ? Icons.translate_rounded : Icons.menu_book_rounded),
              tooltip: _showOriginal ? 'Tampilkan Terjemahan' : 'Tampilkan Asli',
              onPressed: () => setState(() => _showOriginal = !_showOriginal),
            ),
        ],
      ),
      body: Column(
        children: [
          // Header Language Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: sourceLang.code,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                    items: TranslationLanguage.sourceLanguages.map((l) {
                      return DropdownMenuItem(value: l.code, child: Text(l.displayName));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        ref
                            .read(sourceLanguageProvider.notifier)
                            .setLanguage(TranslationLanguage.fromCode(val));
                        _translateImage();
                      }
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                ),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: targetLang.code,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                    items: TranslationLanguage.targetLanguages.map((l) {
                      return DropdownMenuItem(value: l.code, child: Text(l.displayName));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        ref
                            .read(targetLanguageProvider.notifier)
                            .setLanguage(TranslationLanguage.fromCode(val));
                        _translateImage();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // Main View
          Expanded(
            child: _selectedFile == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 64,
                            color: theme.colorScheme.primary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Pilih gambar manga untuk diterjemahkan',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Teks bahasa Jepang, Korea, Mandarin, atau Inggris akan otomatis diterjemahkan ke Bahasa Indonesia secara offline.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _pickFromGallery,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Buka Galeri'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: _pickFromFile,
                                icon: const Icon(Icons.folder_open_outlined),
                                label: const Text('Pilih File'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 5.0,
                        child: Center(
                          child: _showOriginal || _translationResult == null
                              ? Image.file(_selectedFile!)
                              : TranslatedPageOverlay(
                                  imageFile: _selectedFile!,
                                  pageKey: 'imported_${_selectedFile!.path.hashCode}',
                                  child: Image.file(_selectedFile!),
                                ),
                        ),
                      ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 12),
                                Text(
                                  'Mendeteksi dan menerjemahkan teks...',
                                  style: TextStyle(color: Colors.white, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _selectedFile != null
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
                ),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                      label: const Text('Ganti Gambar'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _isProcessing ? null : _translateImage,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Terjemahkan Ulang'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
