import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_storage.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/content_mode.dart';
import '../../shared/widgets/cached_cover.dart';

class ContentModeEditScreen extends ConsumerStatefulWidget {
  final ContentMode? initialMode;

  const ContentModeEditScreen({super.key, this.initialMode});

  @override
  ConsumerState<ContentModeEditScreen> createState() => _ContentModeEditScreenState();
}

class _ContentModeEditScreenState extends ConsumerState<ContentModeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late bool _isDefault;
  final Set<String> _enabledSources = {};

  bool get _isEditing => widget.initialMode != null;
  bool get _isNormalMode => widget.initialMode?.id == ContentMode.defaultNormalId;

  @override
  void initState() {
    super.initState();
    final mode = widget.initialMode;
    _nameController = TextEditingController(text: mode?.name ?? '');
    _descController = TextEditingController(text: mode?.description ?? '');
    _isDefault = mode?.isDefault ?? false;

    if (mode != null) {
      if (mode.enabledSources.isNotEmpty) {
        _enabledSources.addAll(mode.enabledSources);
      } else {
        // If enabledSources is empty, derive from all sources excluding disabledSources
        _enabledSources.addAll(
          ['softkomik', 'komiku', 'shinigami', 'kiryuu', 'komikindo', 'westmanga', 'hwago', 'apkomik', 'doujindesu', 'komiktap', 'bacakomik', 'lumos', 'holotoon', 'pixhentai', 'ikiru', 'hentaicrot', 'voratoon', 'luvyaa', 'crotpedia', 'mihentai', 'ainz', 'soulscans', 'komikstation', 'komikindoch', 'sasangeyou', 'kanzenin', 'mangasusuku', 'izanamiscans', 'cgbum', 'lepoytl', 'yurilab', 'maid', 'natsu', 'komikremaja', 'shirodoujin', 'komikapk', 'mangapill', 'fanfox']
              .where((s) => !mode.disabledSources.contains(s)),
        );
      }
    } else {
      // Default enabled sources for a new custom mode: all standard sources
      _enabledSources.addAll(ContentMode.normal.enabledSources);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final desc = _descController.text.trim();

    final allSourcesAsync = ref.read(sourcesListProvider);
    final allSourceIds = allSourcesAsync.value?.map((s) => s.id).toList() ?? [
      'softkomik', 'komiku', 'shinigami', 'kiryuu', 'komikindo', 'westmanga', 'hwago', 'apkomik', 'doujindesu', 'komiktap', 'bacakomik', 'lumos', 'holotoon', 'pixhentai', 'ikiru', 'hentaicrot', 'voratoon', 'luvyaa', 'crotpedia', 'mihentai', 'ainz', 'soulscans', 'komikstation', 'komikindoch', 'sasangeyou', 'kanzenin', 'mangasusuku', 'izanamiscans', 'cgbum', 'lepoytl', 'yurilab', 'maid', 'natsu', 'komikremaja', 'shirodoujin', 'komikapk', 'mangapill', 'fanfox'
    ];

    final disabled = allSourceIds.where((id) => !_enabledSources.contains(id)).toList();
    final enabled = _enabledSources.toList();

    if (_isEditing) {
      await LocalStorage.updateContentMode(
        widget.initialMode!.id,
        name: name,
        description: desc,
        enabledSources: enabled,
        disabledSources: disabled,
        isDefault: _isDefault,
      );
    } else {
      await LocalStorage.createContentMode(
        name: name,
        description: desc,
        enabledSources: enabled,
        disabledSources: disabled,
        isDefault: _isDefault,
      );
    }

    ref.read(contentModesListProvider.notifier).reload();
    ref.read(activeContentModeProvider.notifier).refresh();

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourcesAsync = ref.watch(sourcesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Mode Konten' : 'Mode Konten Baru'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Simpan'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Nama Mode
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Nama Mode',
                hintText: 'Contoh: Manhwa, Novel, Manga Jepang',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.label_outline_rounded),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Nama mode tidak boleh kosong';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Deskripsi
            TextFormField(
              controller: _descController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Deskripsi (Opsional)',
                hintText: 'Contoh: Library khusus komik berwarna Korea',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 12),

            // Default Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Jadikan Mode Default'),
              subtitle: const Text('Mode ini akan langsung aktif ketika aplikasi pertama kali dibuka'),
              value: _isDefault,
              onChanged: _isNormalMode && _isDefault
                  ? null // Normal cannot be un-defaulted unless another is chosen as default
                  : (val) => setState(() => _isDefault = val),
            ),

            const Divider(height: 32),

            // Source catalog header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Katalog Sumber Manga',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      'Pilih sumber yang aktif pada mode ini',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                sourcesAsync.when(
                  data: (sources) => Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _enabledSources.addAll(sources.map((s) => s.id));
                          });
                        },
                        child: const Text('Semua', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _enabledSources.clear();
                          });
                        },
                        child: const Text('Kosongkan', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (err, stack) => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Sources list
            sourcesAsync.when(
              data: (sources) {
                if (sources.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('Tidak ada sumber tersedia')),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sources.length,
                  separatorBuilder: (ctx, idx) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final source = sources[index];
                    final isChecked = _enabledSources.contains(source.id);
                    final initial = source.name.isNotEmpty ? source.name[0].toUpperCase() : '?';

                    return CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      value: isChecked,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _enabledSources.add(source.id);
                          } else {
                            _enabledSources.remove(source.id);
                          }
                        });
                      },
                      secondary: SizedBox(
                        width: 38,
                        height: 38,
                        child: source.icon != null && source.icon!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedCover(
                                  imageUrl: source.icon!,
                                  fit: BoxFit.contain,
                                  placeholder: (ctx, url) => const SizedBox.shrink(),
                                  errorWidget: (ctx, url, err) => Container(
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(child: Text(initial)),
                                  ),
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(child: Text(initial)),
                              ),
                      ),
                      title: Text(
                        source.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        source.id,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Center(child: Text('Gagal memuat sumber: $err')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
