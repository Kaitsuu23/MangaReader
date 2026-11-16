import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/widgets/cached_cover.dart';
import '../../shared/widgets/error_view.dart';
import 'supported_domains_screen.dart';

class SourcesSettingsScreen extends ConsumerStatefulWidget {
  const SourcesSettingsScreen({super.key});

  @override
  ConsumerState<SourcesSettingsScreen> createState() => _SourcesSettingsScreenState();
}

class _SourcesSettingsScreenState extends ConsumerState<SourcesSettingsScreen> {
  void _showHandleLinksDialog() {
    const previewCount = 3;
    final remainingCount = kSupportedDomains.length > previewCount
        ? kSupportedDomains.length - previewCount
        : 0;

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.open_in_browser_rounded, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Penanganan Tautan Web', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aplikasi dapat secara otomatis mendeteksi dan membuka link URL manga dari peramban luar.',
                style: TextStyle(fontSize: 13, height: 1.3),
              ),
              const SizedBox(height: 12),
              const Text(
                'Beberapa domain yang didukung:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              ...kSupportedDomains.take(previewCount).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 12, height: 1.3)),
                      Expanded(
                        child: Text(
                          '${item.sourceName}: ${item.domains.join(' / ')}',
                          style: const TextStyle(fontSize: 12, height: 1.3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (remainingCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SupportedDomainsScreen()),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        'dan $remainingCount sumber lainnya (klik untuk melihat)...',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              const Text(
                'Pastikan pengaturan Android "Buka secara default" diizinkan untuk Yomika di info aplikasi.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SupportedDomainsScreen()),
                );
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Selengkapnya'),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourcesAsync = ref.watch(sourcesListProvider);
    final isHandleLinks = LocalStorage.isHandleLinksEnabled();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sumber Manga'),
      ),
      body: ListView(
        children: [
          // Penanganan Tautan Web
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'Tautan & Eksternal',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.link_rounded),
            title: const Text('Penanganan Tautan Web (Handle Links)'),
            subtitle: const Text('Buka URL manga yang didukung langsung di dalam aplikasi'),
            value: isHandleLinks,
            onChanged: (val) async {
              await LocalStorage.setHandleLinksEnabled(val);
              setState(() {});
            },
          ),
          ListTile(
            leading: const SizedBox(width: 24),
            title: const Text('Daftar domain & bantuan'),
            subtitle: const Text('Lihat situs web manga yang didukung oleh aplikasi'),
            trailing: const Icon(Icons.info_outline_rounded, size: 20),
            onTap: _showHandleLinksDialog,
          ),

          const Divider(height: 24),

          // Kelola Sumber
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Kelola Sumber (Manage Sources)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  'Aktifkan / Pin',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          sourcesAsync.when(
            data: (sources) {
              if (sources.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Tidak ada sumber tersedia')),
                );
              }

              return Column(
                children: sources.map((source) {
                  final isEnabled = LocalStorage.isSourceEnabled(source.id);
                  final isPinned = LocalStorage.isSourcePinned(source.id);

                  final initial = source.name.isNotEmpty ? source.name[0].toUpperCase() : '?';

                  return ListTile(
                    leading: SizedBox(
                      width: 40,
                      height: 40,
                      child: source.icon != null && source.icon!.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedCover(
                                imageUrl: source.icon!,
                                fit: BoxFit.contain,
                                placeholder: (context, url) => const SizedBox.shrink(),
                                errorWidget: (context, url, error) => Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    title: Text(
                      source.name,
                      style: TextStyle(
                        fontWeight: isPinned ? FontWeight.bold : FontWeight.w500,
                        color: isEnabled ? null : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    subtitle: Text(
                      source.id,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            size: 20,
                            color: isPinned ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                          ),
                          tooltip: isPinned ? 'Lepas sematan' : 'Sematkan ke atas',
                          onPressed: () async {
                            await LocalStorage.togglePinSource(source.id);
                            setState(() {});
                          },
                        ),
                        Switch(
                          value: isEnabled,
                          onChanged: (val) async {
                            await LocalStorage.setSourceEnabled(source.id, val);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, stack) => Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorView(
                message: err.toString(),
                onRetry: () => ref.invalidate(sourcesListProvider),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
