import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/cached_cover.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/error_view.dart';
import 'source_view_screen.dart';
import 'favorites_by_source_screen.dart';
import '../settings/settings_screen.dart';
import '../../shared/widgets/kotatsu_search_bar.dart';
import '../content_mode/content_mode_dialog.dart';
import '../details/manga_details_screen.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/models/manga_item.dart';
import '../../core/services/network_service.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  Future<List<MangaItem>>? _suggestionsFuture;
  bool _lastSuggestionsState = false;
  String _listMode = 'compact';
  int _gridColumns = 4;

  @override
  void initState() {
    super.initState();
    _listMode = LocalStorage.getExploreSourceListMode();
    _gridColumns = LocalStorage.getExploreSourceGridColumns();
    _lastSuggestionsState = LocalStorage.isSuggestionsEnabled();
    _loadSuggestions();
  }

  Future<void> _handleRefresh() async {
    if (!NetworkService.isConnected) {
      NetworkService.showNoInternetSnackBar(context, onRetry: _handleRefresh);
    }
    ref.invalidate(sourcesListProvider);
    _loadSuggestions();
    try {
      await ref.read(sourcesListProvider.future);
    } catch (e) {
      if (mounted && NetworkService.isNetworkError(e)) {
        NetworkService.showNoInternetSnackBar(context, onRetry: _handleRefresh);
      }
    }
    if (mounted) setState(() {});
  }

  void _loadSuggestions() {
    if (LocalStorage.isSuggestionsEnabled()) {
      final activeSrc = LocalStorage.getActiveSource();
      final api = ref.read(parserChannelProvider);
      _suggestionsFuture = api
          .getList(activeSrc, sort: 'popular', page: 1)
          .then((res) {
            return res.data.take(8).toList();
          })
          .catchError((_) => <MangaItem>[]);
    } else {
      _suggestionsFuture = null;
    }
  }

  Widget _buildSuggestionsSection(ThemeData theme) {
    if (!LocalStorage.isSuggestionsEnabled() || _suggestionsFuture == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<MangaItem>>(
      future: _suggestionsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final items = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Saran Bacaan',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 185,
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  LocalStorage.listenFavorites(),
                  LocalStorage.listenHistory(),
                  LocalStorage.listenFeed(),
                ]),
                builder: (context, _) {
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return SizedBox(
                        width: 100,
                        child: MangaCard(
                          item: item,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MangaDetailsScreen(
                                  slug: item.slug,
                                  source: LocalStorage.getActiveSource(),
                                  title: item.title,
                                  cover: item.cover,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFavicon(
    dynamic src,
    String initial,
    Color color, {
    double size = 38,
    double borderRadius = 6,
    double fontSize = 16,
  }) {
    if (src.icon != null && (src.icon as String).isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedCover(
          imageUrl: src.icon as String,
          fit: BoxFit.contain,
          placeholder: (context, url) => const SizedBox.shrink(),
          errorWidget: (context, url, error) =>
              _buildFallbackIcon(initial, color, borderRadius, fontSize),
        ),
      );
    }
    return _buildFallbackIcon(initial, color, borderRadius, fontSize);
  }

  Widget _buildFallbackIcon(
    String initial,
    Color color,
    double borderRadius,
    double fontSize,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  void _openSource(dynamic src) {
    LocalStorage.setActiveSource(src.id as String);
    ref.read(activeSourceProvider.notifier).setSource(src.id as String);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SourceViewScreen(
          sourceId: src.id as String,
          sourceName: src.name as String,
        ),
      ),
    );
  }

  Future<void> _togglePinSource(dynamic src, bool isPinned) async {
    await LocalStorage.togglePinSource(src.id as String);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPinned
                ? '${src.name} batal disematkan'
                : '${src.name} disematkan ke atas',
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  PopupMenuItem<String> _buildListModeMenuItem(String value, String label) {
    final bool isSelected;
    if (value.startsWith('grid_')) {
      final col = int.tryParse(value.split('_').last) ?? 4;
      isSelected = _listMode == 'grid' && _gridColumns == col;
    } else {
      isSelected = _listMode == value;
    }
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
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getListModeIcon() {
    switch (_listMode) {
      case 'grid':
        return Icons.grid_view_rounded;
      case 'details':
        return Icons.view_agenda_outlined;
      case 'compact':
      default:
        return Icons.format_list_bulleted_rounded;
    }
  }

  String _getListModeLabel() {
    switch (_listMode) {
      case 'grid':
        return 'Kisi ($_gridColumns)';
      case 'details':
        return 'Detail';
      case 'compact':
      default:
        return 'Padat';
    }
  }

  Color _getSourceColor(String id) {
    switch (id.toLowerCase()) {
      case 'softkomik':
        return const Color(0xFF6750A4);
      case 'komiku':
        return const Color(0xFF0072E5);
      case 'hwago':
        return const Color(0xFFD9383A);
      case 'doujindesu':
        return const Color(0xFF2E7D32);
      case 'shinigami':
        return const Color(0xFFE91E63);
      case 'kiryuu':
        return const Color(0xFFE65100);
      case 'komiktap':
        return const Color(0xFF8E24AA);
      case 'westmanga':
        return const Color(0xFFE53935);
      case 'komikindo':
        return const Color(0xFF00897B);
      case 'apkomik':
        return const Color(0xFFF57C00);
      case 'bacakomik':
        return const Color(0xFF1E88E5);
      case 'lumos':
        return const Color(0xFF673AB7);
      case 'holotoon':
        return const Color(0xFF00ACC1);
      case 'pixhentai':
        return const Color(0xFFD81B60);
      case 'ikiru':
        return const Color(0xFF3F51B5);
      case 'hentaicrot':
        return const Color(0xFFC2185B);
      case 'voratoon':
        return const Color(0xFF6200EE);
      case 'luvyaa':
        return const Color(0xFFE91E63);
      case 'crotpedia':
        return const Color(0xFF880E4F);
      case 'mihentai':
        return const Color(0xFFAD1457);
      case 'maid':
        return const Color(0xFFEC407A);
      case 'natsu':
        return const Color(0xFFFF5722);
      case 'komikremaja':
        return const Color(0xFF00897B);
      case 'shirodoujin':
        return const Color(0xFF5E35B1);
      case 'komikapk':
        return const Color(0xFF26A69A);
      case 'mangapill':
        return const Color(0xFFE91E63);
      case 'fanfox':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF575E71);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourcesAsync = ref.watch(sourcesListProvider);
    ref.watch(activeContentModeProvider);

    ref.listen(activeContentModeProvider, (prev, next) {
      if (prev?.id != next.id) {
        _loadSuggestions();
      }
    });

    final currentSuggestionsState = LocalStorage.isSuggestionsEnabled();
    if (currentSuggestionsState != _lastSuggestionsState) {
      _lastSuggestionsState = currentSuggestionsState;
      _loadSuggestions();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Search Bar matching Kotatsu fragment_explore / actionbar
            KotatsuSearchBar(
              trailingMenu: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                offset: const Offset(0, 40),
                constraints: const BoxConstraints(minWidth: 160, maxWidth: 200),
                onSelected: (val) {
                  if (val == 'favorites_by_source') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FavoritesBySourceScreen(),
                      ),
                    );
                  } else if (val == 'content_mode') {
                    showContentModeDialog(context, ref);
                  } else if (val == 'refresh') {
                    if (_refreshIndicatorKey.currentState != null) {
                      _refreshIndicatorKey.currentState!.show();
                    } else {
                      _handleRefresh();
                    }
                  } else if (val == 'settings') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ).then((_) {
                      if (mounted) setState(() {});
                    });
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'favorites_by_source',
                    height: 40,
                    child: Row(
                      children: [
                        Icon(Icons.collections_bookmark_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Favorit per Sumber', style: TextStyle(fontSize: 13)),
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
                    value: 'refresh',
                    height: 40,
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Segarkan', style: TextStyle(fontSize: 13)),
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

            // Main Scrollable Content wrapped in RefreshIndicator from the top
            Expanded(
              child: RefreshIndicator(
                key: _refreshIndicatorKey,
                onRefresh: _handleRefresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Suggestions Carousel matching Kotatsu ExploreViewModel suggestions
                    SliverToBoxAdapter(child: _buildSuggestionsSection(theme)),

                    // Source List Section Header matching Kotatsu ItemExploreSourceList
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Sumber Manga',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Opsi daftar',
                              offset: const Offset(0, 36),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              initialValue: _listMode == 'grid'
                                  ? 'grid_$_gridColumns'
                                  : _listMode,
                              onSelected: (val) {
                                setState(() {
                                  if (val.startsWith('grid')) {
                                    _listMode = 'grid';
                                    final col =
                                        int.tryParse(val.split('_').last) ?? 4;
                                    _gridColumns = col;
                                    LocalStorage.setExploreSourceGridColumns(
                                      col,
                                    );
                                  } else {
                                    _listMode = val;
                                  }
                                });
                                LocalStorage.setExploreSourceListMode(
                                  _listMode,
                                );
                              },
                              itemBuilder: (ctx) => [
                                _buildListModeMenuItem('compact', 'Padat'),
                                _buildListModeMenuItem('details', 'Detail'),
                                _buildListModeMenuItem(
                                  'grid_2',
                                  'Kisi (2 kolom)',
                                ),
                                _buildListModeMenuItem(
                                  'grid_3',
                                  'Kisi (3 kolom)',
                                ),
                                _buildListModeMenuItem(
                                  'grid_4',
                                  'Kisi (4 kolom)',
                                ),
                                _buildListModeMenuItem(
                                  'grid_5',
                                  'Kisi (5 kolom)',
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
                                      _getListModeIcon(),
                                      size: 17,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _getListModeLabel(),
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
                    ),

                    // Sources List or State Views
                    ...sourcesAsync.when(
                      data: (sources) {
                        final displaySources = List.of(sources)
                            .where((s) => LocalStorage.isSourceEnabled(s.id))
                            .toList();

                        // Sort pinned sources to the top, matching Kotatsu behavior
                        final pinnedList = LocalStorage.getPinnedSources();
                        displaySources.sort((a, b) {
                          final aPinned = pinnedList.contains(a.id);
                          final bPinned = pinnedList.contains(b.id);
                          if (aPinned && !bPinned) return -1;
                          if (!aPinned && bPinned) return 1;
                          return 0;
                        });

                        if (displaySources.isEmpty) {
                          return [
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.only(top: 40),
                                child: EmptyView(
                                  icon: Icons.source_outlined,
                                  title: 'Sumber Tidak Ditemukan',
                                  subtitle: 'Tidak ada sumber manga yang cocok dengan filter.',
                                ),
                              ),
                            ),
                          ];
                        }

                        // Grid Mode (matching Kotatsu item_explore_source_grid.xml)
                        if (_listMode == 'grid') {
                          final double aspectRatio;
                          final double iconSize;
                          final double fontSize;
                          final double titleFontSize;
                          final double crossSpacing;
                          final double mainSpacing;
                          final double iconRadius;

                          if (_gridColumns == 2) {
                            aspectRatio = 1.45;
                            iconSize = 58.0;
                            fontSize = 22.0;
                            titleFontSize = 13.0;
                            crossSpacing = 8.0;
                            mainSpacing = 6.0;
                            iconRadius = 12.0;
                          } else if (_gridColumns == 3) {
                            aspectRatio = 1.25;
                            iconSize = 48.0;
                            fontSize = 18.0;
                            titleFontSize = 12.0;
                            crossSpacing = 6.0;
                            mainSpacing = 4.0;
                            iconRadius = 10.0;
                          } else if (_gridColumns == 5) {
                            aspectRatio = 1.05;
                            iconSize = 36.0;
                            fontSize = 14.0;
                            titleFontSize = 10.5;
                            crossSpacing = 4.0;
                            mainSpacing = 2.0;
                            iconRadius = 7.0;
                          } else {
                            // 4 columns (default)
                            aspectRatio = 1.15;
                            iconSize = 42.0;
                            fontSize = 16.0;
                            titleFontSize = 11.0;
                            crossSpacing = 4.0;
                            mainSpacing = 4.0;
                            iconRadius = 8.0;
                          }

                          return [
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 2, 12, 96),
                              sliver: SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: _gridColumns,
                                      childAspectRatio: aspectRatio,
                                      crossAxisSpacing: crossSpacing,
                                      mainAxisSpacing: mainSpacing,
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final src = displaySources[index];
                                  final isPinned = pinnedList.contains(src.id);
                                  final initial = src.name.isNotEmpty
                                      ? src.name[0].toUpperCase()
                                      : 'M';
                                  final color = _getSourceColor(src.id);

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => _openSource(src),
                                      onLongPress: () =>
                                          _togglePinSource(src, isPinned),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                          vertical: 4,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: iconSize,
                                              height: iconSize,
                                              child: _buildFavicon(
                                                src,
                                                initial,
                                                color,
                                                size: iconSize,
                                                borderRadius: iconRadius,
                                                fontSize: fontSize,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                if (isPinned) ...[
                                                  const Icon(
                                                    Icons
                                                        .local_fire_department_rounded,
                                                    size: 12,
                                                    color: Color(0xFFFF6D00),
                                                  ),
                                                  const SizedBox(width: 2),
                                                ],
                                                Flexible(
                                                  child: Text(
                                                    src.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: titleFontSize,
                                                      height: 1.15,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (_gridColumns == 2) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Manga, Indonesia',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.6),
                                                  fontSize: 11,
                                                  height: 1.2,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }, childCount: displaySources.length),
                              ),
                            ),
                          ];
                        }

                        // Detail List Mode
                        if (_listMode == 'details') {
                          return [
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(14, 2, 14, 96),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  final src = displaySources[index];
                                  final isPinned = pinnedList.contains(src.id);
                                  final initial = src.name.isNotEmpty
                                      ? src.name[0].toUpperCase()
                                      : 'M';
                                  final color = _getSourceColor(src.id);

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Material(
                                      color:
                                          theme.colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(12),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () => _openSource(src),
                                        onLongPress: () =>
                                            _togglePinSource(src, isPinned),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 44,
                                                height: 44,
                                                child: _buildFavicon(
                                                  src,
                                                  initial,
                                                  color,
                                                  size: 44,
                                                  borderRadius: 8,
                                                  fontSize: 18,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        if (isPinned) ...[
                                                          const Icon(
                                                            Icons
                                                                .local_fire_department_rounded,
                                                            size: 15,
                                                            color: Color(
                                                              0xFFFF6D00,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                        ],
                                                        Expanded(
                                                          child: Text(
                                                            src.name,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize:
                                                                      14.5,
                                                                  height: 1.2,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Row(
                                                      children: [
                                                        Text(
                                                          'Manga, Indonesia',
                                                          style: TextStyle(
                                                            color: theme
                                                                .colorScheme
                                                                .onSurface
                                                                .withValues(
                                                                  alpha: 0.6,
                                                                ),
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        if (isPinned) ...[
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 1,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFFFF6D00,
                                                                  ).withValues(
                                                                    alpha: 0.15,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                            child: const Text(
                                                              'Disematkan',
                                                              style: TextStyle(
                                                                color: Color(
                                                                  0xFFFF6D00,
                                                                ),
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 20,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.4),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }, childCount: displaySources.length),
                              ),
                            ),
                          ];
                        }

                        // Compact List Mode (Default)
                        return [
                          SliverPadding(
                            padding: const EdgeInsets.only(top: 2, bottom: 96),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final src = displaySources[index];
                                final isPinned = pinnedList.contains(src.id);
                                final initial = src.name.isNotEmpty
                                    ? src.name[0].toUpperCase()
                                    : 'M';
                                final color = _getSourceColor(src.id);

                                return InkWell(
                                  onTap: () => _openSource(src),
                                  onLongPress: () =>
                                      _togglePinSource(src, isPinned),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4.5,
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 38,
                                          height: 38,
                                          child: _buildFavicon(
                                            src,
                                            initial,
                                            color,
                                            size: 38,
                                            borderRadius: 6,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  if (isPinned) ...[
                                                    const Icon(
                                                      Icons
                                                          .local_fire_department_rounded,
                                                      size: 15,
                                                      color: Color(0xFFFF6D00),
                                                    ),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  Expanded(
                                                    child: Text(
                                                      src.name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 14.5,
                                                        height: 1.2,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Manga, Indonesia',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.6),
                                                  fontSize: 12,
                                                  height: 1.2,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }, childCount: displaySources.length),
                            ),
                          ),
                        ];
                      },
                      loading: () => [
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.only(top: 60),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      ],
                      error: (err, _) => [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: ErrorView(
                              message: err.toString(),
                              onRetry: _handleRefresh,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
