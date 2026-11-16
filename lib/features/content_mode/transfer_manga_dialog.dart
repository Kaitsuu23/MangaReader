// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/models/content_mode.dart';

/// Helper dialog untuk membuat kategori baru di mode tujuan saat transfer komik
Future<String?> _showCreateCategoryDialog(
  BuildContext context, {
  required String targetModeName,
  required String targetModeId,
}) async {
  final controller = TextEditingController();
  String? errorText;

  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setSubState) {
        final theme = Theme.of(dialogCtx);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.create_new_folder_outlined,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Buat Kategori di $targetModeName',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Buat kategori baru di mode $targetModeName agar komik yang dipindahkan langsung masuk ke kategori ini:',
                style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nama Kategori',
                  hintText: 'Misal: Manhwa 18+, Favorit, dsb',
                  errorText: errorText,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.bookmark_outline_rounded, size: 20),
                ),
                onSubmitted: (_) async {
                  final val = controller.text.trim();
                  if (val.isEmpty) {
                    setSubState(() => errorText = 'Nama kategori tidak boleh kosong');
                    return;
                  }
                  if (val == 'Semua' || val == 'Semua kesukaan') {
                    setSubState(() => errorText = 'Nama tersebut adalah kategori bawaan');
                    return;
                  }
                  await LocalStorage.addFavoriteCategory(val, modeId: targetModeId);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, null),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final val = controller.text.trim();
                if (val.isEmpty) {
                  setSubState(() => errorText = 'Nama kategori tidak boleh kosong');
                  return;
                }
                if (val == 'Semua' || val == 'Semua kesukaan') {
                  setSubState(() => errorText = 'Nama tersebut adalah kategori bawaan');
                  return;
                }
                await LocalStorage.addFavoriteCategory(val, modeId: targetModeId);
                if (dialogCtx.mounted) Navigator.pop(dialogCtx, val);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    ),
  );
}

