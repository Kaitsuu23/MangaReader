import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_storage.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/content_mode.dart';
import 'manage_content_modes_screen.dart';

/// Menampilkan popup / modal dialog pemilihan Mode Konten (Content Mode).
Future<void> showContentModeDialog(BuildContext context, [WidgetRef? ref]) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _ContentModeBottomSheet(parentRef: ref),
  );
}

class _ContentModeBottomSheet extends ConsumerStatefulWidget {
  final WidgetRef? parentRef;

  const _ContentModeBottomSheet({this.parentRef});

  @override
  ConsumerState<_ContentModeBottomSheet> createState() => _ContentModeBottomSheetState();
}

class _ContentModeBottomSheetState extends ConsumerState<_ContentModeBottomSheet> {
  late String _activeModeId;
  late List<ContentMode> _modes;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _activeModeId = LocalStorage.getActiveContentModeId();
      _modes = LocalStorage.getContentModes();
    });
  }

  void _selectMode(ContentMode mode) {
    if (_activeModeId == mode.id) {
      Navigator.pop(context);
      return;
    }

    // Update state via riverpod if available, and local storage
    if (widget.parentRef != null) {
      widget.parentRef!.read(activeContentModeProvider.notifier).setMode(mode.id);
    } else {
      ref.read(activeContentModeProvider.notifier).setMode(mode.id);
    }

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text('Beralih ke mode ${mode.name}'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        duration: const Duration(seconds: 2),
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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle indicator
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.dashboard_customize_rounded,
                    size: 22,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode Konten',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'Pilih library konten komik',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  tooltip: 'Kelola Mode',
                  onPressed: () async {
                    Navigator.pop(context);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ManageContentModesScreen()),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Modes List
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _modes.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final mode = _modes[index];
                  final isSelected = mode.id == _activeModeId;
                  final favCount = LocalStorage.getFavorites(modeId: mode.id).length;
                  final histCount = LocalStorage.getHistory(modeId: mode.id).length;

                  return Material(
                    color: isSelected
                        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                        : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _selectMode(mode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _getModeIcon(mode.id),
                                size: 20,
                                color: isSelected
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
                                      if (mode.isDefault) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
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
                                  Text(
                                    mode.description.isNotEmpty
                                        ? mode.description
                                        : '$favCount favorit • $histCount riwayat',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    '$favCount favorit • $histCount riwayat baca',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: theme.colorScheme.primary,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              )
                            else
                              Icon(
                                Icons.radio_button_unchecked_rounded,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Manage modes button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Kelola Mode Konten'),
                onPressed: () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ManageContentModesScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
