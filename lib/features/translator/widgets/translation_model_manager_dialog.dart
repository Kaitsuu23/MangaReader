import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/translation_language.dart';
import '../providers/translator_settings_provider.dart';

/// Dialog for managing offline Google ML Kit On-Device Translation language models (~30MB each).
class TranslationModelManagerDialog extends ConsumerStatefulWidget {
  const TranslationModelManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const TranslationModelManagerDialog(),
    );
  }

  @override
  ConsumerState<TranslationModelManagerDialog> createState() =>
      _TranslationModelManagerDialogState();
}

class _TranslationModelManagerDialogState
    extends ConsumerState<TranslationModelManagerDialog> {
  final Set<String> _loadingCodes = {};

  @override
  Widget build(BuildContext context) {
    final statusMap = ref.watch(downloadedModelsProvider);
    final theme = Theme.of(context);

    final languagesWithModels = TranslationLanguage.supportedLanguages
        .where((l) => l.bcpCode != null)
        .toList();

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.download_for_offline_rounded, color: Colors.blueAccent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Kelola Model Bahasa Offline',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Model bahasa diunduh ke penyimpanan perangkat (~30 MB/bahasa) agar penerjemahan dapat berjalan 100% offline tanpa kuota internet.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: languagesWithModels.length,
                separatorBuilder: (_, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final lang = languagesWithModels[index];
                  final bcp = lang.bcpCode!;
                  final isDownloaded = statusMap[bcp] ?? false;
                  final isLoading = _loadingCodes.contains(bcp);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    title: Text(
                      lang.displayName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${lang.nativeName} • ${isDownloaded ? "Tersedia Offline" : "Belum diunduh"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDownloaded ? Colors.green : Colors.grey,
                      ),
                    ),
                    trailing: isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : isDownloaded
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                                tooltip: 'Hapus model',
                                onPressed: () async {
                                  setState(() => _loadingCodes.add(bcp));
                                  await ref.read(downloadedModelsProvider.notifier).delete(bcp);
                                  setState(() => _loadingCodes.remove(bcp));
                                },
                              )
                            : ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                                icon: const Icon(Icons.download_rounded, size: 16),
                                label: const Text('Unduh'),
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  setState(() => _loadingCodes.add(bcp));
                                  final success =
                                      await ref.read(downloadedModelsProvider.notifier).download(bcp);
                                  setState(() => _loadingCodes.remove(bcp));

                                  if (!mounted) return;
                                  if (!success) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Gagal mengunduh model ${lang.displayName}'),
                                      ),
                                    );
                                  }
                                },
                              ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
