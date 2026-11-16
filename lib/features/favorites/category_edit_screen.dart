import 'package:flutter/material.dart';
import '../../core/storage/local_storage.dart';
import '../../core/services/sync_service.dart';

class CategoryEditScreen extends StatefulWidget {
  final String? initialName;

  const CategoryEditScreen({
    super.key,
    this.initialName,
  });

  @override
  State<CategoryEditScreen> createState() => _CategoryEditScreenState();
}

class _CategoryEditScreenState extends State<CategoryEditScreen> {
  late final TextEditingController _nameController;
  bool _checkNewChapters = true;
  bool _showOnShelf = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');

    if (widget.initialName != null) {
      final meta = LocalStorage.getCategoryDetails(widget.initialName!);
      _checkNewChapters = meta['checkNewChapters'] as bool? ?? true;
      _showOnShelf = meta['showOnShelf'] as bool? ?? true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (widget.initialName == null) {
      // Create new category
      await LocalStorage.addFavoriteCategory(name);
      await LocalStorage.saveCategoryDetails(name,
        checkNewChapters: _checkNewChapters,
        showOnShelf: _showOnShelf,
      );
    } else {
      // Edit existing category
      if (widget.initialName != name) {
        await LocalStorage.renameFavoriteCategory(widget.initialName!, name);
      }
      await LocalStorage.saveCategoryDetails(name,
        checkNewChapters: _checkNewChapters,
        showOnShelf: _showOnShelf,
      );
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _confirmDelete() {
    if (widget.initialName == null) return;
    final catName = widget.initialName!;
    bool isDeleting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text('Hapus Kategori', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Yakin ingin menghapus kategori "$catName"?\n\nKomik di dalamnya akan tetap tersimpan di koleksi utama tanpa kategori.',
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              if (isDeleting) ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Menghapus dari perangkat & server...', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: isDeleting
                  ? null
                  : () async {
                      setDialogState(() => isDeleting = true);
                      final modeId = LocalStorage.getActiveContentModeId();

                      // 1. Hapus dari database lokal & reassign komik & catat tombstone
                      await LocalStorage.deleteFavoriteCategory(catName, modeId: modeId);

                      // 2. Hapus langsung di server jika terhubung
                      if (LocalStorage.isSyncLoggedIn() && LocalStorage.isSyncFavoritesEnabled()) {
                        try {
                          await SyncService.deleteCategoryOnServer(catName, modeId: modeId);
                        } catch (_) {}
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) Navigator.pop(context, true);
                    },
              child: const Text('Hapus'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.initialName != null;
    final isSaveEnabled = _nameController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Sunting kategori' : 'Kategori baru',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                minimumSize: const Size(0, 36),
              ),
              onPressed: isSaveEnabled ? _save : null,
              child: const Text(
                'Simpan',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Nama Input Field
            TextField(
              controller: _nameController,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nama',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // 2. Periksa bab baru Switch
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Text(
                    'Periksa bab baru',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Switch(
                    value: _checkNewChapters,
                    onChanged: (val) => setState(() => _checkNewChapters = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 4. Tampilkan di Rak Switch
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Text(
                    'Tampilkan di Rak',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Switch(
                    value: _showOnShelf,
                    onChanged: (val) => setState(() => _showOnShelf = val),
                  ),
                ],
              ),
            ),

            if (isEditing) ...[
              const SizedBox(height: 48),
              Center(
                child: TextButton.icon(
                  onPressed: _confirmDelete,
                  icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                  label: Text(
                    'Hapus kategori',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
