import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/translation_language.dart';
import '../providers/translator_settings_provider.dart';
import '../screens/import_translation_screen.dart';
import '../services/groq_translation_service.dart';
import 'groq_api_key_dialog.dart';
import 'translation_model_manager_dialog.dart';

/// Bottom sheet for Manga Translation preferences, engine selection (Groq AI vs ML Kit),
/// and language pairing.
class TranslationSettingsSheet extends ConsumerStatefulWidget {
  const TranslationSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const TranslationSettingsSheet(),
    );
  }

  @override
  ConsumerState<TranslationSettingsSheet> createState() => _TranslationSettingsSheetState();
}

class _TranslationSettingsSheetState extends ConsumerState<TranslationSettingsSheet> {
  late final TextEditingController _apiKeyController;
  bool _obscureKey = true;
  bool _isTestingConnection = false;
  String? _testConnectionResult;
  bool? _testConnectionSuccess;

  static const List<Map<String, String>> _availableGroqModels = [
    {
      'id': 'openai/gpt-oss-120b',
      'label': 'GPT-OSS 120B (Direkomendasikan - Alami & Cerdas)',
    },
    {
      'id': 'qwen/qwen3.8-27b',
      'label': 'Qwen 3.8 27B (Cepat & Responsif)',
    },
    {
      'id': 'openai/gpt-oss-20b',
      'label': 'GPT-OSS 20B (Ringan)',
    },
  ];

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: ref.read(groqApiKeyProvider));
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testGroqConnection() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testConnectionResult = 'API Key tidak boleh kosong';
        _testConnectionSuccess = false;
      });
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _testConnectionResult = null;
    });

    try {
      final model = ref.read(groqModelProvider);
      final ok = await GroqTranslationService.testConnection(key, model: model);
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
          _testConnectionSuccess = ok;
          _testConnectionResult = ok ? 'Koneksi Groq AI Berhasil! ✓' : 'Gagal terhubung ke Groq AI';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
          _testConnectionSuccess = false;
          _testConnectionResult = 'Gagal: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = ref.watch(autoTranslateEnabledProvider);
    final sourceLang = ref.watch(sourceLanguageProvider);
    final targetLang = ref.watch(targetLanguageProvider);
    final mode = ref.watch(translationModeProvider);
    final inpaintEnabled = ref.watch(bubbleInpaintEnabledProvider);
    final modelStatus = ref.watch(downloadedModelsProvider);
    final engine = ref.watch(translatorEngineProvider);
    final selectedGroqModel = ref.watch(groqModelProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Manga Auto Translator',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Switch(
                    value: isEnabled,
                    onChanged: (val) {
                      ref.read(autoTranslateEnabledProvider.notifier).setEnabled(val);
                    },
                  ),
                ],
              ),
              Text(
                'Terjemahkan teks balon manga otomatis menggunakan Groq AI (Cepat & Dialog Alami) atau Google ML Kit Offline.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 16),

              if (isEnabled) ...[
                // Engine Selector: Groq AI vs Google ML Kit
                const Text(
                  'Engine Terjemahan',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  expandedInsets: EdgeInsets.zero,
                  segments: const [
                    ButtonSegment(
                      value: 'groq',
                      label: Text('Groq AI (Online)'),
                      icon: Icon(Icons.auto_awesome, size: 16),
                    ),
                    ButtonSegment(
                      value: 'mlkit',
                      label: Text('ML Kit (Offline)'),
                      icon: Icon(Icons.offline_bolt_outlined, size: 16),
                    ),
                  ],
                  selected: {engine},
                  onSelectionChanged: (set) {
                    ref.read(translatorEngineProvider.notifier).setEngine(set.first);
                  },
                ),
                const SizedBox(height: 12),

                // Groq Settings Panel
                if (engine == 'groq') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Model Groq AI',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _availableGroqModels.any((m) => m['id'] == selectedGroqModel)
                              ? selectedGroqModel
                              : _availableGroqModels.first['id'],
                          isExpanded: true,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: _availableGroqModels.map((m) {
                            return DropdownMenuItem(
                              value: m['id'],
                              child: Text(m['label']!, style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              ref.read(groqModelProvider.notifier).setModel(val);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Groq API Key',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _apiKeyController,
                          obscureText: _obscureKey,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'gsk_...',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    _obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                                ),
                              ],
                            ),
                          ),
                          onChanged: (val) {
                            ref.read(groqApiKeyProvider.notifier).setApiKey(val.trim());
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _isTestingConnection ? null : _testGroqConnection,
                              icon: _isTestingConnection
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.network_check_rounded, size: 16),
                              label: Text(
                                _isTestingConnection ? 'Menguji...' : 'Uji Koneksi',
                                style: const TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (_testConnectionResult != null)
                              Expanded(
                                child: Text(
                                  _testConnectionResult!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: (_testConnectionSuccess == true) ? Colors.green : Colors.redAccent,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () async {
                            await GroqApiKeyDialog.show(context);
                            if (mounted) {
                              _apiKeyController.text = ref.read(groqApiKeyProvider);
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.tune_rounded, size: 16, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Kelola API Key & Uji Semua Model Free...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                                Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.primary),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Mode: Translated vs Original
                const Text(
                  'Mode Tampilan',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  expandedInsets: EdgeInsets.zero,
                  segments: const [
                    ButtonSegment(
                      value: 'translated',
                      label: Text('Translated Mode'),
                      icon: Icon(Icons.translate_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: 'original',
                      label: Text('Original Mode'),
                      icon: Icon(Icons.menu_book_rounded, size: 16),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (set) {
                    ref.read(translationModeProvider.notifier).setMode(set.first);
                  },
                ),
                const SizedBox(height: 16),

                // Source & Target Language
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bahasa Sumber',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            initialValue: sourceLang.code,
                            isExpanded: true,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: TranslationLanguage.sourceLanguages.map((lang) {
                              return DropdownMenuItem(
                                value: lang.code,
                                child: Text(
                                  lang.displayName,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                ref
                                    .read(sourceLanguageProvider.notifier)
                                    .setLanguage(TranslationLanguage.fromCode(val));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Icon(Icons.arrow_forward_rounded, color: Colors.grey),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bahasa Target',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            initialValue: targetLang.code,
                            isExpanded: true,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: TranslationLanguage.targetLanguages.map((lang) {
                              final isDownloaded = modelStatus[lang.bcpCode] ?? false;
                              return DropdownMenuItem(
                                value: lang.code,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(lang.displayName, style: const TextStyle(fontSize: 13)),
                                    if (engine == 'mlkit' && !isDownloaded)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(Icons.file_download_outlined, size: 14, color: Colors.orange),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                ref
                                    .read(targetLanguageProvider.notifier)
                                    .setLanguage(TranslationLanguage.fromCode(val));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Inpainting toggle
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hapus Teks Asli (Inpainting Balon)', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Menutupi teks kanji/hangul/inggris dengan warna balon yang pas', style: TextStyle(fontSize: 11)),
                  value: inpaintEnabled,
                  onChanged: (val) {
                    ref.read(bubbleInpaintEnabledProvider.notifier).toggle();
                  },
                ),
              ],

              const Divider(height: 24),

              // Action buttons: Model Manager & Import image
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.vpn_key_rounded, color: Colors.orangeAccent),
                title: const Text('Pengaturan API Key & Model Groq', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Ganti API Key & benchmark semua model gratis Groq', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  GroqApiKeyDialog.show(context);
                },
              ),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_for_offline_rounded, color: Colors.blueAccent),
                title: const Text('Kelola Model Bahasa Offline', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Unduh/hapus model bahasa ML Kit lokal (~30MB)', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  TranslationModelManagerDialog.show(context);
                },
              ),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_photo_alternate_rounded, color: Colors.green),
                title: const Text('Terjemahkan Gambar dari Galeri / File', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Pilih foto manga dari HP untuk diterjemahkan', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ImportTranslationScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
