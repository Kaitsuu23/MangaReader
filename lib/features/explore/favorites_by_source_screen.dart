import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/models/manga_item.dart';
import '../../shared/models/manga_source.dart';
import '../../shared/widgets/cached_cover.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/widgets/manga_card_badges.dart';
import '../../shared/widgets/predictive_back_bottom_sheet.dart';
import '../details/manga_details_screen.dart';
import '../feed/feed_provider.dart';

class FavoritesBySourceScreen extends ConsumerStatefulWidget {
  const FavoritesBySourceScreen({super.key});

  @override
  ConsumerState<FavoritesBySourceScreen> createState() =>
      _FavoritesBySourceScreenState();
}

class _FavoritesBySourceScreenState
    extends ConsumerState<FavoritesBySourceScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  int _lastTabIndex = 0;

  String _listMode = 'grid'; // 'compact', 'details', 'grid'
  int _gridColumns = 3;
  String _sortOrder = 'added_desc';

  bool _filterUnread = false;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  final Map<int, ScrollController> _scrollControllers = {};

  ScrollController _scrollControllerFor(int index) {
    return _scrollControllers.putIfAbsent(index, () => ScrollController());
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _searchController.addListener(_onSearchChanged);
  }

  void _loadPreferences() {
    _listMode = LocalStorage.getFavoritesListMode();
    _gridColumns = LocalStorage.getFavoritesGridColumns();
    _sortOrder = LocalStorage.getFavoritesSort();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query != _searchQuery) {
      setState(() {
        _searchQuery = query;
      });
    }
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchQuery = '';
    });
    _searchFocusNode.unfocus();
  }

  void _ensureTabController(int count) {
    final validCount = count < 1 ? 1 : count;
    if (_tabController == null || _tabController!.length != validCount) {
      final oldIndex = _tabController?.index ?? 0;
      _tabController?.removeListener(_onTabChanged);
      _tabController?.dispose();
      _lastTabIndex = oldIndex.clamp(0, validCount - 1);
      _tabController = TabController(
        length: validCount,
        vsync: this,
        initialIndex: _lastTabIndex,
      );
      _tabController!.addListener(_onTabChanged);
    }
  }

  void _onTabChanged() {
    if (_tabController != null && _tabController!.index != _lastTabIndex) {
      _lastTabIndex = _tabController!.index;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _scrollControllers.clear();
    super.dispose();
  }

  bool _isItemUnread(Map<String, dynamic> item) {
    final slug = (item['slug'] as String? ?? '').trim();
    if (slug.isEmpty) return false;
    final source = (item['source'] as String?)?.trim();
    final latestChapter = item['latestChapter'] as String?;

    final unread =
        LocalStorage.getMangaUnreadNewChaptersCount(slug, source: source);
    if (unread > 0) return true;

    final progress = LocalStorage.getHistoryProgress(
      slug,
      source: source,
      latestChapter: latestChapter,
    );
    return progress < 0.999;
  }

  List<Map<String, dynamic>> _filterAndSortItems(
    List<Map<String, dynamic>> rawItems,
  ) {
    var items = List<Map<String, dynamic>>.from(rawItems);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = items.where((item) {
        final title = (item['title'] as String? ?? '').toLowerCase();
        final slug = (item['slug'] as String? ?? '').toLowerCase();
        return title.contains(q) || slug.contains(q);
      }).toList();
    }

    if (_filterUnread) {
      items = items.where(_isItemUnread).toList();
    }

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

  String _formatSourceName(
    String rawSource,
    Map<String, MangaSource> sourceMap,
  ) {
    if (rawSource.isEmpty || rawSource == 'all') {
      return 'Semua Sumber';
    }
    final match = sourceMap[rawSource.toLowerCase()];
    if (match != null && match.name.isNotEmpty) {
      return match.name;
    }
    // Title-case fallback
    if (rawSource.length <= 1) return rawSource.toUpperCase();
    return rawSource[0].toUpperCase() + rawSource.substring(1);
  }

  Widget _buildFilterChips(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildChip(
            label: 'Belum dibaca',
            icon: _filterUnread ? Icons.close : Icons.auto_stories_outlined,
            selected: _filterUnread,
            theme: theme,
            onTap: () => setState(() => _filterUnread = !_filterUnread),
          ),
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
                        Text(
                          'Mode daftar',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
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

  Widget _buildCompactItem(
    MangaItem item,
    Map<String, dynamic> data,
    Map<String, MangaSource> sourceMap,
  ) {
    final theme = Theme.of(context);
    final cat = data['category'] as String? ?? '';
    final chapter = data['latestChapter'] as String? ?? '';
    final progress = LocalStorage.getHistoryProgress(
      item.slug,
      source: item.source,
      latestChapter: chapter.isNotEmpty ? chapter : item.latestChapter,
    );
    final unreadUpdates = LocalStorage.getMangaUnreadNewChaptersCount(
      item.slug,
      source: item.source,
    );
    final sourceName = _formatSourceName(item.source ?? '', sourceMap);

    return InkWell(
      onTap: () => _openDetails(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 48,
                    height: 68,
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
                Positioned(
                  top: 2,
                  left: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (unreadUpdates > 0) ...[
                        NewChaptersBadge(
                          count: unreadUpdates,
                          height: 18,
                          fontSize: 8.5,
                        ),
                        const SizedBox(width: 2),
                      ],
                      const FavoriteBadge(size: 18, iconSize: 9),
                    ],
                  ),
                ),
                if (progress > 0)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: ReadingProgressBadge(
                      progress: progress,
                      size: 18,
                      strokeWidth: 2,
                    ),
                  ),
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          sourceName,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      if (cat.isNotEmpty && cat != 'Semua kesukaan') ...[
                        const SizedBox(width: 6),
                        Text(
                          '•  $cat',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      if (chapter.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '•  Ch. $chapter',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedItem(
    MangaItem item,
    Map<String, dynamic> data,
    Map<String, MangaSource> sourceMap,
  ) {
    final theme = Theme.of(context);
    final cat = data['category'] as String? ?? '';
    final chapter = data['latestChapter'] as String? ?? '';
    final progress = LocalStorage.getHistoryProgress(
      item.slug,
      source: item.source,
      latestChapter: chapter.isNotEmpty ? chapter : item.latestChapter,
    );
    final unreadUpdates = LocalStorage.getMangaUnreadNewChaptersCount(
      item.slug,
      source: item.source,
    );
    final sourceName = _formatSourceName(item.source ?? '', sourceMap);

    return InkWell(
      onTap: () => _openDetails(item),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
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
                          sourceName,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      if (cat.isNotEmpty && cat != 'Semua kesukaan')
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
                            cat,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (chapter.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Chapter $chapter',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourcesAsync = ref.watch(sourcesListProvider);
    final sourceMap = <String, MangaSource>{};
    for (final s in (sourcesAsync.asData?.value ?? [])) {
      sourceMap[s.id.toLowerCase()] = s;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_isSearching) {
              _stopSearch();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Cari di favorit...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              )
            : const Text(
                'Favorit per Sumber',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
        actions: [
          if (_isSearching)
            if (_searchQuery.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchController.clear();
                  _searchQuery = '';
                  setState(() {});
                },
              )
            else
              const SizedBox.shrink()
          else
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Cari',
              onPressed: _startSearch,
            ),
          PopupMenuButton<String>(
            tooltip: 'Urutkan',
            icon: const Icon(Icons.swap_vert_rounded),
            offset: const Offset(0, 40),
            initialValue: _sortOrder,
            onSelected: (val) {
              setState(() {
                _sortOrder = val;
              });
              LocalStorage.setFavoritesSort(_sortOrder);
              FeedUpdateNotifier.syncTrackedMangaConfig();
            },
            itemBuilder: (ctx) => [
              _buildSortMenuItem('added_desc', 'Terbaru ditambahkan'),
              _buildSortMenuItem('added_asc', 'Terlama ditambahkan'),
              _buildSortMenuItem('title_asc', 'Berdasarkan nama (A - Z)'),
              _buildSortMenuItem('title_desc', 'Berdasarkan nama (Z - A)'),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.view_agenda_outlined),
            tooltip: 'Mode daftar',
            onPressed: _showListModeSheet,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterChips(theme),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  LocalStorage.listenFavorites(),
                  LocalStorage.listenHistory(),
                  LocalStorage.listenFeed(),
                  LocalStorage.listenContentMode(),
                ]),
                builder: (context, _) {
                  final allFavs = LocalStorage.getFavorites();

                  // Extract all distinct sources
                  final distinctSources = <String>{};
                  for (final item in allFavs) {
                    final src = (item['source'] as String? ?? '').trim();
                    if (src.isNotEmpty) {
                      distinctSources.add(src.toLowerCase());
                    }
                  }
                  final sortedSources = distinctSources.toList()..sort();
                  final tabs = ['all', ...sortedSources];

                  if (_tabController == null ||
                      _tabController!.length != tabs.length) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _ensureTabController(tabs.length);
                    });
                  }

                  if (allFavs.isEmpty) {
                    return const EmptyView(
                      icon: Icons.favorite_border_rounded,
                      title: 'Belum Ada Favorit',
                      subtitle:
                          'Tandai komik favorit Anda untuk melihatnya di sini.',
                    );
                  }

                  List<Map<String, dynamic>> favsForSource(String src) {
                    if (src == 'all') return allFavs;
                    return allFavs.where((item) {
                      final itemSrc =
                          (item['source'] as String? ?? '').trim().toLowerCase();
                      return itemSrc == src;
                    }).toList();
                  }

                  final tabCtrl = _tabController;
                  if (tabCtrl == null || tabCtrl.length != tabs.length) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return Column(
                    children: [
                      TabBar(
                        controller: tabCtrl,
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
                        tabs: tabs.map((srcKey) {
                          final raw = favsForSource(srcKey);
                          final count = _filterUnread
                              ? raw.where(_isItemUnread).length
                              : raw.length;
                          final displayName =
                              _formatSourceName(srcKey, sourceMap);

                          return Tab(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(displayName),
                                if (count > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: theme
                                            .colorScheme.onSurfaceVariant,
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
                          controller: tabCtrl,
                          children: tabs.asMap().entries.map((entry) {
                            final tabIndex = entry.key;
                            final srcKey = entry.value;
                            final rawItems = favsForSource(srcKey);
                            final items = _filterAndSortItems(rawItems);

                            if (items.isEmpty) {
                              if (_searchQuery.isNotEmpty) {
                                return const EmptyView(
                                  icon: Icons.search_off_rounded,
                                  title: 'Tidak Ditemukan',
                                  subtitle:
                                      'Tidak ada komik yang cocok dengan pencarian.',
                                );
                              }
                              if (_filterUnread) {
                                return const EmptyView(
                                  icon: Icons.done_all_rounded,
                                  title: 'Semua Sudah Dibaca',
                                  subtitle:
                                      'Tidak ada komik yang belum dibaca pada sumber ini.',
                                );
                              }
                              return const EmptyView(
                                icon: Icons.collections_bookmark_outlined,
                                title: 'Belum Ada Komik',
                                subtitle:
                                    'Tidak ada komik favorit untuk sumber ini.',
                              );
                            }

                            return Column(
                              children: [
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
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _getSortLabel(_sortOrder),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: _listMode == 'compact'
                                      ? ListView.builder(
                                          controller:
                                              _scrollControllerFor(tabIndex),
                                          padding: const EdgeInsets.only(
                                            bottom: 32,
                                          ),
                                          itemCount: items.length,
                                          itemBuilder: (context, index) {
                                            final data = items[index];
                                            final mangaItem = MangaItem(
                                              title: data['title']
                                                      as String? ??
                                                  '',
                                              slug: data['slug']
                                                      as String? ??
                                                  '',
                                              cover: data['cover'] as String?,
                                              source:
                                                  data['source'] as String?,
                                              type: data['type'] as String?,
                                              latestChapter:
                                                  data['latestChapter']
                                                      as String?,
                                            );
                                            return _buildCompactItem(
                                              mangaItem,
                                              data,
                                              sourceMap,
                                            );
                                          },
                                        )
                                      : _listMode == 'details'
                                          ? ListView.builder(
                                              controller:
                                                  _scrollControllerFor(
                                                    tabIndex,
                                                  ),
                                              padding: const EdgeInsets.only(
                                                bottom: 32,
                                              ),
                                              itemCount: items.length,
                                              itemBuilder: (context, index) {
                                                final data = items[index];
                                                final mangaItem = MangaItem(
                                                  title: data['title']
                                                          as String? ??
                                                      '',
                                                  slug: data['slug']
                                                          as String? ??
                                                      '',
                                                  cover:
                                                      data['cover'] as String?,
                                                  source:
                                                      data['source'] as String?,
                                                  type:
                                                      data['type'] as String?,
                                                  latestChapter:
                                                      data['latestChapter']
                                                          as String?,
                                                );
                                                return _buildDetailedItem(
                                                  mangaItem,
                                                  data,
                                                  sourceMap,
                                                );
                                              },
                                            )
                                          : GridView.builder(
                                              controller:
                                                  _scrollControllerFor(
                                                    tabIndex,
                                                  ),
                                              padding: const EdgeInsets.fromLTRB(
                                                14,
                                                4,
                                                14,
                                                32,
                                              ),
                                              gridDelegate:
                                                  SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount:
                                                        _gridColumns,
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
                                                final slug = data['slug']
                                                        as String? ??
                                                    '';
                                                final mangaItem = MangaItem(
                                                  title: data['title']
                                                          as String? ??
                                                      '',
                                                  slug: slug,
                                                  cover:
                                                      data['cover'] as String?,
                                                  source:
                                                      data['source'] as String?,
                                                  type:
                                                      data['type'] as String?,
                                                  latestChapter:
                                                      data['latestChapter']
                                                          as String?,
                                                );
                                                final favSource =
                                                    (data['source'] as String?)
                                                        ?.trim();
                                                final effectiveFavSource =
                                                    (favSource != null &&
                                                            favSource
                                                                .isNotEmpty)
                                                        ? favSource
                                                        : null;
                                                final progress = LocalStorage
                                                    .getHistoryProgress(
                                                      slug,
                                                      source:
                                                          effectiveFavSource,
                                                      latestChapter:
                                                          (data['latestChapter']
                                                                          as String?)
                                                                      ?.isNotEmpty ==
                                                                  true
                                                              ? data['latestChapter']
                                                                  as String
                                                              : mangaItem
                                                                  .latestChapter,
                                                    );
                                                final unreadUpdates = LocalStorage
                                                    .getMangaUnreadNewChaptersCount(
                                                      slug,
                                                      source:
                                                          effectiveFavSource,
                                                    );
                                                return MangaCard(
                                                  item: mangaItem,
                                                  isFavorite: true,
                                                  readProgress: progress,
                                                  unreadCount: unreadUpdates,
                                                  onTap: () =>
                                                      _openDetails(mangaItem),
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
    );
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
}
