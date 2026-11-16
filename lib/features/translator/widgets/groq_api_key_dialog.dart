import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/local_storage.dart';
import '../providers/translator_settings_provider.dart';
import '../services/groq_translation_service.dart';

/// Modal dialog for managing Groq API Key and benchmarking/testing all free Groq models.
class GroqApiKeyDialog extends ConsumerStatefulWidget {
  const GroqApiKeyDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const GroqApiKeyDialog(),
    );
  }

  @override
  ConsumerState<GroqApiKeyDialog> createState() => _GroqApiKeyDialogState();
}

class _GroqApiKeyDialogState extends ConsumerState<GroqApiKeyDialog> {
  late final TextEditingController _keyController;
  bool _obscureKey = true;
  bool _isTestingAll = false;
  final Map<String, GroqModelTestResult> _testResults = {};
  List<String> _modelsToTest = GroqTranslationService.fallbackCandidateModels;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: ref.read(groqApiKeyProvider));
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _saveApiKey() {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key tidak boleh kosong')),
      );
      return;
    }
    ref.read(groqApiKeyProvider.notifier).setApiKey(key);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API Key Groq berhasil disimpan!')),
    );
  }

  void _resetToDefaultKey() {
    _keyController.text = LocalStorage.defaultGroqApiKey;
    ref.read(groqApiKeyProvider.notifier).setApiKey(LocalStorage.defaultGroqApiKey);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API Key dikembalikan ke bawaan aplikasi.')),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _keyController.text = data.text!.trim();
      });
      _saveApiKey();
    }
  }

  Future<void> _testAllModels() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan masukkan API Key Groq terlebih dahulu')),
      );
      return;
    }

    setState(() {
      _isTestingAll = true;
      _testResults.clear();
    });

    try {
      // 1. Fetch available models from Groq API endpoint
      final fetched = await GroqTranslationService.fetchAvailableChatModels(key);
      if (fetched.isNotEmpty && mounted) {
        setState(() {
          _modelsToTest = fetched;
        });
      }

      // 2. Test each model
      for (final modelId in _modelsToTest) {
        if (!mounted) break;
        final res = await GroqTranslationService.testModel(key, modelId);
        if (mounted) {
          setState(() {
            _testResults[modelId] = res;
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingAll = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeModel = ref.watch(groqModelProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
          maxWidth: 500,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.auto_awesome, color: theme.colorScheme.onPrimaryContainer, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kelola API Key & Model Groq',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Uji performa semua model AI gratis dari Groq',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // API Key Field with Actions
              const Text(
                'Groq API Key',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _keyController,
                obscureText: _obscureKey,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'gsk_...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _obscureKey ? 'Tampilkan' : 'Sembunyikan',
                        icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                        onPressed: () => setState(() => _obscureKey = !_obscureKey),
                      ),
                      IconButton(
                        tooltip: 'Tempel dari Clipboard',
                        icon: const Icon(Icons.content_paste_rounded, size: 18),
                        onPressed: _pasteFromClipboard,
                      ),
                      IconButton(
                        tooltip: 'Hapus',
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => setState(() => _keyController.clear()),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Action buttons: Simpan & Reset Default
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _saveApiKey,
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Simpan Key', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _resetToDefaultKey,
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: const Text('Reset Bawaan', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),

              const Divider(height: 24),

              // Benchmark & Model Testing Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Uji Semua Model Free',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _isTestingAll ? null : _testAllModels,
                    icon: _isTestingAll
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.speed_rounded, size: 16),
                    label: Text(
                      _isTestingAll ? 'Menguji...' : 'Uji Semua Model',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // List of Models
              Expanded(
                child: ListView.separated(
                  itemCount: _modelsToTest.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final modelId = _modelsToTest[index];
                    final isActive = (modelId == activeModel);
                    final result = _testResults[modelId];

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive
                            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActive
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          width: isActive ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        modelId,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                                          fontFamily: 'monospace',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isActive)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'Aktif',
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),

                                // Status / Latency badge
                                if (result == null && _isTestingAll)
                                  const Row(
                                    children: [
                                      SizedBox(
                                        width: 10,
                                        height: 10,
                                        child: CircularProgressIndicator(strokeWidth: 1.5),
                                      ),
                                      SizedBox(width: 6),
                                      Text('Menunggu antrean...', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                    ],
                                  )
                                else if (result != null)
                                  Row(
                                    children: [
                                      Icon(
                                        result.isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                                        size: 13,
                                        color: result.isSuccess
                                            ? Colors.green
                                            : (result.errorMessage?.contains('429') ?? false)
                                                ? Colors.orange
                                                : Colors.redAccent,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        result.isSuccess
                                            ? 'Aktif (${result.latencyMs} ms)'
                                            : (result.errorMessage ?? 'Gagal'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: result.isSuccess
                                              ? Colors.green
                                              : (result.errorMessage?.contains('429') ?? false)
                                                  ? Colors.orange
                                                  : Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  const Text(
                                    'Belum diuji',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Select button
                          if (!isActive)
                            TextButton(
                              onPressed: () {
                                ref.read(groqModelProvider.notifier).setModel(modelId);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Model terjemahan diubah ke: $modelId')),
                                );
                              },
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              ),
                              child: const Text('Gunakan', style: TextStyle(fontSize: 12)),
                            )
                          else
                            const Icon(Icons.check_rounded, color: Colors.green, size: 20),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