/// Helper prompt jika mode tujuan belum punya kategori saat tombol Pindahkan ditekan
Future<String?> _showNoCategoryPrompt(
  BuildContext context, {
  required String targetModeName,
}) async {
  return showDialog<String>(
    context: context,
    builder: (promptCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(Icons.folder_open_rounded, color: Theme.of(promptCtx).colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Kategori di Mode Tujuan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: Text(
        'Mode "$targetModeName" belum memiliki kategori favorit.\n\nApakah kamu ingin membuat kategori baru di mode ini sekarang, atau simpan komik tanpa kategori khusus?',
        style: const TextStyle(fontSize: 13, height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(promptCtx, 'cancel'),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(promptCtx, 'skip'),
          child: const Text('Tanpa Kategori'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(promptCtx, 'create'),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Buat Kategori'),
        ),
      ],
    ),
  );
}

/// Dialog untuk mentransfer komik beserta progress membaca, bookmark, dan status favorit antar-mode.
Future<bool?> showTransferMangaDialog(
  BuildContext context, {
  required String slug,
  required String title,
  String? fromModeId,
}) async {
  final currentFrom = fromModeId ?? LocalStorage.getActiveContentModeId();
  final allModes = LocalStorage.getContentModes();
  final targetCandidates = allModes.where((m) => m.id != currentFrom).toList();

  if (targetCandidates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tidak ada mode tujuan lain yang tersedia. Buat mode baru terlebih dahulu.'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
      ),
    );
    return false;
  }

  String selectedTargetId = targetCandidates.first.id;
  String? selectedCategory;

  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final theme = Theme.of(ctx);
        final fromMode = allModes.firstWhere(
          (m) => m.id == currentFrom,
          orElse: () => ContentMode.normal,
        );
        final targetMode = allModes.firstWhere(
          (m) => m.id == selectedTargetId,
          orElse: () => targetCandidates.first,
        );

        final targetCategories = LocalStorage.getFavoriteCategories(modeId: selectedTargetId);

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.drive_file_move_outlined,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Pindah Mode Konten',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Dari: ${fromMode.name}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Pilih Mode Tujuan:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      children: targetCandidates.map((mode) {
                        final isSelected = mode.id == selectedTargetId;
                        return RadioListTile<String>(
                          value: mode.id,
                          groupValue: selectedTargetId,
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          title: Text(
                            mode.name,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          subtitle: mode.description.isNotEmpty
                              ? Text(
                                  mode.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                )
                              : null,
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedTargetId = val;
                                selectedCategory = null;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Kategori di Mode Tujuan
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kategori di ${targetMode.name}:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final newCat = await _showCreateCategoryDialog(
                            ctx,
                            targetModeName: targetMode.name,
                            targetModeId: selectedTargetId,
                          );
                          if (newCat != null) {
                            setDialogState(() {
                              selectedCategory = newCat;
                            });
                          }
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Buat Kategori', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  if (targetCategories.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.folder_open_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Mode ${targetMode.name} belum memiliki kategori.',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final newCat = await _showCreateCategoryDialog(
                                ctx,
                                targetModeName: targetMode.name,
                                targetModeId: selectedTargetId,
                              );
                              if (newCat != null) {
                                setDialogState(() {
                                  selectedCategory = newCat;
                                });
                              }
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: Text('Buat Kategori di ${targetMode.name}', style: const TextStyle(fontSize: 12)),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: targetCategories.map((cat) {
                        final isCatSelected = selectedCategory == cat;
                        return FilterChip(
                          label: Text(cat, style: const TextStyle(fontSize: 12)),
                          selected: isCatSelected,
                          onSelected: (sel) {
                            setDialogState(() {
                              selectedCategory = sel ? cat : null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (selectedCategory == null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Pilih kategori di atas (opsional), atau biarkan kosong untuk menyimpan tanpa kategori.',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Semua progres membaca (persentase, bab terakhir, posisi scroll) dan bookmark akan dipindahkan secara utuh.',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                // Jika mode tujuan belum punya kategori sama sekali dan user belum buat kategori
                if (targetCategories.isEmpty && selectedCategory == null) {
                  final promptChoice = await _showNoCategoryPrompt(
                    ctx,
                    targetModeName: targetMode.name,
                  );
                  if (promptChoice == 'cancel' || promptChoice == null) return;
                  if (promptChoice == 'create') {
                    if (!ctx.mounted) return;
                    final newCat = await _showCreateCategoryDialog(
                      ctx,
                      targetModeName: targetMode.name,
                      targetModeId: selectedTargetId,
                    );
                    if (newCat != null) {
                      selectedCategory = newCat;
                    } else {
                      return; // User membatalkan dialog input kategori
                    }
                  }
                  // promptChoice == 'skip' -> lanjut ke 'Semua kesukaan'
                }

                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);

                await LocalStorage.transferManga(
                  slug: slug,
                  fromModeId: currentFrom,
                  toModeId: selectedTargetId,
                  targetCategory: selectedCategory,
                );

                if (context.mounted) {
                  final catLabel = (selectedCategory != null && selectedCategory!.isNotEmpty)
                      ? ' (Kategori: $selectedCategory)'
                      : '';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('$title berhasil dipindahkan ke mode ${targetMode.name}$catLabel'),
                          ),
                        ],
                      ),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              child: const Text('Pindahkan'),
            ),
          ],
        );
      },
    ),
  );
}

