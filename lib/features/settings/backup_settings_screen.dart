import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/storage/local_storage.dart';
import '../../core/services/backup_service.dart';
import '../../shared/models/content_mode.dart';

class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  bool _isLoading = false;

  void _showCreateBackupDialog() {
    final List<ContentMode> modes = LocalStorage.getContentModes();
    String selectedModeId = LocalStorage.getActiveContentModeId();

    bool incFavorites = true;
    bool incHistory = true;
    bool incCategories = true;
    bool incBookmarks = true;
    bool incSettings = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final favCount = LocalStorage.getFavorites(modeId: selectedModeId).length;
          final histCount = LocalStorage.getHistory(modeId: selectedModeId).length;
          final catCount = LocalStorage.getFavoriteCategories(modeId: selectedModeId).length;
          final bookmarkCount = LocalStorage.getAllBookmarks(modeId: selectedModeId).length;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 16,
              left: 20,
              right: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.archive_rounded, color: theme.colorScheme.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Buat Cadangan Baru',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Format Resmi Kotatsu Redo (.bk.zip)',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Pilihan Mode Konten
                  if (modes.length > 1) ...[
                    Text(
                      'Pilih Mode Konten (Library):',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedModeId,
                          isExpanded: true,
                          items: modes.map((m) {
                            return DropdownMenuItem<String>(
                              value: m.id,
                              child: Text('${m.name} ${m.isDefault ? "(Default)" : ""}',
                                  style: const TextStyle(fontSize: 14)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedModeId = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  Text(
                    'Pilih Bagian Cadangan:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 4),

                  CheckboxListTile(
                    value: incFavorites,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Komik Favorit', style: TextStyle(fontSize: 14)),
                    subtitle: Text('$favCount komik tersimpan', style: const TextStyle(fontSize: 11)),
                    onChanged: (v) => setModalState(() => incFavorites = v ?? true),
                  ),
                  CheckboxListTile(
                    value: incHistory,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Riwayat Membaca', style: TextStyle(fontSize: 14)),
                    subtitle: Text('$histCount bab riwayat', style: const TextStyle(fontSize: 11)),
                    onChanged: (v) => setModalState(() => incHistory = v ?? true),
                  ),
                  CheckboxListTile(
                    value: incCategories,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Kategori Favorit', style: TextStyle(fontSize: 14)),
                    subtitle: Text('$catCount kategori khusus', style: const TextStyle(fontSize: 11)),
                    onChanged: (v) => setModalState(() => incCategories = v ?? true),
                  ),
                  CheckboxListTile(
                    value: incBookmarks,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Penanda Halaman (Bookmark)', style: TextStyle(fontSize: 14)),
                    subtitle: Text('$bookmarkCount penanda halaman', style: const TextStyle(fontSize: 11)),
                    onChanged: (v) => setModalState(() => incBookmarks = v ?? true),
                  ),
                  CheckboxListTile(
                    value: incSettings,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pengaturan & Sumber', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Preferensi aplikasi dan status sumber', style: TextStyle(fontSize: 11)),
                    onChanged: (v) => setModalState(() => incSettings = v ?? true),
                  ),

                  const SizedBox(height: 16),

                  // Tombol Aksi
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: const Text('Bagikan'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _processCreateBackup(
                              modeId: selectedModeId,
                              incFavorites: incFavorites,
                              incHistory: incHistory,
                              incCategories: incCategories,
                              incBookmarks: incBookmarks,
                              incSettings: incSettings,
                              action: 'share',
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.save_alt_rounded, size: 18),
                          label: const Text('Simpan File'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _processCreateBackup(
                              modeId: selectedModeId,
                              incFavorites: incFavorites,
                              incHistory: incHistory,
                              incCategories: incCategories,
                              incBookmarks: incBookmarks,
                              incSettings: incSettings,
                              action: 'save',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Salin Cadangan sebagai JSON', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _copyBackupAsJson(selectedModeId);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _processCreateBackup({
    required String modeId,
    required bool incFavorites,
    required bool incHistory,
    required bool incCategories,
    required bool incBookmarks,
    required bool incSettings,
    required String action,
  }) async {
    setState(() => _isLoading = true);
    try {
      final zipBytes = KotatsuBackupService.createBackupZip(
        modeId: modeId,
        includeFavorites: incFavorites,
        includeHistory: incHistory,
        includeCategories: incCategories,
        includeBookmarks: incBookmarks,
        includeSettings: incSettings,
        includeSources: incSettings,
      );

      final now = DateTime.now();
      await LocalStorage.setLastBackupTime(now);

      final dateStr = DateFormat('yyyyMMdd-HHmm').format(now);
      final fileName = 'kotatsu_$dateStr.bk.zip';

      // Simpan sementara di cache/temp directory
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(zipBytes);

      if (!mounted) return;

      if (action == 'share') {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(tempFile.path, mimeType: 'application/zip', name: fileName)],
            subject: 'Cadangan Manga Reader',
            text: 'File cadangan Manga Reader ($fileName)',
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('File cadangan siap dibagikan ($fileName)')),
        );
      } else {
        // action == 'save'
        Uri? savedUri;
        try {
          savedUri = await FilePicker.saveFile(
            dialogTitle: 'Pilih Lokasi Penyimpanan Cadangan',
            fileName: fileName,
            bytes: zipBytes,
            mimeType: 'application/zip',
          );
        } catch (_) {
          savedUri = null;
        }

        if (!mounted) return;
        if (savedUri != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Cadangan berhasil disimpan ($fileName)')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              content: Text('File disimpan di direktori aplikasi ($fileName)'),
              action: SnackBarAction(
                label: 'Bagikan',
                onPressed: () {
                  SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(tempFile.path, mimeType: 'application/zip', name: fileName)],
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Gagal membuat cadangan: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _copyBackupAsJson(String modeId) {
    final data = LocalStorage.exportBackupData(modeId: modeId);
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    Clipboard.setData(ClipboardData(text: jsonString));
    LocalStorage.setLastBackupTime(DateTime.now());
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Cadangan format JSON disalin ke papan klip')),
    );
  }

  void _showRestoreBackupChoiceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Pulihkan Cadangan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Pilih metode untuk mengimpor data komik dan pengaturan Anda:',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.folder_zip_rounded, color: Theme.of(context).colorScheme.primary),
              ),
              title: const Text('Pilih File Cadangan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Mendukung file .bk.zip resmi Kotatsu Redo atau .json',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                _pickBackupFile();
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.paste_rounded, color: Theme.of(context).colorScheme.secondary),
              ),
              title: const Text('Tempel Teks JSON', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Impor data teks JSON dari papan klip atau salinan manual',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                _showPasteJsonDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBackupFile() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Pilih File Cadangan Kotatsu (.bk.zip atau .json)',
        type: FileType.any,
      );

      if (file == null) return;

      final bytes = await file.xFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('File yang dipilih kosong.');
      }

      final preview = KotatsuBackupService.parseBackup(bytes, fileName: file.name);
      if (!mounted) return;
      _showRestorePreviewDialog(preview);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Gagal membaca file cadangan: $e')),
      );
    }
  }

  void _showPasteJsonDialog() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.paste_rounded, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('Tempel Cadangan JSON', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tempel data cadangan teks JSON:',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: textController,
              maxLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              decoration: InputDecoration(
                hintText: '{\n  "favorites": [...],\n  "history": [...]\n}',
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste_rounded, size: 20),
                  tooltip: 'Tempel dari papan klip',
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      textController.text = data!.text!;
                    }
                  },
                ),
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
            onPressed: () {
              final raw = textController.text.trim();
              if (raw.isEmpty) return;

              try {
                final bytes = Uint8List.fromList(utf8.encode(raw));
                final preview = KotatsuBackupService.parseBackup(bytes, fileName: 'clipboard.json');
                Navigator.pop(ctx);
                _showRestorePreviewDialog(preview);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Format JSON tidak valid: $e')),
                );
              }
            },
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
  }

  void _showRestorePreviewDialog(BackupPreview preview) {
    final List<ContentMode> modes = LocalStorage.getContentModes();
    String targetModeId = LocalStorage.getActiveContentModeId();

    bool restFavorites = preview.favoritesCount > 0;
    bool restHistory = preview.historyCount > 0;
    bool restCategories = preview.categoriesCount > 0;
    bool restBookmarks = preview.bookmarksCount > 0;
    bool restSettings = preview.settings.isNotEmpty;
    bool isRestoring = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final dateStr = DateFormat('d MMM yyyy, HH:mm').format(preview.createdAt);

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.settings_backup_restore_rounded, color: theme.colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Pratinjau Cadangan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Kartu Info File
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                preview.isKotatsuZip ? Icons.archive_rounded : Icons.code_rounded,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  preview.originalFileName ??
                                      (preview.isKotatsuZip ? 'Kotatsu Backup (.bk.zip)' : 'JSON Backup'),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Dibuat: $dateStr', style: const TextStyle(fontSize: 11.5)),
                          Text('Aplikasi: ${preview.appId} (v${preview.appVersion})',
                              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Pemilihan Target Mode Konten
                    Text(
                      'Pulihkan ke Mode Konten:',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: targetModeId,
                          isExpanded: true,
                          items: modes.map((m) {
                            return DropdownMenuItem<String>(
                              value: m.id,
                              child: Text('${m.name} ${m.isDefault ? "(Default)" : ""}',
                                  style: const TextStyle(fontSize: 13.5)),
                            );
                          }).toList(),
                          onChanged: isRestoring
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setDialogState(() {
                                      targetModeId = val;
                                    });
                                  }
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    Text(
                      'Pilih Komponen untuk Dipulihkan:',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 4),

                    CheckboxListTile(
                      value: restFavorites,
                      dense: true,
                      enabled: !isRestoring && preview.favoritesCount > 0,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Favorit (${preview.favoritesCount} komik)', style: const TextStyle(fontSize: 13.5)),
                      onChanged: (v) => setDialogState(() => restFavorites = v ?? true),
                    ),
                    CheckboxListTile(
                      value: restHistory,
                      dense: true,
                      enabled: !isRestoring && preview.historyCount > 0,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Riwayat Membaca (${preview.historyCount} bab)',
                          style: const TextStyle(fontSize: 13.5)),
                      onChanged: (v) => setDialogState(() => restHistory = v ?? true),
                    ),
                    CheckboxListTile(
                      value: restCategories,
                      dense: true,
                      enabled: !isRestoring && preview.categoriesCount > 0,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Kategori (${preview.categoriesCount} kategori)',
                          style: const TextStyle(fontSize: 13.5)),
                      onChanged: (v) => setDialogState(() => restCategories = v ?? true),
                    ),
                    CheckboxListTile(
                      value: restBookmarks,
                      dense: true,
                      enabled: !isRestoring && preview.bookmarksCount > 0,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Penanda / Bookmark (${preview.bookmarksCount})',
                          style: const TextStyle(fontSize: 13.5)),
                      onChanged: (v) => setDialogState(() => restBookmarks = v ?? true),
                    ),
                    CheckboxListTile(
                      value: restSettings,
                      dense: true,
                      enabled: !isRestoring && preview.settings.isNotEmpty,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Pengaturan Aplikasi (${preview.settings.length} setelan)',
                          style: const TextStyle(fontSize: 13.5)),
                      subtitle: const Text('Menimpa setelan pembaca dan tema', style: TextStyle(fontSize: 11)),
                      onChanged: (v) => setDialogState(() => restSettings = v ?? true),
                    ),

                    if (isRestoring) ...[
                      const SizedBox(height: 12),
                      const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('Memulihkan data...', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isRestoring ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: isRestoring
                    ? null
                    : () async {
                        setDialogState(() => isRestoring = true);
                        try {
                          final result = await KotatsuBackupService.restoreBackup(
                            preview,
                            targetModeId: targetModeId,
                            restoreFavorites: restFavorites,
                            restoreHistory: restHistory,
                            restoreCategories: restCategories,
                            restoreBookmarks: restBookmarks,
                            restoreSettings: restSettings,
                          );

                          if (!dialogCtx.mounted) return;
                          Navigator.pop(dialogCtx);

                          if (mounted) {
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text(result.message)),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isRestoring = false);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Gagal memulihkan cadangan: $e')),
                          );
                        }
                      },
                child: const Text('Pulihkan Sekarang'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAutoBackupDialog() {
    final current = LocalStorage.getAutoBackupFrequency();
    final options = [
      {'val': 'off', 'label': 'Nonaktif', 'desc': 'Cadangan hanya dibuat manual'},
      {'val': 'daily', 'label': 'Setiap Hari', 'desc': 'Otomatis membuat cadangan sekali sehari'},
      {'val': '2days', 'label': 'Setiap 2 Hari', 'desc': 'Cadangan berkala tiap 2 hari'},
      {'val': 'weekly', 'label': 'Setiap Minggu', 'desc': 'Cadangan berkala tiap akhir pekan'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Frekuensi Pencadangan Otomatis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        children: options.map((opt) {
          final isSelected = current == opt['val'];
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
            title: Text(opt['label']!,
                style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
            subtitle: Text(opt['desc']!,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            trailing: isSelected
                ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20)
                : null,
            onTap: () async {
              await LocalStorage.setAutoBackupFrequency(opt['val']!);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() {});
            },
          );
        }).toList(),
      ),
    );
  }

  void _confirmClearData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text('Hapus Data Lokal?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: const Text(
          'Tindakan ini akan menghapus semua riwayat membaca, daftar favorit, dan penanda pada mode aktif di perangkat ini.\n\nPastikan Anda telah membuat cadangan sebelum melanjutkan.',
          style: TextStyle(fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () async {
              await LocalStorage.clearAllLocalData();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() {});
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Seluruh data lokal berhasil dibersihkan')),
              );
            },
            child: const Text('Hapus Semua'),
          ),
        ],
      ),
    );
  }

  String _formatLastBackup() {
    final raw = LocalStorage.getLastBackupTime();
    if (raw == null) return 'Belum pernah dicadangkan';
    try {
      final dt = DateTime.parse(raw);
      return 'Terakhir: ${DateFormat('d MMM yyyy, HH:mm').format(dt)}';
    } catch (_) {
      return 'Belum pernah dicadangkan';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ContentMode activeMode = LocalStorage.getActiveContentMode();
    final favsCount = LocalStorage.getFavorites().length;
    final histCount = LocalStorage.getHistory().length;
    final catCount = LocalStorage.getFavoriteCategories().length;
    final bookmarkCount = LocalStorage.getAllBookmarks().length;
    final autoBackupFreq = LocalStorage.getAutoBackupFrequency();

    final autoBackupLabel = autoBackupFreq == 'daily'
        ? 'Setiap Hari'
        : autoBackupFreq == '2days'
            ? 'Setiap 2 Hari'
            : autoBackupFreq == 'weekly'
                ? 'Setiap Minggu'
                : 'Nonaktif';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pencadangan dan Pemulihan'),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Sedang memproses cadangan...', style: TextStyle(fontSize: 13)),
                ],
              ),
            )
          : ListView(
              children: [
                // Ringkasan Data
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Status Data (${activeMode.name})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Mode Aktif',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildDataStat(context, '$favsCount', 'Favorit', Icons.favorite_rounded),
                        _buildDataStat(context, '$histCount', 'Riwayat', Icons.history_rounded),
                        _buildDataStat(context, '$catCount', 'Kategori', Icons.category_rounded),
                        _buildDataStat(context, '$bookmarkCount', 'Penanda', Icons.bookmark_rounded),
                      ],
                    ),
                  ),
                ),

                const Divider(height: 24),

                // Aksi Pencadangan
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text(
                    'Cadangkan & Pulihkan',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.file_upload_outlined, color: theme.colorScheme.primary),
                  ),
                  title: const Text('Buat Cadangan (Backup)', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Ekspor format resmi Kotatsu (.bk.zip) • ${_formatLastBackup()}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showCreateBackupDialog,
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.file_download_outlined, color: theme.colorScheme.secondary),
                  ),
                  title: const Text('Pulihkan Cadangan (Restore)', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Impor file .bk.zip Kotatsu atau JSON cadangan'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showRestoreBackupChoiceDialog,
                ),

                const Divider(height: 24),

                // Otomatisasi
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text(
                    'Otomatisasi',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('Pencadangan Otomatis'),
                  subtitle: Text(autoBackupLabel),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showAutoBackupDialog,
                ),

                const Divider(height: 24),

                // Zona Bahaya
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text(
                    'Pengelolaan Data',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.red.shade400,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                  title: const Text('Bersihkan Seluruh Data Lokal', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('Kosongkan semua riwayat, favorit, dan penanda mode ini'),
                  onTap: _confirmClearData,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildDataStat(BuildContext context, String value, String label, IconData icon) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: theme.colorScheme.primary),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
