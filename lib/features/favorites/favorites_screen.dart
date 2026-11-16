import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../core/storage/local_storage.dart';
import '../../core/services/sync_service.dart';
import '../feed/feed_provider.dart';
import '../../shared/models/manga_item.dart';
import '../../shared/widgets/cached_cover.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/widgets/manga_card_badges.dart';
import '../details/manga_details_screen.dart';
import '../settings/settings_screen.dart';
import 'manage_categories_screen.dart';
import '../../shared/widgets/kotatsu_search_bar.dart';
import '../../shared/widgets/predictive_back_bottom_sheet.dart';
import '../content_mode/content_mode_dialog.dart';
import '../content_mode/transfer_manga_dialog.dart';
import '../../shared/models/content_mode.dart';

class FavoritesScreen extends StatefulWidget {
  final VoidCallback? onExploreTap;

  const FavoritesScreen({super.key, this.onExploreTap});

  @override
  State<FavoritesScreen> createState() => FavoritesScreenState();
}

class FavoritesScreenState extends State<FavoritesScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  String _listMode = 'grid'; // 'compact', 'details', 'grid'
  int _gridColumns = 3;
  String _sortOrder =
      'added_desc'; // 'added_desc', 'added_asc', 'title_asc', 'title_desc'

  // Selection mode state matching HistoryScreen
  bool _isSelectionMode = false;
  final Set<String> _selectedSlugs = {};

  // Scroll controllers keyed by tab index
  final Map<int, ScrollController> _scrollControllers = {};

  ScrollController _scrollControllerFor(int index) {
    return _scrollControllers.putIfAbsent(index, () => ScrollController());
  }

  /// Reset scroll position of all tabs to top, then switch to the first tab
  void resetToFirstTab() {
    if (!mounted) return;
    // Reset scroll position for all existing controllers
    for (final controller in _scrollControllers.values) {
      if (controller.hasClients && controller.offset > 0) {
        controller.jumpTo(0);
      }
    }
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _initTabController();
    LocalStorage.listenContentMode().addListener(_onContentModeChanged);
    if (LocalStorage.getActiveContentModeId() == ContentMode.defaultNormalId) {
      SyncService.healMissingFavorites();
    }
  }

  void _onContentModeChanged() {
    if (mounted) {
      _refreshCategories(preserveIndex: 0);
    }
  }

  List<String> _getTabs() {
    final all = LocalStorage.getFavoriteCategories();
    final visibleCustom = all.where((c) {
      final meta = LocalStorage.getCategoryDetails(c);
      return meta['showOnShelf'] != false;
    }).toList();

    final showAll = LocalStorage.isAllFavoritesVisible();
    if (showAll || visibleCustom.isEmpty) {
      return ['Semua kesukaan', ...visibleCustom];
    }
    return visibleCustom;
  }

  void _loadPreferences() {
    _listMode = LocalStorage.getFavoritesListMode();
    _gridColumns = LocalStorage.getFavoritesGridColumns();
    _sortOrder = LocalStorage.getFavoritesSort();
  }

  void _initTabController([int initialIndex = 0]) {
    final count = _getTabs().length;
    final validCount = count < 1 ? 1 : count;
    _lastTabIndex = initialIndex.clamp(0, validCount - 1);
    _tabController = TabController(
      length: validCount,
      vsync: this,
      initialIndex: _lastTabIndex,
    );
    _tabController.addListener(_onTabChanged);
  }

  int _lastTabIndex = 0;

  void _onTabChanged() {
    if (_tabController.index != _lastTabIndex) {
      _lastTabIndex = _tabController.index;
      if (mounted) setState(() {});
    }
  }

  void _ensureTabController(int tabsCount) {
    final validCount = tabsCount < 1 ? 1 : tabsCount;
    if (_tabController.length != validCount) {
      final oldController = _tabController;
      final oldIndex = oldController.index;
      oldController.removeListener(_onTabChanged);
      _lastTabIndex = oldIndex.clamp(0, validCount - 1);
      _tabController = TabController(
        length: validCount,
        vsync: this,
        initialIndex: _lastTabIndex,
      );
      _tabController.addListener(_onTabChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
      });
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    final tabs = _getTabs();
    _ensureTabController(tabs.length);
  }

  void _refreshCategories({int? preserveIndex}) {
    final oldIndex = preserveIndex ?? _tabController.index;
    setState(() {
      final newLength = _getTabs().length;
      final validCount = newLength < 1 ? 1 : newLength;
      final oldController = _tabController;
      oldController.removeListener(_onTabChanged);
      _lastTabIndex = oldIndex.clamp(0, validCount - 1);
      _tabController = TabController(
        length: validCount,
        vsync: this,
        initialIndex: _lastTabIndex,
      );
      _tabController.addListener(_onTabChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
      });
    });
  }

  @override
  void dispose() {
    LocalStorage.listenContentMode().removeListener(_onContentModeChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _scrollControllers.clear();
    super.dispose();
  }

  bool _isAllSelected(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return false;
    return items.every(
      (item) => _selectedSlugs.contains(item['slug'] as String? ?? ''),
    );
  }

  void _toggleSelectAll(List<Map<String, dynamic>> items) {
    setState(() {
      if (_isAllSelected(items)) {
        for (final item in items) {
          _selectedSlugs.remove(item['slug'] as String? ?? '');
        }
      } else {
        for (final item in items) {
          final slug = item['slug'] as String? ?? '';
          if (slug.isNotEmpty) _selectedSlugs.add(slug);
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
        _isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedSlugs.clear();
      _isSelectionMode = false;
    });
  }

  List<Map<String, dynamic>> _filterAndSortItems(
    List<Map<String, dynamic>> rawItems,
  ) {
    var items = List<Map<String, dynamic>>.from(rawItems);
    switch (_sortOrder) {
      case 'added_asc':
        items.sort((a, b) {
          final tA = a['addedAt'] as int? ?? 0;
          final tB = b['addedAt'] as int? ?? 0;
          return tA.compareTo(tB);
        });
        break;
      case 'title_asc':
        items.sort((a, b) {
          final tA = (a['title'] as String? ?? '').toLowerCase();
          final tB = (b['title'] as String? ?? '').toLowerCase();
          return tA.compareTo(tB);
        });
        break;
      case 'title_desc':
        items.sort((a, b) {
          final tA = (a['title'] as String? ?? '').toLowerCase();
          final tB = (b['title'] as String? ?? '').toLowerCase();
          return tB.compareTo(tA);
        });
        break;
      case 'added_desc':
      default:
        items.sort((a, b) {
          final tA = a['addedAt'] as int? ?? 0;
          final tB = b['addedAt'] as int? ?? 0;
          return tB.compareTo(tA);
        });
        break;
    }

    return items;
  }

  String _getSortLabel(String sort) {
    switch (sort) {
      case 'added_asc':
        return 'Terlama';
      case 'title_asc':
        return 'Judul (A - Z)';
      case 'title_desc':
        return 'Judul (Z - A)';
      case 'added_desc':
      default:
        return 'Terbaru';
    }
  }

  void _openDetails(MangaItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaDetailsScreen(
          slug: item.slug,
          source: item.source ?? LocalStorage.getActiveSource(),
          title: item.title,
          cover: item.cover,
          origin: 'favorites',
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<String?> _promptNewCategory(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Kategori Baru',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama Kategori',
            hintText: 'Misal: Manhwa, Favorit...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx, text.isNotEmpty ? text : null);
            },
            child: const Text('Buat'),
          ),
        ],
      ),
    );
  }

  void _showMoveCategoryDialog(BuildContext context) {
    if (_selectedSlugs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih setidaknya 1 komik terlebih dahulu'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final theme = Theme.of(context);
    final categories = LocalStorage.getFavoriteCategories();
    final tabs = _getTabs();
    final activeTab = tabs.isNotEmpty
        ? tabs[_tabController.index.clamp(0, tabs.length - 1)]
        : 'Semua kesukaan';
    String selectedCategory =
        (activeTab != 'Semua kesukaan' && categories.contains(activeTab))
        ? activeTab
        : (categories.isNotEmpty ? categories.first : '');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final allCats = LocalStorage.getFavoriteCategories();

            return AlertDialog(
              title: Text(
                'Pindahkan ke Kategori',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_selectedSlugs.length} komik dipilih',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (allCats.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Belum ada kategori tujuan. Silakan buat kategori baru terlebih dahulu.',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(ctx).height * 0.4,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: allCats.map((cat) {
                              final isSelected = selectedCategory == cat;
                              final count = LocalStorage.getFavorites(
                                category: cat,
                              ).length;
                              // ignore: deprecated_member_use
                              return RadioListTile<String>(
                                value: cat,
                                // ignore: deprecated_member_use
                                groupValue: selectedCategory,
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                title: Text(
                                  cat,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                secondary: count > 0
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          '$count',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      )
                                    : null,
                                // ignore: deprecated_member_use
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(
                                      () => selectedCategory = val,
                                    );
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    const Divider(height: 16),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text(
                        'Buat Kategori Baru',
                        style: TextStyle(fontSize: 13),
                      ),
                      onPressed: () async {
                        final newCat = await _promptNewCategory(ctx);
                        if (newCat != null && newCat.isNotEmpty) {
                          await LocalStorage.addFavoriteCategory(newCat);
                          setDialogState(() {
                            selectedCategory = newCat;
                          });
                          _refreshCategories();
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed:
                      (selectedCategory.isEmpty ||
                          !allCats.contains(selectedCategory))
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final toMove = Set<String>.from(_selectedSlugs);
                          _exitSelectionMode();

                          for (final rawKey in toMove) {
                            String slug = rawKey;
                            String? source;
                            if (rawKey.contains('::')) {
                              final parts = rawKey.split('::');
                              source = parts[0];
                              slug = parts.sublist(1).join('::');
                            }
                            await LocalStorage.updateFavoriteCategory(
                              slug,
                              selectedCategory,
                              source: source,
                            );
                          }

                          final currentModeId =
                              LocalStorage.getActiveContentModeId();
                          if (LocalStorage.isSyncEnabled(
                            modeId: currentModeId,
                          )) {
                            await SyncService.syncNow(modeId: currentModeId);
                          }

                          if (mounted && context.mounted) {
                            _refreshCategories();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${toMove.length} komik berhasil dipindahkan ke "$selectedCategory"',
                                ),
                                behavior: SnackBarBehavior.floating,
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
        );
      },
    );
  }

  void _confirmDeleteSelected(BuildContext context) {
    if (_selectedSlugs.isEmpty) return;
    final count = _selectedSlugs.length;
    final isSyncActive =
        LocalStorage.isSyncLoggedIn() && LocalStorage.isSyncEnabled();
    bool deleteFromServer = isSyncActive;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Hapus dari Favorit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count == 1
                    ? 'Hapus 1 manga dari daftar kesukaan?'
                    : 'Hapus $count manga dari daftar kesukaan?',
              ),
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
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final toDelete = Set<String>.from(_selectedSlugs);
                _exitSelectionMode();

                final currentModeId = LocalStorage.getActiveContentModeId();
                final deletedItems = <Map<String, dynamic>>[];
                for (final rawKey in toDelete) {
                  String slug = rawKey;
                  String? source;
                  if (rawKey.contains('::')) {
                    final parts = rawKey.split('::');
                    source = parts[0];
                    slug = parts.sublist(1).join('::');
                  }
                  final item = LocalStorage.getFavorite(
                    slug,
                    source: source,
                    modeId: currentModeId,
                  );
                  if (item != null) deletedItems.add(item);
                  await LocalStorage.removeFavorite(
                    slug,
                    source: source,
                    recordTombstone: deleteFromServer,
                    modeId: currentModeId,
                  );
                }
                if (deleteFromServer) {
                  await SyncService.syncNow(modeId: currentModeId);
                }
                unawaited(FeedUpdateNotifier.syncTrackedMangaConfig());
                if (mounted && context.mounted) {
                  _refreshCategories();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$count komik dihapus dari favorit'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 4),
                      action: SnackBarAction(
                        label: 'Urungkan',
                        onPressed: () async {
                          for (final item in deletedItems) {
                            await LocalStorage.saveFavorite(
                              slug: item['slug'] as String? ?? '',
                              title: item['title'] as String? ?? '',
                              cover: item['cover'] as String?,
                              source:
                                  item['source'] as String? ??
                                  LocalStorage.getActiveSource(
                                    modeId: currentModeId,
                                  ),
                              category: item['category'] as String?,
                              categories: (item['categories'] as List?)
                                  ?.map((e) => e.toString())
                                  .toList(),
                              type: item['type'] as String?,
                              latestChapter: item['latestChapter'] as String?,
                              modeId: currentModeId,
                            );
                          }
                          if (deleteFromServer) {
                            await SyncService.syncNow(modeId: currentModeId);
                          }
                          unawaited(
                            FeedUpdateNotifier.syncTrackedMangaConfig(),
                          );
                          if (mounted) _refreshCategories();
                        },
                      ),
                    ),
                  );
                }
              },
              child: const Text('Hapus'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _transferSelectedFavorites(BuildContext context) async {
    final toTransfer = _selectedSlugs.toList();
    if (toTransfer.isEmpty) return;
    final res = await showTransferMultipleMangaDialog(
      context,
      slugs: toTransfer,
    );
    if (res == true && mounted) {
      _exitSelectionMode();
      _refreshCategories();
    }
  }

  Widget _buildSelectionHeader(
    BuildContext context,
    List<Map<String, dynamic>> currentTabItems,
    ThemeData theme,
  ) {
    final allSelected = _isAllSelected(currentTabItems);

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
                allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                size: 22,
              ),
              tooltip: allSelected ? 'Batal pilih semua' : 'Pilih semua',
              onPressed: () => _toggleSelectAll(currentTabItems),
            ),
            IconButton(
              icon: const Icon(Icons.folder_outlined, size: 22),
              tooltip: 'Pindahkan kategori',
              onPressed: () => _showMoveCategoryDialog(context),
            ),
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded, size: 22),
              tooltip: 'Pindahkan ke mode lain',
              onPressed: () => _transferSelectedFavorites(context),
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 22,
                color: theme.colorScheme.error,
              ),
              tooltip: 'Hapus dari favorit',
              onPressed: () => _confirmDeleteSelected(context),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
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
            isSelected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            size: 18,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
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

  Widget _buildCompactItem(
    MangaItem item,
    Map<String, dynamic> data,
    bool isSelected,
  ) {
    final theme = Theme.of(context);
    final cat = data['category'] as String? ?? '';
    final chapter = data['latestChapter'] as String? ?? '';
    final progress = LocalStorage.getHistoryProgress(
      item.slug,
      source: item.source,
    );
    final unreadUpdates = LocalStorage.getMangaUnreadNewChaptersCount(
      item.slug,
      source: item.source,
    );
    final selectKey = (item.source?.isNotEmpty == true)
        ? '${item.source}::${item.slug}'
        : item.slug;

    return RepaintBoundary(
      child: InkWell(
        onTap: () {
          if (_isSelectionMode || _selectedSlugs.isNotEmpty) {
            _toggleSelection(selectKey);
          } else {
            _openDetails(item);
          }
        },
        onLongPress: () => _toggleSelection(selectKey),
        borderRadius: BorderRadius.circular(8),
        child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 44,
                    height: 44,
                    color: theme.colorScheme.surfaceContainerHigh,
                    child: item.cover != null && item.cover!.isNotEmpty
                        ? CachedCover(
                            imageUrl: item.cover!,
                            source: item.source,
                            slug: item.slug,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 150),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.broken_image, size: 20),
                          )
                        : const Icon(Icons.menu_book, size: 20),
                  ),
                ),
                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.35,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  )
                else ...[
                  if (unreadUpdates > 0)
                    Positioned(
                      top: 2,
                      left: 2,
                      child: NewChaptersBadge(
                        count: unreadUpdates,
                        height: 18,
                        fontSize: 8.5,
                      ),
                    ),
                  if (progress > 0)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: ReadingProgressBadge(
                        progress: progress,
                        size: 18,
                        strokeWidth: 2.2,
                      ),
                    ),
                ],
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w600,
                      color: isSelected ? theme.colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (item.source != null) item.source!.toUpperCase(),
                      if (cat.isNotEmpty && cat != 'Semua kesukaan') cat,
                      if (chapter.isNotEmpty) 'Ch. $chapter',
                    ].join(' • ' ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildDetailedItem(
    MangaItem item,
    Map<String, dynamic> data,
    bool isSelected,
  ) {
    final theme = Theme.of(context);
    final cat = data['category'] as String? ?? '';
    final chapter = data['latestChapter'] as String? ?? '';
    final progress = LocalStorage.getHistoryProgress(
      item.slug,
      source: item.source,
    );
    final unreadUpdates = LocalStorage.getMangaUnreadNewChaptersCount(
      item.slug,
      source: item.source,
    );
    final selectKey = (item.source?.isNotEmpty == true)
        ? '${item.source}::${item.slug}'
        : item.slug;

    return RepaintBoundary(
      child: InkWell(
        onTap: () {
          if (_isSelectionMode || _selectedSlugs.isNotEmpty) {
            _toggleSelection(selectKey);
          } else {
            _openDetails(item);
          }
        },
        onLongPress: () => _toggleSelection(selectKey),
        borderRadius: BorderRadius.circular(8),
        child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 78,
                    height: 114,
                    color: theme.colorScheme.surfaceContainerHigh,
                    child: item.cover != null && item.cover!.isNotEmpty
                        ? CachedCover(
                            imageUrl: item.cover!,
                            source: item.source,
                            slug: item.slug,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 150),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.broken_image, size: 24),
                          )
                        : const Icon(Icons.menu_book, size: 24),
                  ),
                ),
                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
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
                else ...[
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (unreadUpdates > 0) ...[
                          NewChaptersBadge(
                            count: unreadUpdates,
                            height: 22,
                            fontSize: 9.5,
                          ),
                          const SizedBox(width: 3),
                        ],
                        const FavoriteBadge(size: 22, iconSize: 11),
                      ],
                    ),
                  ),
                  if (progress > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: ReadingProgressBadge(
                        progress: progress,
                        size: 22,
                        strokeWidth: 2.4,
                      ),
                    ),
                ],
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    item.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                      color: isSelected ? theme.colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (cat.isNotEmpty && cat != 'Semua kesukaan')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      if (item.source != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.source!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (chapter.isNotEmpty)
                    Text(
                      'Chapter $chapter',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.5,
                ),
              ),
              child: Icon(
                Icons.favorite_border_rounded,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Belum Ada yang Disukai',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Manga yang Anda favoritkan akan tersimpan di sini agar mudah dibaca kembali.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 20),
            if (widget.onExploreTap != null)
              FilledButton.tonalIcon(
                onPressed: widget.onExploreTap,
                icon: const Icon(Icons.explore_rounded, size: 18),
                label: const Text('Jelajah Komik'),
              ),
          ],
        ),
      ),
    );
  }

  void _showListModeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      sheetAnimationStyle: AnimationStyle(
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 250),
      ),
      builder: (ctx) {
        final theme = Theme.of(context);
        return PredictiveBackBottomSheet(
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top handle
                        Center(
                          child: Container(
                            width: 32,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // "Mode daftar" title
                        Text(
                          'Mode daftar',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 3-Segmented Toggle Buttons: Padat, Detail, Kisi
                        Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(36),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Row(
                            children: [
                              _buildModeSegment(
                                title: 'Padat',
                                icon: Icons.format_list_bulleted_rounded,
                                mode: 'compact',
                                isFirst: true,
                                setSheetState: setSheetState,
                              ),
                              _buildModeSegment(
                                title: 'Detail',
                                icon: Icons.view_agenda_outlined,
                                mode: 'details',
                                setSheetState: setSheetState,
                              ),
                              _buildModeSegment(
                                title: 'Kisi',
                                icon: Icons.grid_view_rounded,
                                mode: 'grid',
                                isLast: true,
                                setSheetState: setSheetState,
                              ),
                            ],
                          ),
                        ),

                        // "Ukuran kisi" (visible when mode == 'grid')
                        if (_listMode == 'grid') ...[
                          const SizedBox(height: 20),
                          Text(
                            'Ukuran kisi',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 14,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 10,
                              ),
                            ),
                            child: Slider(
                              value: _gridColumns.toDouble(),
                              min: 2,
                              max: 4,
                              divisions: 2,
                              onChanged: (val) {
                                final newCols = val.round();
                                setSheetState(() {
                                  _gridColumns = newCols;
                                });
                                setState(() {
                                  _gridColumns = newCols;
                                });
                                LocalStorage.setFavoritesGridColumns(newCols);
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildModeSegment({
    required String title,
    required IconData icon,
    required String mode,
    bool isFirst = false,
    bool isLast = false,
    required StateSetter setSheetState,
  }) {
    final isSelected = _listMode == mode;
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        onTap: () {
          setSheetState(() {
            _listMode = mode;
          });
          setState(() {
            _listMode = mode;
          });
          LocalStorage.setFavoritesListMode(mode);
        },
        child: Container(
          height: double.infinity,
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isFirst ? const Radius.circular(36) : Radius.zero,
              right: isLast ? const Radius.circular(36) : Radius.zero,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allCategoryTabs = _getTabs();
    _ensureTabController(allCategoryTabs.length);

    final isInSelection = _isSelectionMode || _selectedSlugs.isNotEmpty;

    return PopScope(
      canPop: !isInSelection,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (isInSelection)
                Builder(
                  builder: (ctx) {
                    final currentTab = allCategoryTabs.isNotEmpty
                        ? allCategoryTabs[_tabController.index.clamp(
                            0,
                            allCategoryTabs.length - 1,
                          )]
                        : 'Semua kesukaan';
                    final currentTabItems = LocalStorage.getFavorites(
                      category: currentTab,
                    );
                    return _buildSelectionHeader(
                      context,
                      currentTabItems,
                      theme,
                    );
                  },
                )
              else
                KotatsuSearchBar(
                  trailingMenu: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    offset: const Offset(0, 40),
                    constraints: const BoxConstraints(
                      minWidth: 160,
                      maxWidth: 200,
                    ),
                    onSelected: (val) async {
                      if (val == 'select') {
                        setState(() {
                          _isSelectionMode = true;
                        });
                      } else if (val == 'list_mode') {
                        _showListModeSheet();
                      } else if (val == 'content_mode') {
                        await showContentModeDialog(context);
                        _refreshCategories();
                      } else if (val == 'categories') {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ManageCategoriesScreen(),
                          ),
                        );
                        _refreshCategories();
                      } else if (val == 'settings') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'list_mode',
                        height: 40,
                        child: Row(
                          children: [
                            Icon(Icons.view_agenda_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Opsi daftar', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
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
                        value: 'select',
                        height: 40,
                        child: Row(
                          children: [
                            Icon(Icons.checklist_rounded, size: 18),
                            SizedBox(width: 10),
                            Text('Pilih komik', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'categories',
                        height: 40,
                        child: Row(
                          children: [
                            Icon(Icons.category_outlined, size: 18),
                            SizedBox(width: 10),
                            Text(
                              'Kategori disukai',
                              style: TextStyle(fontSize: 13),
                            ),
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

              // Kotatsu Category Tabs & Content
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    LocalStorage.listenFavorites(),
                    LocalStorage.listenHistory(),
                    LocalStorage.listenContentMode(),
                  ]),
                  builder: (context, _) {
                    final tabs = _getTabs();
                    _ensureTabController(tabs.length);
                    final allFavs = LocalStorage.getFavorites();

                    List<Map<String, dynamic>> favsForCat(String cat) {
                      if (cat == 'Semua' || cat == 'Semua kesukaan') {
                        return allFavs;
                      }
                      return allFavs.where((item) {
                        final itemCategories = (item['categories'] is List)
                            ? List<String>.from(item['categories'] as List)
                            : (item['category'] != null ? [item['category'] as String] : <String>[]);
                        return itemCategories.contains(cat) || item['category'] == cat;
                      }).toList();
                    }

                    return Column(
                      children: [
                        TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontWeight: FontWeight.normal,
                            fontSize: 13.5,
                          ),
                          tabs: tabs.map((cat) {
                            final count = favsForCat(cat).length;
                            return Tab(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(cat),
                                  if (count > 0) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$count',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: tabs.asMap().entries.map((entry) {
                              final tabIndex = entry.key;
                              final cat = entry.value;
                              final rawItems = favsForCat(cat);
                              final items = _filterAndSortItems(rawItems);

                              if (items.isEmpty) {
                                return _buildEmptyState();
                              }

                              return Column(
                                children: [
                                  // Kotatsu Subheader Toolbar (Total items count & Sort selector & List mode selector)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          '${items.length} komik',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                        const Spacer(),
                                        // Sort Popup Menu
                                        PopupMenuButton<String>(
                                          tooltip: 'Urutkan',
                                          offset: const Offset(0, 36),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          initialValue: _sortOrder,
                                          onSelected: (val) {
                                            setState(() {
                                              _sortOrder = val;
                                            });
                                            LocalStorage.setFavoritesSort(
                                              _sortOrder,
                                            );
                                            FeedUpdateNotifier.syncTrackedMangaConfig();
                                          },
                                          itemBuilder: (ctx) => [
                                            _buildSortMenuItem(
                                              'added_desc',
                                              'Terbaru ditambahkan',
                                            ),
                                            _buildSortMenuItem(
                                              'added_asc',
                                              'Terlama ditambahkan',
                                            ),
                                            _buildSortMenuItem(
                                              'title_asc',
                                              'Berdasarkan nama (A - Z)',
                                            ),
                                            _buildSortMenuItem(
                                              'title_desc',
                                              'Berdasarkan nama (Z - A)',
                                            ),
                                          ],
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 4,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.swap_vert_rounded,
                                                  size: 17,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _getSortLabel(_sortOrder),
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Opsi Daftar (List Mode Sheet)
                                        Tooltip(
                                          message: 'Opsi daftar',
                                          child: InkWell(
                                            onTap: _showListModeSheet,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(
                                                _listMode == 'compact'
                                                    ? Icons
                                                          .format_list_bulleted_rounded
                                                    : (_listMode == 'details'
                                                          ? Icons
                                                                .view_agenda_outlined
                                                          : Icons
                                                                .grid_view_rounded),
                                                size: 18,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Manga List / Grid based on _listMode
                                  Expanded(
                                    child: _listMode == 'grid'
                                        ? GridView.builder(
                                            controller: _scrollControllerFor(
                                              tabIndex,
                                            ),
                                            padding: const EdgeInsets.only(
                                              left: 14,
                                              right: 14,
                                              top: 4,
                                              bottom: 96,
                                            ),
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: _gridColumns,
                                                  childAspectRatio:
                                                      _gridColumns == 2
                                                      ? 0.61
                                                      : (_gridColumns == 4
                                                            ? 0.54
                                                            : 0.58),
                                                  crossAxisSpacing: 11,
                                                  mainAxisSpacing: 12,
                                                ),
                                            itemCount: items.length,
                                            itemBuilder: (context, index) {
                                              final data = items[index];
                                              final slug =
                                                  data['slug'] as String? ?? '';
                                              final mangaItem = MangaItem(
                                                title:
                                                    data['title'] as String? ??
                                                    '',
                                                slug: slug,
                                                cover: data['cover'] as String?,
                                                source:
                                                    data['source'] as String?,
                                                type: data['type'] as String?,
                                                latestChapter:
                                                    data['latestChapter']
                                                        as String?,
                                              );
                                              final selectKey =
                                                  (data['source'] as String?)
                                                          ?.isNotEmpty ==
                                                      true
                                                  ? '${data['source']}::$slug'
                                                  : slug;
                                              final isSelected =
                                                  _selectedSlugs.contains(
                                                    selectKey,
                                                  ) ||
                                                  _selectedSlugs.contains(slug);
                                              final favSource =
                                                  (data['source'] as String?)
                                                      ?.trim();
                                              final effectiveFavSource =
                                                  (favSource != null &&
                                                      favSource.isNotEmpty)
                                                  ? favSource
                                                  : null;
                                              const isFav = true;
                                              final progress =
                                                  LocalStorage.getHistoryProgress(
                                                    slug,
                                                    source: effectiveFavSource,
                                                  );
                                              final unreadUpdates =
                                                  LocalStorage.getMangaUnreadNewChaptersCount(
                                                    slug,
                                                    source: effectiveFavSource,
                                                  );
                                              return MangaCard(
                                                item: mangaItem,
                                                isSelected: isSelected,
                                                isFavorite: isFav,
                                                readProgress: progress,
                                                unreadCount: unreadUpdates,
                                                onTap: () {
                                                  if (_isSelectionMode ||
                                                      _selectedSlugs
                                                          .isNotEmpty) {
                                                    _toggleSelection(selectKey);
                                                  } else {
                                                    _openDetails(mangaItem);
                                                  }
                                                },
                                                onLongPress: () =>
                                                    _toggleSelection(selectKey),
                                              );
                                            },
                                          )
                                        : _listMode == 'compact'
                                        ? ListView.builder(
                                            controller: _scrollControllerFor(
                                              tabIndex,
                                            ),
                                            padding: const EdgeInsets.only(
                                              left: 14,
                                              right: 14,
                                              top: 4,
                                              bottom: 96,
                                            ),
                                            prototypeItem: _buildCompactItem(
                                              MangaItem(
                                                title: 'Prototype',
                                                slug: '__proto__',
                                                source: 'src',
                                              ),
                                              <String, dynamic>{},
                                              false,
                                            ),
                                            itemCount: items.length,
                                            itemBuilder: (context, index) {
                                              final data = items[index];
                                              final slug =
                                                  data['slug'] as String? ?? '';
                                              final mangaItem = MangaItem(
                                                title:
                                                    data['title'] as String? ??
                                                    '',
                                                slug: slug,
                                                cover: data['cover'] as String?,
                                                source:
                                                    data['source'] as String?,
                                                type: data['type'] as String?,
                                                latestChapter:
                                                    data['latestChapter']
                                                        as String?,
                                              );
                                              final selectKey =
                                                  (data['source'] as String?)
                                                          ?.isNotEmpty ==
                                                      true
                                                  ? '${data['source']}::$slug'
                                                  : slug;
                                              final isSelected =
                                                  _selectedSlugs.contains(
                                                    selectKey,
                                                  ) ||
                                                  _selectedSlugs.contains(slug);
                                              return _buildCompactItem(
                                                mangaItem,
                                                data,
                                                isSelected,
                                              );
                                            },
                                          )
                                        : ListView.builder(
                                            controller: _scrollControllerFor(
                                              tabIndex,
                                            ),
                                            padding: const EdgeInsets.only(
                                              left: 14,
                                              right: 14,
                                              top: 4,
                                              bottom: 96,
                                            ),
                                            itemCount: items.length,
                                            itemBuilder: (context, index) {
                                              final data = items[index];
                                              final slug =
                                                  data['slug'] as String? ?? '';
                                              final mangaItem = MangaItem(
                                                title:
                                                    data['title'] as String? ??
                                                    '',
                                                slug: slug,
                                                cover: data['cover'] as String?,
                                                source:
                                                    data['source'] as String?,
                                                type: data['type'] as String?,
                                                latestChapter:
                                                    data['latestChapter']
                                                        as String?,
                                              );
                                              final selectKey =
                                                  (data['source'] as String?)
                                                          ?.isNotEmpty ==
                                                      true
                                                  ? '${data['source']}::$slug'
                                                  : slug;
                                              final isSelected =
                                                  _selectedSlugs.contains(
                                                    selectKey,
                                                  ) ||
                                                  _selectedSlugs.contains(slug);
                                              return _buildDetailedItem(
                                                mangaItem,
                                                data,
                                                isSelected,
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
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