/// Dialog untuk mentransfer beberapa komik sekaligus antar-mode.
Future<bool?> showTransferMultipleMangaDialog(
  BuildContext context, {
  required List<String> slugs,
  String? fromModeId,
}) async {
  if (slugs.isEmpty) return false;

  final currentFrom = fromModeId ?? LocalStorage.getActiveContentModeId();
  final allModes = LocalStorage.getContentModes();
  final targetCandidates = allModes.where((m) => m.id != currentFrom).toList();

  if (targetCandidates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tidak ada mode tujuan lain yang tersedia. Buat mode baru terlebih dahulu.'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
      ),
    );
    return false;
  }

  String selectedTargetId = targetCandidates.first.id;
  String? selectedCategory;

  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final theme = Theme.of(ctx);
        final fromMode = allModes.firstWhere(
          (m) => m.id == currentFrom,
          orElse: () => ContentMode.normal,
        );
        final targetMode = allModes.firstWhere(
          (m) => m.id == selectedTargetId,
          orElse: () => targetCandidates.first,
        );

        final targetCategories = LocalStorage.getFavoriteCategories(modeId: selectedTargetId);

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.drive_file_move_outlined,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Pindah Mode Konten',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${slugs.length} komik dipilih',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Dari: ${fromMode.name}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Pilih Mode Tujuan:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      children: targetCandidates.map((mode) {
                        final isSelected = mode.id == selectedTargetId;
                        return RadioListTile<String>(
                          value: mode.id,
                          groupValue: selectedTargetId,
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          title: Text(
                            mode.name,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          subtitle: mode.description.isNotEmpty
                              ? Text(
                                  mode.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                )
                              : null,
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedTargetId = val;
                                selectedCategory = null;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Kategori di Mode Tujuan
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kategori di ${targetMode.name}:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final newCat = await _showCreateCategoryDialog(
                            ctx,
                            targetModeName: targetMode.name,
                            targetModeId: selectedTargetId,
                          );
                          if (newCat != null) {
                            setDialogState(() {
                              selectedCategory = newCat;
                            });
                          }
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Buat Kategori', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  if (targetCategories.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.folder_open_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Mode ${targetMode.name} belum memiliki kategori.',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final newCat = await _showCreateCategoryDialog(
                                ctx,
                                targetModeName: targetMode.name,
                                targetModeId: selectedTargetId,
                              );
                              if (newCat != null) {
                                setDialogState(() {
                                  selectedCategory = newCat;
                                });
                              }
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: Text('Buat Kategori di ${targetMode.name}', style: const TextStyle(fontSize: 12)),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: targetCategories.map((cat) {
                        final isCatSelected = selectedCategory == cat;
                        return FilterChip(
                          label: Text(cat, style: const TextStyle(fontSize: 12)),
                          selected: isCatSelected,
                          onSelected: (sel) {
                            setDialogState(() {
                              selectedCategory = sel ? cat : null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (selectedCategory == null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Pilih kategori di atas (opsional), atau biarkan kosong untuk menyimpan tanpa kategori.',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Semua progres membaca (persentase, bab terakhir, posisi scroll) dan bookmark akan dipindahkan secara utuh.',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                if (targetCategories.isEmpty && selectedCategory == null) {
                  final promptChoice = await _showNoCategoryPrompt(
                    ctx,
                    targetModeName: targetMode.name,
                  );
                  if (promptChoice == 'cancel' || promptChoice == null) return;
                  if (promptChoice == 'create') {
                    if (!ctx.mounted) return;
                    final newCat = await _showCreateCategoryDialog(
                      ctx,
                      targetModeName: targetMode.name,
                      targetModeId: selectedTargetId,
                    );
                    if (newCat != null) {
                      selectedCategory = newCat;
                    } else {
                      return;
                    }
                  }
                }

                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);

                await LocalStorage.transferMultipleManga(
                  slugs: slugs,
                  fromModeId: currentFrom,
                  toModeId: selectedTargetId,
                  targetCategory: selectedCategory,
                );

                if (context.mounted) {
                  final catLabel = (selectedCategory != null && selectedCategory!.isNotEmpty)
                      ? ' (Kategori: $selectedCategory)'
                      : '';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${slugs.length} komik berhasil dipindahkan ke mode ${targetMode.name}$catLabel'),
                          ),
                        ],
                      ),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              child: const Text('Pindahkan'),
            ),
          ],
        );
      },
    ),
  );
}
