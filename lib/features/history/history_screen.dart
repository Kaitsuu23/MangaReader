import 'package:flutter/material.dart';
import '../../shared/widgets/cached_cover.dart';
import '../../shared/widgets/manga_card_badges.dart';
import '../../shared/models/chapter.dart';
import '../../shared/models/manga_item.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../../shared/widgets/kotatsu_search_bar.dart';
import '../details/manga_details_screen.dart';
import '../reader/manga_reader_screen.dart';
import '../settings/settings_screen.dart';
import '../../core/services/sync_service.dart';
import '../content_mode/content_mode_dialog.dart';
import '../content_mode/transfer_manga_dialog.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  final Set<String> _selectedSlugs = {};
  late String _sortOrder;
  late bool _isGroupingEnabled;
  final ScrollController _scrollController = ScrollController();
  bool _filterUnread = false;
  bool _filterNotFavorited = false;

  /// Reset scroll ke atas tanpa animasi — sama seperti resetToFirstTab di FavoritesScreen.
  /// Dipanggil dari MainScreen saat user berpindah kembali ke tab Riwayat.
  void scrollToTop() {
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.jumpTo(0);
    }
  }

  String _itemKey(Map<String, dynamic> item) {
    final src = item['source'] as String? ?? '';
    final slug = item['slug'] as String? ?? '';
    return src.isNotEmpty ? '$src::$slug' : slug;
  }

  /// Most-recently-read history item (highest `updatedAt`), equivalent to
  /// `getHistory(sortOrder: 'last_read').firstOrNull` but derived from an
  /// already-fetched list to avoid a second full box scan on every rebuild.
  Map<String, dynamic>? _mostRecentRead(Iterable<Map<String, dynamic>> items) {
    Map<String, dynamic>? lastRead;
    int maxTs = -1;
    for (final it in items) {
      final ts = (it['updatedAt'] as int?) ?? 0;
      if (ts > maxTs) {
        maxTs = ts;
        lastRead = it;
      }
    }
    return lastRead;
  }

  static const _idMonths = [
    '',
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember'
  ];

  @override
  void initState() {
    super.initState();
    _sortOrder = LocalStorage.getHistorySort();
    _isGroupingEnabled = LocalStorage.isHistoryGroupingEnabled();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isAllSelected(List<Map<String, dynamic>> all) {
    if (all.isEmpty) return false;
    return all.every((item) => _selectedSlugs.contains(_itemKey(item)));
  }

  void _toggleSelectAll(List<Map<String, dynamic>> all) {
    setState(() {
      if (_isAllSelected(all)) {
        _selectedSlugs.clear();
      } else {
        for (final item in all) {
          final key = _itemKey(item);
          if (key.isNotEmpty) _selectedSlugs.add(key);
        }
      }
    });
  }

  void _toggleSelection(String slug) {
    if (slug.isEmpty) return;
    setState(() {
      if (_selectedSlugs.contains(slug)) {
        _selectedSlugs.remove(slug);
      } else {
        _selectedSlugs.add(slug);
      }
    });
  }

  void _exitSelectionMode() {
    if (_selectedSlugs.isNotEmpty) {
      setState(() => _selectedSlugs.clear());
    }
  }

  String _getSortLabel(String sort) {
    switch (sort) {
      case 'long_ago_read':
        return 'Sudah lama dibaca';
      case 'newest':
        return 'Baru ditambahkan';
      case 'oldest':
        return 'Paling lama';
      case 'progress':
        return 'Progres';
      case 'unread':
        return 'Belum selesai';
      case 'title_asc':
        return 'Nama (A - Z)';
      case 'title_desc':
        return 'Nama (Z - A)';
      case 'last_read':
      default:
        return 'Terakhir dibaca';
    }
  }

  PopupMenuItem<String> _buildSortMenuItem(String value, String label) {
    final isSelected = _sortOrder == value;
    final theme = Theme.of(context);
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? theme.colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubheader(BuildContext context, int count, ThemeData theme) {
    final canGroup = _sortOrder == 'last_read' ||
        _sortOrder == 'long_ago_read' ||
        _sortOrder == 'newest' ||
        _sortOrder == 'oldest' ||
        _sortOrder == 'progress' ||
        _sortOrder == 'unread';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFilterChips(theme),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                '$count komik',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (canGroup)
                IconButton(
                  tooltip: _isGroupingEnabled ? 'Matikan pengelompokan' : 'Kelompokkan item',
                  icon: Icon(
                    _isGroupingEnabled ? Icons.workspaces_rounded : Icons.workspaces_outlined,
                    size: 20,
                    color: _isGroupingEnabled ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      _isGroupingEnabled = !_isGroupingEnabled;
                    });
                    LocalStorage.setHistoryGroupingEnabled(_isGroupingEnabled);
                  },
                ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
            tooltip: 'Urutkan',
            offset: const Offset(0, 36),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            initialValue: _sortOrder,
            onSelected: (val) {
              setState(() {
                _sortOrder = val;
              });
              LocalStorage.setHistorySort(_sortOrder);
            },
            itemBuilder: (ctx) => [
              _buildSortMenuItem('last_read', 'Terakhir dibaca'),
              _buildSortMenuItem('long_ago_read', 'Sudah lama dibaca'),
              _buildSortMenuItem('newest', 'Baru ditambahkan'),
              _buildSortMenuItem('oldest', 'Paling lama ditambahkan'),
              _buildSortMenuItem('progress', 'Progres tertinggi'),
              _buildSortMenuItem('unread', 'Belum selesai dibaca'),
              _buildSortMenuItem('title_asc', 'Berdasarkan nama (A - Z)'),
              _buildSortMenuItem('title_desc', 'Berdasarkan nama (Z - A)'),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swap_vert_rounded,
                    size: 17,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getSortLabel(_sortOrder),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
      ],
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    if (!_filterUnread && !_filterNotFavorited) {
      // Show chips in non-selected state
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            _buildChip(
              label: 'Belum dibaca',
              icon: Icons.auto_stories_outlined,
              selected: false,
              theme: theme,
              onTap: () => setState(() => _filterUnread = true),
            ),
            const SizedBox(width: 8),
            _buildChip(
              label: 'Belum di favorit',
              icon: Icons.favorite_border_rounded,
              selected: false,
              theme: theme,
              onTap: () => setState(() => _filterNotFavorited = true),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          if (_filterUnread || !_filterNotFavorited) ...[
            _buildChip(
              label: 'Belum dibaca',
              icon: _filterUnread ? Icons.close : Icons.auto_stories_outlined,
              selected: _filterUnread,
              theme: theme,
              onTap: () => setState(() => _filterUnread = !_filterUnread),
            ),
            const SizedBox(width: 8),
          ],
          if (_filterNotFavorited || !_filterUnread) ...[
            _buildChip(
              label: 'Belum di favorit',
              icon: _filterNotFavorited ? Icons.close : Icons.favorite_border_rounded,
              selected: _filterNotFavorited,
              theme: theme,
              onTap: () => setState(() => _filterNotFavorited = !_filterNotFavorited),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required bool selected,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> items) {
    if (!_filterUnread && !_filterNotFavorited) return items;

    return items.where((item) {
      if (_filterUnread) {
        final percentVal = (item['percent'] as num?)?.toDouble() ?? 0.0;
        final totalChs = (item['totalChapters'] as num?)?.toInt() ?? 0;
        final chNum = (item['chapterNumber'] as num?)?.toInt() ?? 0;
        // Belum selesai: percent < 0.999 ATAU masih ada chapter tersisa
        final isCompleted = percentVal >= 0.999 && (totalChs == 0 || chNum >= totalChs);
        if (isCompleted) return false;
      }
      if (_filterNotFavorited) {
        final slug = item['slug'] as String? ?? '';
        final src = item['source'] as String?;
        if (slug.isEmpty || LocalStorage.isFavorite(slug, source: src)) return false;
      }
      return true;
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> _groupItems(List<Map<String, dynamic>> items) {
    if (_sortOrder == 'progress' || _sortOrder == 'unread') {
      return _groupByProgress(items);
    } else if (_sortOrder == 'newest' || _sortOrder == 'oldest') {
      return _groupByDate(items, isCreatedAt: true);
    } else {
      return _groupByDate(items, isCreatedAt: false);
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupByProgress(List<Map<String, dynamic>> items) {
    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (final item in items) {
      final percentVal = (item['percent'] as num?)?.toDouble();
      final page = (item['page'] as num?)?.toInt() ?? 1;
      final totalPages = (item['totalPages'] as num?)?.toInt() ?? 1;
      final double pct;
      if (percentVal != null && percentVal > 0) {
        var p = percentVal.clamp(0.0, 1.0);
        final totalChs = (item['totalChapters'] as num?)?.toInt() ?? 0;
        final chNum = (item['chapterNumber'] as num?)?.toInt() ?? 0;
        if (totalChs > 0 && chNum > 0) {
          final remaining = totalChs - chNum;
          if (remaining > 0) {
            if (p >= 0.999) {
              p = (chNum / totalChs);
            }
            if (remaining >= 2) {
              p = p.clamp(0.0, remaining >= 3 ? 0.97 : 0.98);
            } else {
              p = p.clamp(0.0, 0.99);
            }
          }
        }
        pct = p;
      } else if (totalPages > 0) {
        pct = (page / totalPages).clamp(0.0, 1.0);
      } else {
        pct = 0.0;
      }

      final String label;
      if (pct >= 0.99) {
        label = 'Selesai';
      } else if (pct > 0.01) {
        label = 'Dibaca';
      } else {
        label = 'Direncanakan';
      }

      groups.putIfAbsent(label, () => []).add(item);
    }
    return groups;
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(
      List<Map<String, dynamic>> items, {required bool isCreatedAt}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (final item in items) {
      final field = isCreatedAt ? (item['createdAt'] ?? item['updatedAt']) : item['updatedAt'];
      final ts = (field as num?)?.toInt() ?? 0;
      if (ts <= 0) {
        groups.putIfAbsent('Tidak diketahui', () => []).add(item);
        continue;
      }
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      final day = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(day).inDays;

      final String label;
      if (diff <= 0) {
        label = 'Hari ini';
      } else if (diff == 1) {
        label = 'Kemarin';
      } else if (diff < 6) {
        label = '$diff hari yang lalu';
      } else {
        final monthName = (dt.month >= 1 && dt.month <= 12) ? _idMonths[dt.month] : '${dt.month}';
        if (dt.year == now.year) {
          label = '${dt.day} $monthName';
        } else {
          label = '${dt.day} $monthName ${dt.year}';
        }
      }

      groups.putIfAbsent(label, () => []).add(item);
    }
    return groups;
  }

  void _openDetail(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaDetailsScreen(
          slug: item['slug'] as String? ?? '',
          source: item['source'] as String? ?? LocalStorage.getActiveSource(),
          title: item['title'] as String?,
          cover: item['cover'] as String?,
          origin: 'history',
        ),
      ),
    );
  }

  void _openReader(Map<String, dynamic> item) {
    final rawSlug = item['slug'] as String? ?? '';
    final cleanSlug = rawSlug.trim().replaceAll(RegExp(r'^/+|/+$'), '').replaceFirst(RegExp(r'^manga/', caseSensitive: false), '').replaceAll(RegExp(r'^/+|/+$'), '');
    final chapterSlug = item['chapterSlug'] as String? ?? '';
    final chapterTitle = item['chapterTitle'] as String? ?? '';
    if (chapterSlug.isEmpty) return;

    final isHashId = int.tryParse(chapterSlug) != null && chapterSlug.length >= 8;
    final chapter = Chapter(
      chapter: chapterSlug,
      title: chapterTitle.isNotEmpty
          ? chapterTitle
          : (isHashId ? 'Memuat bab...' : 'Chapter $chapterSlug'),
      slug: chapterSlug,
    );

    final rawHeights = item['pageHeights'];
    Map<int, double>? savedHeights;
    if (rawHeights is Map) {
      savedHeights = {};
      rawHeights.forEach((k, v) {
        final idx = int.tryParse(k.toString());
        final h = (v as num?)?.toDouble();
        if (idx != null && h != null) savedHeights![idx] = h;
      });
    }
    final savedRatio = (item['pageOffsetRatio'] as num?)?.toDouble();
    final savedPercent = (item['percent'] as num?)?.toDouble() ?? 0.0;
    final isCompleted = savedPercent >= 0.999;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaReaderScreen(
          mangaSlug: cleanSlug.isNotEmpty ? cleanSlug : rawSlug,
          mangaTitle: item['title'] as String? ?? '',
          source: item['source'] as String? ?? LocalStorage.getActiveSource(),
          cover: item['cover'] as String?,
          chapters: [chapter],
          initialChapter: chapter,
          initialPage: (item['page'] as num?)?.toInt() ?? 1,
          initialPageOffset: (item['pageOffset'] as num?)?.toDouble() ?? 0,
          initialScrollOffset: (item['scrollOffset'] as num?)?.toDouble() ?? 0,
          initialPageHeights: savedHeights,
          initialPageOffsetRatio: savedRatio,
          startAtEnd: isCompleted,
          origin: 'history',
        ),
      ),
    );
  }

  void _confirmDeleteSelected(BuildContext context) {
    if (_selectedSlugs.isEmpty) return;
    final count = _selectedSlugs.length;
    final isSyncActive = LocalStorage.isSyncLoggedIn() && LocalStorage.isSyncEnabled();
    bool deleteFromServer = isSyncActive;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Hapus Riwayat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(count == 1
                  ? 'Hapus 1 manga dari riwayat membaca?'
                  : 'Hapus $count manga dari riwayat membaca?'),
              if (isSyncActive) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deleteFromServer,
                  onChanged: (val) {
                    setDialogState(() => deleteFromServer = val ?? false);
                  },
                  title: const Text(
                    'Hapus juga dari server akun sinkronisasi',
                    style: TextStyle(fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
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
              onPressed: () async {
                Navigator.pop(ctx);
                final toDelete = Set<String>.from(_selectedSlugs);
                _exitSelectionMode();
                final currentModeId = LocalStorage.getActiveContentModeId();
                for (final rawKey in toDelete) {
                  String slug = rawKey;
                  String? source;
                  if (rawKey.contains('::')) {
                    final parts = rawKey.split('::');
                    source = parts[0];
                    slug = parts.sublist(1).join('::');
                  }
                  await LocalStorage.deleteHistoryItem(
                    slug,
                    source: source,
                    recordTombstone: deleteFromServer,
                    modeId: currentModeId,
                  );
                }
                if (deleteFromServer) {
                  await SyncService.syncNow(modeId: currentModeId);
                }
              },
              child: const Text('Hapus'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearHistory(BuildContext context) {
    final isSyncActive = LocalStorage.isSyncLoggedIn() && LocalStorage.isSyncEnabled();
    bool deleteFromServer = isSyncActive;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Hapus Riwayat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Hapus semua riwayat membaca?'),
              if (isSyncActive) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deleteFromServer,
                  onChanged: (val) {
                    setDialogState(() => deleteFromServer = val ?? false);
                  },
                  title: const Text(
                    'Hapus juga dari server akun sinkronisasi',
                    style: TextStyle(fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
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
              onPressed: () async {
                Navigator.pop(ctx);
                final currentModeId = LocalStorage.getActiveContentModeId();
                if (deleteFromServer) {
                  await SyncService.clearServerHistory(modeId: currentModeId);
                } else {
                  await LocalStorage.clearHistory(modeId: currentModeId);
                }
              },
              child: const Text('Hapus'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _transferSelected(BuildContext context) async {
    if (_selectedSlugs.isEmpty) return;
    // _selectedSlugs berisi composite key 'source::slug' — ekstrak pure slug untuk dialog
    final toTransfer = _selectedSlugs.map((rawKey) {
      if (rawKey.contains('::')) {
        return rawKey.split('::').sublist(1).join('::');
      }
      return rawKey;
    }).toSet().toList();
    if (toTransfer.isEmpty) return;
    final res = await showTransferMultipleMangaDialog(context, slugs: toTransfer);
    if (res == true && mounted) {
      _exitSelectionMode();
    }
  }

  Widget _buildSelectionHeader(
      BuildContext context, List<Map<String, dynamic>> all, ThemeData theme) {
    final allSelected = _isAllSelected(all);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 22),
              tooltip: 'Batal',
              onPressed: _exitSelectionMode,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${_selectedSlugs.length} dipilih',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                allSelected
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              size: 22,
            ),
            tooltip: allSelected ? 'Batal pilih semua' : 'Pilih semua',
            onPressed: () => _toggleSelectAll(all),
          ),
          IconButton(
            icon: const Icon(
              Icons.drive_file_move_outlined,
              size: 22,
            ),
            tooltip: 'Pindahkan ke mode lain',
            onPressed: () => _transferSelected(context),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 22,
              color: theme.colorScheme.error,
            ),
            tooltip: 'Hapus dari riwayat',
            onPressed: () => _confirmDeleteSelected(context),
          ),
          const SizedBox(width: 6),
        ],
      ),
    ),
  );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _selectedSlugs.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _exitSelectionMode();
        }
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([
          LocalStorage.listenHistory(),
          LocalStorage.listenFavorites(),
          LocalStorage.listenContentMode(),
        ]),
        builder: (context, child) {
          final all = LocalStorage.getHistory(sortOrder: _sortOrder);
          final filtered = _applyFilters(all);
          final lastRead = _mostRecentRead(all);

          return Scaffold(
            // FAB sits above the floating navbar automatically
            floatingActionButton: _selectedSlugs.isNotEmpty
                ? null
                : (lastRead != null
                    ? Padding(
                        // nudge up by navbar height (64) + its bottom padding (12) + gap (8)
                        padding: const EdgeInsets.only(bottom: 84),
                        child: _ContinueFab(
                          onPressed: () => _openReader(lastRead),
                        ),
                      )
                    : null),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.endFloat,
            body: SafeArea(
              child: Column(
                children: [
                  if (_selectedSlugs.isNotEmpty)
                    _buildSelectionHeader(context, filtered, theme)
                  else ...[
                    KotatsuSearchBar(
                      trailingMenu: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        offset: const Offset(0, 40),
                        constraints: const BoxConstraints(minWidth: 160, maxWidth: 200),
                        onSelected: (val) {
                          if (val == 'content_mode') {
                            showContentModeDialog(context);
                          } else if (val == 'settings') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            );
                          } else if (val == 'clear') {
                            _confirmClearHistory(context);
                          }
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'content_mode',
                            height: 40,
                            child: Row(
                              children: [
                                Icon(Icons.dashboard_customize_outlined, size: 18),
                                SizedBox(width: 10),
                                Text('Mode Konten', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'clear',
                            height: 40,
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded, size: 18),
                                SizedBox(width: 10),
                                Text('Hapus riwayat', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'settings',
                            height: 40,
                            child: Row(
                              children: [
                                Icon(Icons.settings_outlined, size: 18),
                                SizedBox(width: 10),
                                Text('Pengaturan', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (all.isNotEmpty)
                      _buildSubheader(context, filtered.length, theme),
                  ],
                  Expanded(
                    child: _buildList(context, filtered, theme),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Map<String, dynamic>> filtered,
      ThemeData theme) {
    if (filtered.isEmpty) {
      final hasActiveFilter = _filterUnread || _filterNotFavorited;
      return EmptyView(
        icon: hasActiveFilter ? Icons.filter_list_off_rounded : Icons.history_rounded,
        title: hasActiveFilter ? 'Tidak Ada Hasil' : 'Riwayat Kosong',
        subtitle: hasActiveFilter
            ? 'Tidak ada manga yang sesuai dengan filter ini.'
            : 'Manga yang pernah kamu baca akan muncul di sini.',
      );
    }

    final canGroup = _isGroupingEnabled &&
        _sortOrder != 'title_asc' &&
        _sortOrder != 'title_desc';

    if (!canGroup) {
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.58,
          crossAxisSpacing: 11,
          mainAxisSpacing: 12,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final item = filtered[index];
          final key = _itemKey(item);
          final isSelected = _selectedSlugs.contains(key);
          final slug = item['slug'] as String? ?? '';
          final src = item['source'] as String?;
          final isFav = slug.isNotEmpty && LocalStorage.isFavorite(slug, source: src);
          final unreadUpdates = LocalStorage.getMangaUnreadNewChaptersCount(slug, source: src);
          return RepaintBoundary(
            child: _HistoryCard(
              item: item,
              isSelected: isSelected,
              isFavorite: isFav,
              unreadCount: unreadUpdates,
              onTap: () {
                if (_selectedSlugs.isNotEmpty) {
                  _toggleSelection(key);
                } else {
                  _openDetail(item);
                }
              },
              onLongPress: () {
                _toggleSelection(key);
              },
            ),
          );
        },
      );
    }

    final groups = _groupItems(filtered);
    final groupKeys = groups.keys.toList();

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        for (final label in groupKeys) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.58,
                crossAxisSpacing: 11,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, ii) {
                  final item = groups[label]![ii];
                  final key = _itemKey(item);
                  final isSelected = _selectedSlugs.contains(key);
                  final slug = item['slug'] as String? ?? '';
                  final src = item['source'] as String?;
                  final isFav = slug.isNotEmpty && LocalStorage.isFavorite(slug, source: src);
                  final unreadUpdates = LocalStorage.getMangaUnreadNewChaptersCount(slug, source: src);
                  return _HistoryCard(
                    item: item,
                    isSelected: isSelected,
                    isFavorite: isFav,
                    unreadCount: unreadUpdates,
                    onTap: () {
                      if (_selectedSlugs.isNotEmpty) {
                        _toggleSelection(key);
                      } else {
                        _openDetail(item);
                      }
                    },
                    onLongPress: () {
                      _toggleSelection(key);
                    },
                  );
                },
                childCount: groups[label]!.length,
              ),
            ),
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool? isFavorite;
  final int? unreadCount;

  const _HistoryCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.isFavorite,
    this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawTitle = item['title'] as String? ?? 'Tanpa Judul';
    final title = MangaItem.formatTitleFromSlug(rawTitle);
    final cover = item['cover'] as String?;
    final slug = item['slug'] as String? ?? '';
    final isFav = isFavorite ?? (slug.isNotEmpty && LocalStorage.isFavorite(slug, source: item['source'] as String?));
    final unreadUpdates = unreadCount ?? LocalStorage.getMangaUnreadNewChaptersCount(slug, source: item['source'] as String?);
    final percentVal = (item['percent'] as num?)?.toDouble();
    final page = (item['page'] as num?)?.toInt() ?? 1;
    final totalPages = (item['totalPages'] as num?)?.toInt() ?? 1;
    final double progress;
    if (percentVal != null && percentVal > 0) {
      var p = percentVal.clamp(0.0, 1.0);
      final totalChs = (item['totalChapters'] as num?)?.toInt() ?? 0;
      final chNum = (item['chapterNumber'] as num?)?.toInt() ?? 0;
      if (totalChs > 0 && chNum > 0) {
        final remaining = totalChs - chNum;
        if (remaining > 0) {
          if (p >= 0.999) {
            p = (chNum / totalChs);
          }
          if (remaining >= 2) {
            p = p.clamp(0.0, remaining >= 3 ? 0.97 : 0.98);
          } else {
            p = p.clamp(0.0, 0.99);
          }
        }
      }
      progress = p;
    } else if (totalPages > 0) {
      progress = (page / totalPages).clamp(0.0, 1.0);
    } else {
      progress = 0.0;
    }

    return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 13 / 18,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Cover
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    child: cover != null && cover.isNotEmpty
                        ? CachedCover(
                            imageUrl: cover,
                            source: item['source'] as String?,
                            slug: slug,
                            fit: BoxFit.cover,
                            placeholder: (ctx, url) =>
                                const MangaCardCoverShimmer())
                        : Container(
                            color: theme.colorScheme.surfaceContainerHigh,
                            child: const Center(
                                child: Icon(Icons.menu_book, size: 28))),
                  ),

                  // Top Left: Selection overlay (when in selection mode) or Favorite Heart badge
                  if (isSelected)
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppTheme.cardRadius),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2.5,
                          ),
                          borderRadius:
                              BorderRadius.circular(AppTheme.cardRadius),
                          color: theme.colorScheme.primary.withValues(alpha: 0.25),
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primary,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (unreadUpdates > 0 || isFav)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unreadUpdates > 0) ...[
                            NewChaptersBadge(count: unreadUpdates),
                            if (isFav) const SizedBox(width: 4),
                          ],
                          if (isFav) const FavoriteBadge(),
                        ],
                      ),
                    ),

                  // Top Right: Progress badge — matching Kotatsu Redo (Material 3 Expressive ProgressDrawable)
                  if (progress > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: ReadingProgressBadge(progress: progress),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 12.0,
                height: 1.2,
              ),
            ),
          ],
        ),
    );
  }
}

/// FAB-style "Lanjut" button — floats above navbar bottom-right
class _ContinueFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _ContinueFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(28),
      elevation: 4,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 26,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 10),
              Text(
                'Lanjut',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
