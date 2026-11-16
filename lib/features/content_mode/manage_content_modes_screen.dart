import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_storage.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/content_mode.dart';
import 'content_mode_edit_screen.dart';

class ManageContentModesScreen extends ConsumerStatefulWidget {
  const ManageContentModesScreen({super.key});

  @override
  ConsumerState<ManageContentModesScreen> createState() => _ManageContentModesScreenState();
}

class _ManageContentModesScreenState extends ConsumerState<ManageContentModesScreen> {
  late List<ContentMode> _modes;
  late String _activeModeId;

  @override
  void initState() {
    super.initState();
    _loadModes();
  }

  void _loadModes() {
    setState(() {
      _modes = LocalStorage.getContentModes();
      _activeModeId = LocalStorage.getActiveContentModeId();
    });
  }

  Future<void> _openCreateMode() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ContentModeEditScreen()),
    );
    if (result == true) {
      _loadModes();
    }
  }

  Future<void> _openEditMode(ContentMode mode) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ContentModeEditScreen(initialMode: mode)),
    );
    if (result == true) {
      _loadModes();
    }
  }

  Future<void> _setDefaultMode(ContentMode mode) async {
    await LocalStorage.setDefaultContentModeId(mode.id);
    _loadModes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mode default diubah ke ${mode.name}'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _switchMode(ContentMode mode) async {
    ref.read(activeContentModeProvider.notifier).setMode(mode.id);
    _loadModes();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Beralih ke mode ${mode.name}'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _confirmDeleteMode(ContentMode mode) {
    if (mode.id == ContentMode.defaultNormalId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mode Normal adalah mode bawaan dan tidak dapat dihapus.'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
        ),
      );
      return;
    }

    final favCount = LocalStorage.getFavorites(modeId: mode.id).length;
    final histCount = LocalStorage.getHistory(modeId: mode.id).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus Mode "${mode.name}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Apakah kamu yakin ingin menghapus mode "${mode.name}"?'),
            if (favCount > 0 || histCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Mode ini memiliki $favCount komik favorit dan $histCount riwayat baca yang akan ikut terhapus.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalStorage.deleteContentMode(mode.id);
              ref.read(contentModesListProvider.notifier).reload();
              ref.read(activeContentModeProvider.notifier).refresh();
              _loadModes();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Mode "${mode.name}" berhasil dihapus'),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                  ),
                );
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _confirmClearModeData(ContentMode mode) {
    if (mode.id == ContentMode.defaultNormalId) return;

    final favCount = LocalStorage.getFavorites(modeId: mode.id).length;
    final histCount = LocalStorage.getHistory(modeId: mode.id).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bersihkan Data "${mode.name}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seluruh data favorit ($favCount komik), kategori, dan riwayat ($histCount item) pada mode "${mode.name}" akan dihapus bersih.',
            ),
            const SizedBox(height: 10),
            Text(
              'Data di mode lain (seperti mode Normal) tidak akan terpengaruh sama sekali.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalStorage.clearModeData(mode.id);
              _loadModes();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Data mode "${mode.name}" berhasil dibersihkan.'),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                  ),
                );
              }
            },
            child: const Text('Bersihkan'),
          ),
        ],
      ),
    );
  }

  IconData _getModeIcon(String id) {
    switch (id) {
      case ContentMode.defaultNormalId:
        return Icons.auto_stories_rounded;
      case ContentMode.defaultRestrictedId:
        return Icons.explicit_rounded;
      default:
        return Icons.style_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Mode Konten'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Tambah Mode Konten',
            onPressed: _openCreateMode,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Multiple Library (Mode Konten)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Setiap mode memiliki library favorit, riwayat membaca, dan katalog sumber manga yang terisolasi secara mandiri.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'Daftar Mode (${_modes.length})',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),

          // List of Modes
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _modes.length,
            separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final mode = _modes[index];
              final isActive = mode.id == _activeModeId;
              final favCount = LocalStorage.getFavorites(modeId: mode.id).length;
              final histCount = LocalStorage.getHistory(modeId: mode.id).length;
              final isNormal = mode.id == ContentMode.defaultNormalId;

              return Material(
                color: isActive
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                    : theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openEditMode(mode),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getModeIcon(mode.id),
                            size: 20,
                            color: isActive
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    mode.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (isActive) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Aktif',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (mode.isDefault) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.secondaryContainer,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Bawaan',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              if (mode.description.isNotEmpty)
                                Text(
                                  mode.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              Text(
                                '$favCount favorit • $histCount riwayat',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (val) {
                            switch (val) {
                              case 'switch':
                                _switchMode(mode);
                                break;
                              case 'default':
                                _setDefaultMode(mode);
                                break;
                              case 'edit':
                                _openEditMode(mode);
                                break;
                              case 'clear':
                                _confirmClearModeData(mode);
                                break;
                              case 'delete':
                                _confirmDeleteMode(mode);
                                break;
                            }
                          },
                          itemBuilder: (ctx) => [
                            if (!isActive)
                              const PopupMenuItem(
                                value: 'switch',
                                height: 40,
                                child: Row(
                                  children: [
                                    Icon(Icons.swap_horiz_rounded, size: 18),
                                    SizedBox(width: 10),
                                    Text('Gunakan Mode Ini', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            if (!mode.isDefault)
                              const PopupMenuItem(
                                value: 'default',
                                height: 40,
                                child: Row(
                                  children: [
                                    Icon(Icons.star_outline_rounded, size: 18),
                                    SizedBox(width: 10),
                                    Text('Jadikan Mode Default', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'edit',
                              height: 40,
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 18),
                                  SizedBox(width: 10),
                                  Text('Edit Mode', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                            if (!isNormal) ...[
                              PopupMenuItem(
                                value: 'clear',
                                height: 40,
                                child: Row(
                                  children: [
                                    Icon(Icons.cleaning_services_outlined,
                                        size: 18, color: theme.colorScheme.error),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Bersihkan Data Mode',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                height: 40,
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded,
                                        size: 18, color: theme.colorScheme.error),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Hapus Mode',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateMode,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Mode Baru'),
      ),
    );
  }
}
