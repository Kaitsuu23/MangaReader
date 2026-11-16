import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/cached_cover.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/models/manga_item.dart';
import '../../shared/models/manga_source.dart';
import '../../shared/models/genre.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/widgets/manga_card_badges.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../details/manga_details_screen.dart';
import '../../shared/widgets/predictive_back_bottom_sheet.dart';
import '../../shared/widgets/in_app_browser_screen.dart';
import '../../core/services/network_service.dart';

class SourceViewScreen extends ConsumerStatefulWidget {
  final String sourceId;
  final String sourceName;
  final String? initialGenre;
  final String? initialQuery;

  const SourceViewScreen({
    super.key,
    required this.sourceId,
    required this.sourceName,
    this.initialGenre,
    this.initialQuery,
  });

  @override
  ConsumerState<SourceViewScreen> createState() => _SourceViewScreenState();
}

class _SourceViewScreenState extends ConsumerState<SourceViewScreen> {
  late List<SourceSortOption> _availableSorts;
  late SourceSortOption _selectedSort;
  final Set<String> _selectedGenres = {};
  String? _selectedType;
  String? _selectedStatus;
  String? _selectedTema;
  String? _selectedDemografis;
  List<Genre> _availableTema = [];
  List<Genre> _availableDemografis = [];

  String _listMode = 'grid'; // 'compact', 'details', 'grid'
  int _gridColumns = 3; // 2, 3, 4

  // Remote Search State
  bool _isSearchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  String _searchQuery = '';
  final List<MangaItem> _searchResults = [];
  bool _isSearchLoading = false;
  bool _isSearchLoadingMore = false;
  String? _searchError;
  int _searchPage = 1;
  bool _hasSearchNextPage = true;
  int _searchFetchId = 0;

  final ScrollController _scrollController = ScrollController();
  List<Genre> _allGenres = [];

  static final List<Genre> _defaultPopularGenres = [
    Genre(name: 'Romance', slug: 'romance'),
    Genre(name: 'Comedy', slug: 'comedy'),
    Genre(name: 'Fantasy', slug: 'fantasy'),
    Genre(name: 'Action', slug: 'action'),
    Genre(name: 'Drama', slug: 'drama'),
    Genre(name: 'Adventure', slug: 'adventure'),
    Genre(name: 'Isekai', slug: 'isekai'),
    Genre(name: 'Slice of Life', slug: 'slice-of-life'),
    Genre(name: 'Mystery', slug: 'mystery'),
    Genre(name: 'Supernatural', slug: 'supernatural'),
    Genre(name: 'Horror', slug: 'horror'),
    Genre(name: 'Sci-Fi', slug: 'sci-fi'),
  ];

  final List<MangaItem> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  bool _hasNextPage = true;
  int _fetchId = 0;

  int get _maxSelectableGenres => MangaSource.getMaxSelectableGenres(widget.sourceId);
  bool get _hasGenreFilter => widget.sourceId.toLowerCase() != 'lepoytl';

  @override
  void initState() {
    super.initState();
    _availableSorts = MangaSource.getSortOptionsForSource(widget.sourceId);
    _selectedSort = _availableSorts.first;
    _listMode = LocalStorage.getSourceListMode();
    _gridColumns = LocalStorage.getSourceGridColumns();
    _scrollController.addListener(_onScroll);
    // Pre-select genre if passed from detail screen
    if (widget.initialGenre != null && widget.initialGenre!.isNotEmpty) {
      _selectedGenres.add(widget.initialGenre!);
    }
    _loadGenres();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _isSearchVisible = true;
      _searchController.text = widget.initialQuery!;
      _performSearch(widget.initialQuery!);
    } else {
      _fetchManga(1);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      // Trigger infinite scroll when within 800 pixels of the bottom (early prefetch, matching Kotatsu)
      if (maxScroll - currentScroll <= 800) {
        if (_isSearchVisible && _searchQuery.isNotEmpty) {
          if (!_isSearchLoadingMore && _hasSearchNextPage && !_isSearchLoading) {
            _fetchSearchMore();
          }
        } else {
          if (!_isLoadingMore && _hasNextPage && !_isLoading) {
            _fetchManga(_currentPage + 1);
          }
        }
      }
    }
  }

  Future<void> _loadGenres() async {
    if (!_hasGenreFilter) return;
    try {
      final api = ref.read(parserChannelProvider);
      final results = await Future.wait([
        api.getGenres(widget.sourceId),
        api.getSources().catchError((_) => <MangaSource>[]),
      ]);
      final genres = results[0] as List<Genre>;
      final sources = results[1] as List<MangaSource>;

      if (mounted) {
        setState(() {
          if (genres.isNotEmpty) {
            _allGenres = genres;
          }
          final currentSource = sources.where((s) => s.id.toLowerCase() == widget.sourceId.toLowerCase()).firstOrNull;
          if (currentSource?.supportedSorts != null && currentSource!.supportedSorts!.isNotEmpty) {
            _availableSorts = currentSource.supportedSorts!;
            if (!_availableSorts.any((s) => s.id == _selectedSort.id)) {
              _selectedSort = _availableSorts.first;
            }
          }
        });
      }

      if (widget.sourceId.toLowerCase() == 'komikindoch') {
        final temaResults = await api.getTema(widget.sourceId).catchError((_) => <Genre>[]);
        final demogResults = await api.getDemografis(widget.sourceId).catchError((_) => <Genre>[]);
        if (mounted) {
          setState(() {
            _availableTema = temaResults;
            _availableDemografis = demogResults;
          });
        }
      }
    } catch (_) {}
  }

  List<Genre> _getOrderedGenres() {
    if (_allGenres.isEmpty) {
      return _defaultPopularGenres;
    }
    final popularSlugs = _defaultPopularGenres.map((g) => g.slug.toLowerCase()).toSet();
    final popularInSource = _allGenres.where((g) => popularSlugs.contains(g.slug.toLowerCase())).toList();
    final others = _allGenres.where((g) => !popularSlugs.contains(g.slug.toLowerCase())).toList();

    popularInSource.sort((a, b) {
      final idxA = _defaultPopularGenres.indexWhere((g) => g.slug.toLowerCase() == a.slug.toLowerCase());
      final idxB = _defaultPopularGenres.indexWhere((g) => g.slug.toLowerCase() == b.slug.toLowerCase());
      return idxA.compareTo(idxB);
    });

    return [...popularInSource, ...others];
  }

  Future<void> _fetchManga(int page, {bool isPullToRefresh = false}) async {
    if (!mounted) return;
    final currentFetchId = ++_fetchId;

    if (page == 1) {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _error = null;
        if (!isPullToRefresh) {
          // Kotatsu behavior: immediately clear old cards from previous sort
          _items.clear();
        }
      });

      if (!isPullToRefresh && _scrollController.hasClients && _scrollController.offset > 0) {
        _scrollController.jumpTo(0);
      }
    } else {
      if (!mounted) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final api = ref.read(parserChannelProvider);
      final result = await api.getList(
        widget.sourceId,
        page: page,
        sort: _selectedSort.id,
        status: _selectedStatus,
        genre: _selectedGenres.isNotEmpty ? _selectedGenres.join(',') : null,
        type: _selectedType,
        tema: _selectedTema,
        demografis: _selectedDemografis,
      );

      // If another fetch was triggered while loading, cancel/ignore this result
      if (currentFetchId != _fetchId) return;

      if (mounted) {
        final resolvedData = result.data.map((item) {
          if (item.source == null || item.source!.trim().isEmpty) {
            return item.copyWith(source: widget.sourceId);
          }
          return item;
        }).toList();

        setState(() {
          if (page == 1) {
            _items.clear();
          }
          _items.addAll(resolvedData);
          _currentPage = page;
          _hasNextPage = (result.pagination?.hasNextPage ?? (result.data.length >= 8)) && result.data.isNotEmpty;
          _isLoading = false;
          _isLoadingMore = false;
        });

        // Kotatsu behavior: if the initial page doesn't fill enough scroll buffer (<= 800px),
        // prefetch page 2 immediately so the user experiences zero lag when scrolling
        if (page == 1 && _hasNextPage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              final maxScroll = _scrollController.position.maxScrollExtent;
              final currentScroll = _scrollController.position.pixels;
              if (maxScroll - currentScroll <= 800) {
                if (!_isLoadingMore && _hasNextPage && !_isLoading) {
                  _fetchManga(2);
                }
              }
            }
          });
        }
      }
    } catch (e) {
      if (currentFetchId != _fetchId) return;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          if (_items.isEmpty) {
            _error = e.toString();
          }
        });

        // Tampilkan SnackBar hanya jika terjadi kesalahan saat memuat halaman berikutnya (pagination),
        // bukan saat halaman pertama yang sudah memiliki tampilan ErrorView penuh.
        if (_items.isNotEmpty) {
          if (NetworkService.isNetworkError(e) || !NetworkService.isConnected) {
            NetworkService.showNoInternetSnackBar(
              context,
              onRetry: () {
                if (mounted) _fetchManga(page);
              },
              hasBottomNavbar: false,
            );
          } else {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text('Gagal memuat halaman berikutnya: $e'),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    }
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    final query = text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults.clear();
        _isSearchLoading = false;
        _searchError = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query, {bool isRefresh = false}) async {
    final currentFetchId = ++_searchFetchId;
    setState(() {
      _searchQuery = query;
      _isSearchLoading = true;
      _searchError = null;
      if (!isRefresh) {
        _searchResults.clear();
      }
    });

    try {
      final api = ref.read(parserChannelProvider);
      final result = await api.search(widget.sourceId, query, page: 1);
      if (currentFetchId != _searchFetchId) return;

      if (mounted) {
        final resolvedData = result.data.map((item) {
          if (item.source == null || item.source!.trim().isEmpty) {
            return item.copyWith(source: widget.sourceId);
          }
          return item;
        }).toList();

        setState(() {
          _searchResults.clear();
          _searchResults.addAll(resolvedData);
          _searchPage = 1;
          _hasSearchNextPage = (result.pagination?.hasNextPage ?? (result.data.length >= 8)) && result.data.isNotEmpty;
          _isSearchLoading = false;
        });
      }
    } catch (e) {
      if (currentFetchId != _searchFetchId) return;
      if (mounted) {
        setState(() {
          _isSearchLoading = false;
          _searchError = e.toString();
        });
        if (NetworkService.isNetworkError(e) || !NetworkService.isConnected) {
          NetworkService.showNoInternetSnackBar(
            context,
            onRetry: () => _performSearch(query),
            hasBottomNavbar: false,
          );
        }
      }
    }
  }

  Future<void> _fetchSearchMore() async {
    if (_isSearchLoadingMore || !_hasSearchNextPage || _isSearchLoading || _searchQuery.isEmpty) return;
    final nextPage = _searchPage + 1;
    final currentFetchId = ++_searchFetchId;

    setState(() => _isSearchLoadingMore = true);

    try {
      final api = ref.read(parserChannelProvider);
      final result = await api.search(widget.sourceId, _searchQuery, page: nextPage);
      if (currentFetchId != _searchFetchId) return;

      if (mounted) {
        final resolvedData = result.data.map((item) {
          if (item.source == null || item.source!.trim().isEmpty) {
            return item.copyWith(source: widget.sourceId);
          }
          return item;
        }).toList();

        setState(() {
          _searchResults.addAll(resolvedData);
          _searchPage = nextPage;
          _hasSearchNextPage = (result.pagination?.hasNextPage ?? (result.data.length >= 8)) && result.data.isNotEmpty;
          _isSearchLoadingMore = false;
        });
      }
    } catch (e) {
      if (currentFetchId != _searchFetchId) return;
      if (mounted) {
        setState(() => _isSearchLoadingMore = false);
      }
    }
  }

  void _closeSearch() {
    if (!_isSearchVisible) return;
    _searchDebounce?.cancel();
    setState(() {
      _isSearchVisible = false;
      _searchController.clear();
      _searchQuery = '';
      _searchResults.clear();
      _isSearchLoading = false;
      _searchError = null;
    });
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _toggleSearch() {
    if (_isSearchVisible) {
      _closeSearch();
    } else {
      setState(() {
        _isSearchVisible = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  void _openRandomManga() {
    if (_items.isEmpty) return;
    final randomItem = _items[Random().nextInt(_items.length)];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaDetailsScreen(
          slug: randomItem.slug,
          source: widget.sourceId,
          title: randomItem.title,
          cover: randomItem.cover,
          id: randomItem.id,
          origin: 'source_view',
          sourceName: widget.sourceName,
        ),
      ),
    );
  }

  String _getSortLabel(SourceSortOption option) => option.label;

  static final Map<String, List<String>> _inMemoryGenresCache = {};
  final Set<String> _pendingGenreFetches = {};

  List<String> _getItemGenres(MangaItem item) {
    if (item.genres.isNotEmpty) {
      return item.genres;
    }
    final key = '${widget.sourceId}_${item.slug}';
    final cachedMem = _inMemoryGenresCache[key];
    if (cachedMem != null && cachedMem.isNotEmpty) {
      return cachedMem;
    }
    final cachedLocal = LocalStorage.getCachedMangaGenres(widget.sourceId, item.slug);
    if (cachedLocal != null && cachedLocal.isNotEmpty) {
      _inMemoryGenresCache[key] = cachedLocal;
      return cachedLocal;
    }

    _extractGenreFromDetails(item);
    return const [];
  }

  void _extractGenreFromDetails(MangaItem item) {
    final key = '${widget.sourceId}_${item.slug}';
    if (_pendingGenreFetches.contains(key)) return;
    _pendingGenreFetches.add(key);

    ref.read(parserChannelProvider).getDetails(widget.sourceId, item.slug).then((details) async {
      _pendingGenreFetches.remove(key);
      if (details.genres.isNotEmpty) {
        final genreNames = details.genres.map((g) => g.name).where((n) => n.isNotEmpty).toList();
        if (genreNames.isNotEmpty) {
          _inMemoryGenresCache[key] = genreNames;
          await LocalStorage.saveCachedMangaGenres(widget.sourceId, item.slug, genreNames);
          if (mounted) {
            setState(() {});
          }
        }
      }
    }).catchError((_) {
      _pendingGenreFetches.remove(key);
    });
  }

  /// Returns subtitle text for a manga card (genres only).
  String _itemSubtitle(MangaItem item) {
    final genres = _getItemGenres(item);
    if (genres.isNotEmpty) {
      return genres.take(3).join(', ');
    }
    return '';
  }

  void _showFilterBottomSheet() {
    SourceSortOption tempSort = _selectedSort;
    Set<String> tempGenres = Set.from(_selectedGenres);
    String? tempType = _selectedType;
    String? tempStatus = _selectedStatus;
    String? tempTema = _selectedTema;
    String? tempDemografis = _selectedDemografis;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AnimationStyle(
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 250),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);

            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              minChildSize: 0.35,
              maxChildSize: 0.78,
              expand: false,
              builder: (context, scrollController) {
                // Collect visible genre chips: ensure all currently selected genres are visible, plus top 12
                final visibleChips = <Genre>[];
                final seenSlugs = <String>{};
                for (final slug in tempGenres) {
                  final match = _allGenres.firstWhere(
                    (g) => g.slug == slug,
                    orElse: () => Genre(name: slug, slug: slug),
                  );
                  if (seenSlugs.add(match.slug)) {
                    visibleChips.add(match);
                  }
                }
                final availableGenreList = _hasGenreFilter ? _allGenres : _defaultPopularGenres;
                for (final g in availableGenreList.take(12)) {
                  if (seenSlugs.add(g.slug)) {
                    visibleChips.add(g);
                  }
                }

                return PredictiveBackBottomSheet(
                  child: Material(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          children: [
                        // Urutkan
                        Text(
                          'Urutkan',
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<SourceSortOption>(
                              value: _availableSorts.firstWhere(
                                (s) => s.id == tempSort.id,
                                orElse: () => _availableSorts.first,
                              ),
                              isExpanded: true,
                              items: _availableSorts.map((opt) {
                                return DropdownMenuItem(
                                  value: opt,
                                  child: Text(opt.label),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setSheetState(() {
                                    tempSort = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Bahasa
                        Text(
                          'Bahasa',
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: 'all',
                              isExpanded: true,
                              items: [
                                DropdownMenuItem(value: 'all', child: Text('Semua bahasa')),
                                DropdownMenuItem(value: 'id', child: Text('Indonesia')),
                              ],
                              onChanged: null,
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Genre section with "Lebih"
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Genre',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: !_hasGenreFilter
                                    ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                    : null,
                              ),
                            ),
                            if (_hasGenreFilter)
                              InkWell(
                                onTap: () async {
                                  final newSelected = await _showAllGenresSheet(currentSelection: tempGenres);
                                  if (newSelected != null) {
                                    setSheetState(() {
                                      tempGenres.clear();
                                      tempGenres.addAll(newSelected);
                                    });
                                  }
                                },
                                child: Text(
                                  'Lebih',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: visibleChips.map((g) {
                            final isSelected = tempGenres.contains(g.slug);
                            return FilterChip(
                              label: Text(g.name),
                              labelStyle: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: !_hasGenreFilter
                                    ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                    : (isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface),
                              ),
                              selected: isSelected,
                              showCheckmark: false,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: !_hasGenreFilter
                                      ? theme.colorScheme.outline.withValues(alpha: 0.1)
                                      : (isSelected ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.2)),
                                  width: 1,
                                ),
                              ),
                              backgroundColor: theme.colorScheme.surfaceContainerHigh.withValues(alpha: !_hasGenreFilter ? 0.4 : 1.0),
                              selectedColor: theme.colorScheme.primaryContainer,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              onSelected: !_hasGenreFilter
                                  ? null
                                  : (selected) {
                                      if (selected) {
                                        if (_maxSelectableGenres == 1) {
                                          setSheetState(() {
                                            tempGenres.clear();
                                            tempGenres.add(g.slug);
                                          });
                                          return;
                                        }
                                        if (tempGenres.length >= _maxSelectableGenres) {
                                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('${widget.sourceName} hanya mendukung maksimal $_maxSelectableGenres genre.'),
                                              duration: const Duration(seconds: 2),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }
                                        setSheetState(() {
                                          tempGenres.add(g.slug);
                                        });
                                      } else {
                                        setSheetState(() {
                                          tempGenres.remove(g.slug);
                                        });
                                      }
                                    },
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 14),

                        // Tipe
                        Text(
                          'Tipe',
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: MangaSource.getTypesForSource(widget.sourceId).map((t) {
                            final isSelected = tempType == t['val'];
                            return ChoiceChip(
                              label: Text(t['label']!),
                              labelStyle: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                              ),
                              selected: isSelected,
                              showCheckmark: false,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              backgroundColor: theme.colorScheme.surfaceContainerHigh,
                              selectedColor: theme.colorScheme.primaryContainer,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              onSelected: (selected) {
                                setSheetState(() {
                                  tempType = selected ? t['val'] : null;
                                });
                              },
                            );
                          }).toList(),
                        ),

                        if (widget.sourceId.toLowerCase() == 'komikindoch' && _availableTema.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Tema',
                                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              InkWell(
                                onTap: () async {
                                  final newSelected = await _showAllTemaSheet(currentSelection: tempTema);
                                  setSheetState(() {
                                    tempTema = newSelected;
                                  });
                                },
                                child: Text(
                                  tempTema != null ? 'Ubah' : 'Pilih',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              final newSelected = await _showAllTemaSheet(currentSelection: tempTema);
                              setSheetState(() {
                                tempTema = newSelected;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      tempTema != null
                                          ? _availableTema.firstWhere(
                                              (t) => t.slug == tempTema,
                                              orElse: () => Genre(name: tempTema!, slug: tempTema!),
                                            ).name
                                          : 'Pilih tema komik...',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: tempTema != null ? theme.colorScheme.primary : theme.colorScheme.outline,
                                        fontWeight: tempTema != null ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (tempTema != null)
                                    GestureDetector(
                                      onTap: () {
                                        setSheetState(() {
                                          tempTema = null;
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Icon(Icons.close_rounded, size: 18, color: theme.colorScheme.outline),
                                      ),
                                    ),
                                  Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.outline),
                                ],
                              ),
                            ),
                          ),
                        ],

                        if (widget.sourceId.toLowerCase() == 'komikindoch' && _availableDemografis.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            'Demografis',
                            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _availableDemografis.map((d) {
                              final isSelected = tempDemografis == d.slug;
                              return ChoiceChip(
                                label: Text(d.name),
                                labelStyle: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  color: isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                                ),
                                selected: isSelected,
                                showCheckmark: false,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                                selectedColor: theme.colorScheme.primaryContainer,
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                onSelected: (selected) {
                                  setSheetState(() {
                                    tempDemografis = selected ? d.slug : null;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],

                        const SizedBox(height: 14),

                        // Status
                        Text(
                          'Status',
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            {'label': 'Masih lanjut', 'val': 'ongoing'},
                            {'label': 'Tamat', 'val': 'completed'},
                          ].map((s) {
                            final isSelected = tempStatus == s['val'];
                            return ChoiceChip(
                              label: Text(s['label']!),
                              labelStyle: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                              ),
                              selected: isSelected,
                              showCheckmark: false,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              backgroundColor: theme.colorScheme.surfaceContainerHigh,
                              selectedColor: theme.colorScheme.primaryContainer,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              onSelected: (selected) {
                                setSheetState(() {
                                  tempStatus = selected ? s['val'] : null;
                                });
                              },
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),

                      // Bottom Action Buttons
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    setState(() {
                                      _selectedSort = tempSort;
                                      _selectedGenres.clear();
                                      _selectedGenres.addAll(tempGenres);
                                      _selectedType = tempType;
                                      _selectedStatus = tempStatus;
                                      _selectedTema = tempTema;
                                      _selectedDemografis = tempDemografis;
                                    });
                                    _fetchManga(1);
                                  },
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  child: const Text('Selesai'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<Set<String>?> _showAllGenresSheet({Set<String>? currentSelection}) async {
    if (!_hasGenreFilter) return null;
    final searchController = TextEditingController();
    List<Genre> filteredList = List.from(_allGenres);
    final tempSelected = Set<String>.from(currentSelection ?? _selectedGenres);

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AnimationStyle(
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 250),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);

            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.40,
              maxChildSize: 0.80,
              expand: false,
              builder: (context, scrollController) {
                return PredictiveBackBottomSheet(
                  child: Material(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Search Genre input
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: 'Ketik nama genre',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHigh,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            isDense: true,
                          ),
                          onChanged: (query) {
                            setSheetState(() {
                              if (query.trim().isEmpty) {
                                filteredList = List.from(_allGenres);
                              } else {
                                filteredList = _allGenres
                                    .where((g) => g.name.toLowerCase().contains(query.toLowerCase()))
                                    .toList();
                              }
                            });
                          },
                        ),
                      ),

                      const SizedBox(height: 8),

                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final g = filteredList[index];
                            final isSelected = tempSelected.contains(g.slug);

                            return ListTile(
                              title: Text(
                                g.name,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? theme.colorScheme.primary : null,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(_maxSelectableGenres == 1 ? Icons.radio_button_checked_rounded : Icons.check_box_rounded, color: theme.colorScheme.primary)
                                  : Icon(_maxSelectableGenres == 1 ? Icons.radio_button_off_rounded : Icons.check_box_outline_blank_rounded, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                              onTap: () {
                                if (tempSelected.contains(g.slug)) {
                                  setSheetState(() {
                                    tempSelected.remove(g.slug);
                                  });
                                } else {
                                  if (_maxSelectableGenres == 1) {
                                    setSheetState(() {
                                      tempSelected.clear();
                                      tempSelected.add(g.slug);
                                    });
                                    return;
                                  }
                                  if (tempSelected.length >= _maxSelectableGenres) {
                                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('${widget.sourceName} hanya mendukung maksimal $_maxSelectableGenres genre.'),
                                        duration: const Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    return;
                                  }
                                  setSheetState(() {
                                    tempSelected.add(g.slug);
                                  });
                                }
                              },
                            );
                          },
                        ),
                      ),

                      // Bottom Action Buttons
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    setSheetState(() {
                                      tempSelected.clear();
                                    });
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  child: const Text('Reset'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    Navigator.pop(ctx, tempSelected);
                                  },
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  child: Text(
                                    tempSelected.isNotEmpty
                                        ? 'Terapkan (${tempSelected.length})'
                                        : 'Terapkan',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                );
              },
            );
          },
        );
      },
    );

    if (result != null) {
      if (currentSelection != null) {
        return result;
      }
      if (!mounted) return result;
      setState(() {
        _selectedGenres.clear();
        _selectedGenres.addAll(result);
      });
      _fetchManga(1);
      return result;
    }
    return null;
  }

  Future<String?> _showAllTemaSheet({String? currentSelection}) async {
    final searchController = TextEditingController();
    List<Genre> filteredList = List.from(_availableTema);
    String? tempSelected = currentSelection ?? _selectedTema;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AnimationStyle(
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 250),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);

            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.40,
              maxChildSize: 0.80,
              expand: false,
              builder: (context, scrollController) {
                return PredictiveBackBottomSheet(
                  child: Material(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Search Tema input
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: TextField(
                            controller: searchController,
                            decoration: InputDecoration(
                              hintText: 'Ketik nama tema',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: theme.colorScheme.surfaceContainerHigh,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              isDense: true,
                            ),
                            onChanged: (query) {
                              setSheetState(() {
                                if (query.trim().isEmpty) {
                                  filteredList = List.from(_availableTema);
                                } else {
                                  filteredList = _availableTema
                                      .where((t) => t.name.toLowerCase().contains(query.toLowerCase()))
                                      .toList();
                                }
                              });
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        Expanded(
                          child: ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: filteredList.length,
                            itemBuilder: (context, index) {
                              final t = filteredList[index];
                              final isSelected = tempSelected == t.slug;

                              return ListTile(
                                title: Text(
                                  t.name,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? theme.colorScheme.primary : null,
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(Icons.radio_button_checked_rounded, color: theme.colorScheme.primary)
                                    : Icon(Icons.radio_button_off_rounded, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                                onTap: () {
                                  setSheetState(() {
                                    if (tempSelected == t.slug) {
                                      tempSelected = null;
                                    } else {
                                      tempSelected = t.slug;
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),

                        // Bottom Action Buttons
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setSheetState(() {
                                        tempSelected = null;
                                      });
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                    ),
                                    child: const Text('Reset'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () {
                                      Navigator.pop(ctx, tempSelected ?? '');
                                    },
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                    ),
                                    child: Text(
                                      tempSelected != null
                                          ? 'Terapkan (1)'
                                          : 'Terapkan',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    if (result != null) {
      final finalTema = result.isEmpty ? null : result;
      if (currentSelection != null) {
        return finalTema;
      }
      if (!mounted) return finalTema;
      setState(() {
        _selectedTema = finalTema;
      });
      _fetchManga(1);
      return finalTema;
    }
    return null;
  }

  Future<void> _openDetails(MangaItem item) async {
    final effectiveSource = (item.source != null && item.source!.trim().isNotEmpty)
        ? item.source!.trim()
        : widget.sourceId;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaDetailsScreen(
          slug: item.slug,
          source: effectiveSource,
          title: item.title,
          cover: item.cover,
          id: item.id,
          origin: 'source_view',
          sourceName: widget.sourceName,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
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
                          color: theme.colorScheme.outline.withValues(alpha: 0.2),
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
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
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
                            LocalStorage.setSourceGridColumns(newCols);
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
          LocalStorage.setSourceListMode(mode);
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

  Widget _buildCompactItem(MangaItem item) {
    final theme = Theme.of(context);
    final effectiveSource = (item.source != null && item.source!.trim().isNotEmpty)
        ? item.source!.trim()
        : widget.sourceId;
    final isFav = LocalStorage.isFavorite(item.slug, source: effectiveSource);
    final progress = LocalStorage.getHistoryProgress(item.slug, source: effectiveSource);
    final unreadUpdates = LocalStorage.getMangaUnreadNewChaptersCount(item.slug, source: effectiveSource);

    return InkWell(
      onTap: () => _openDetails(item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.cover != null && item.cover!.isNotEmpty
                        ? CachedCover(
                            imageUrl: item.cover!,
                            source: item.source ?? widget.sourceId,
                            slug: item.slug,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 150),
                            errorWidget: (context, url, err) => const Icon(Icons.broken_image, size: 20),
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHigh,
                            child: const Icon(Icons.menu_book, size: 20),
                          ),
                    if (unreadUpdates > 0 || isFav)
                      Positioned(
                        top: 2,
                        left: 2,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (unreadUpdates > 0) ...[
                              NewChaptersBadge(
                                count: unreadUpdates,
                                height: 16,
                                fontSize: 8.0,
                              ),
                              if (isFav) const SizedBox(width: 2),
                            ],
                            if (isFav) const FavoriteBadge(size: 16, iconSize: 9),
                          ],
                        ),
                      ),
                    if (progress > 0)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: ReadingProgressBadge(progress: progress, size: 16, strokeWidth: 1.8),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_itemSubtitle(item).isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _itemSubtitle(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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

  Widget _buildDetailedItem(MangaItem item) {
    final theme = Theme.of(context);
    final effectiveSource = (item.source != null && item.source!.trim().isNotEmpty)
        ? item.source!.trim()
        : widget.sourceId;
    final isFav = LocalStorage.isFavorite(item.slug, source: effectiveSource);
    final progress = LocalStorage.getHistoryProgress(item.slug, source: effectiveSource);
    final unreadUpdates = LocalStorage.getMangaUnreadNewChaptersCount(item.slug, source: effectiveSource);

    return InkWell(
      onTap: () => _openDetails(item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 78,
                height: 114,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.cover != null && item.cover!.isNotEmpty
                        ? CachedCover(
                            imageUrl: item.cover!,
                            source: effectiveSource,
                            slug: item.slug,
                            width: 78,
                            height: 114,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 150),
                            errorWidget: (context, url, err) => const Icon(Icons.broken_image, size: 24),
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHigh,
                            child: const Icon(Icons.menu_book, size: 24),
                          ),
                    if (unreadUpdates > 0 || isFav)
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
                              if (isFav) const SizedBox(width: 3),
                            ],
                            if (isFav) const FavoriteBadge(size: 22, iconSize: 11),
                          ],
                        ),
                      ),
                    if (progress > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: ReadingProgressBadge(progress: progress, size: 22, strokeWidth: 2.5),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final genres = _getItemGenres(item);
                      if (genres.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            genres.join(', '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
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
    final displayGenres = _getOrderedGenres();
    final isSearching = _isSearchVisible && _searchQuery.isNotEmpty;

    return ListenableBuilder(
      listenable: Listenable.merge([
        LocalStorage.listenFavorites(),
        LocalStorage.listenHistory(),
        LocalStorage.listenFeed(),
      ]),
      builder: (context, _) {
        return PopScope(
          canPop: !_isSearchVisible,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_isSearchVisible) {
              _closeSearch();
            }
          },
          child: ScaffoldMessenger(
            child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            body: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: () {
                  if (isSearching) {
                    return _performSearch(_searchQuery, isRefresh: true);
                  } else {
                    return _fetchManga(1, isPullToRefresh: true);
                  }
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // 1. Collapsing App Bar matching Kotatsu ActivityMangaList CollapsingToolbarLayout
                    SliverAppBar(
              expandedHeight: _isSearchVisible ? 0 : 112.0,
              pinned: false,
              floating: true,
              snap: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: theme.scaffoldBackgroundColor,
              leading: _isSearchVisible
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _closeSearch,
                    )
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
              title: _isSearchVisible
                  ? TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Cari di ${widget.sourceName}...',
                        border: InputBorder.none,
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        hintStyle: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 18,
                        ),
                        suffixIcon: _isSearchLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : (_searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      _searchController.clear();
                                      _onSearchChanged('');
                                    },
                                  )
                                : null),
                      ),
                      style: const TextStyle(fontSize: 18),
                      onChanged: _onSearchChanged,
                      onSubmitted: (text) {
                        final q = text.trim();
                        if (q.isNotEmpty) {
                          _searchDebounce?.cancel();
                          _performSearch(q);
                        }
                      },
                    )
                  : null,
              actions: [
                if (!_isSearchVisible) ...[
                  IconButton(
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Cari Komik',
                    onPressed: _toggleSearch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.casino_outlined),
                    tooltip: 'Komik Acak',
                    onPressed: _openRandomManga,
                  ),
                ],
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  position: PopupMenuPosition.under,
                  constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
                  onSelected: (val) {
                    if (val == 'list_mode') {
                      _showListModeSheet();
                    } else if (val == 'filter') {
                      _showFilterBottomSheet();
                    } else if (val == 'open_web') {
                      final url = MangaSource.getBaseUrlForSource(widget.sourceId);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InAppBrowserScreen(
                            url: url,
                            title: widget.sourceName,
                          ),
                        ),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'open_web',
                      height: 40,
                      child: Row(
                        children: [
                          Icon(Icons.public_rounded, size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Buka di peramban web',
                              style: TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_isSearchVisible)
                      const PopupMenuItem(
                        value: 'filter',
                        height: 40,
                        child: Row(
                          children: [
                            Icon(Icons.filter_list_rounded, size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Saring',
                                style: TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'list_mode',
                      height: 40,
                      child: Row(
                        children: [
                          Icon(Icons.view_agenda_outlined, size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Opsi daftar',
                              style: TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              flexibleSpace: _isSearchVisible
                  ? null
                  : LayoutBuilder(
                builder: (context, constraints) {
                  final topPadding = MediaQuery.of(context).padding.top;
                  final currentH = constraints.biggest.height;
                  final minH = topPadding + kToolbarHeight;
                  final maxH = topPadding + 112.0;
                  final expandRatio = ((currentH - minH) / (maxH - minH)).clamp(0.0, 1.0);

                  return Container(
                    color: theme.scaffoldBackgroundColor,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Collapsed Title inside top Toolbar (visible when scrolled)
                        Positioned(
                          left: 56,
                          top: topPadding,
                          bottom: 0,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Opacity(
                              opacity: (1.0 - expandRatio * 2.0).clamp(0.0, 1.0),
                              child: Text(
                                widget.sourceName,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Expanded Title on Left & Sort Button on Right (side by side on bottom)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 10,
                          child: Opacity(
                            opacity: (expandRatio - 0.25).clamp(0.0, 1.0) / 0.75,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.sourceName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: _showFilterBottomSheet,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.filter_list_rounded,
                                          size: 18,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _getSortLabel(_selectedSort),
                                          style: TextStyle(
                                            color: theme.colorScheme.primary,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
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
                      ],
                    ),
                  );
                },
              ),
            ),

            // 2. Pinned Horizontal Filter Header (hidden when searching or if source has no genres)
            if (!_isSearchVisible && _hasGenreFilter)
              SliverPersistentHeader(
              pinned: true,
              delegate: _SliverGenreHeaderDelegate(
                child: Container(
                  height: 46,
                  color: theme.scaffoldBackgroundColor,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      // [ ? Genre ] button (always neutral, opens all genres sheet)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                        child: Material(
                          color: theme.colorScheme.surfaceContainerHigh,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _showAllGenresSheet(),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.menu_rounded,
                                    size: 16,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _selectedGenres.isNotEmpty
                                        ? 'Genre (${_selectedGenres.length})'
                                        : 'Genre',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),

                      // Active type chip with dismiss
                      if (_selectedType != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                          child: Material(
                            color: theme.colorScheme.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: theme.colorScheme.outline.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: () {
                                setState(() => _selectedType = null);
                                _fetchManga(1);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12, right: 6, top: 4, bottom: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      MangaSource.formatTypeLabel(_selectedType),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Active tema chip with dismiss
                      if (_selectedTema != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                          child: Material(
                            color: theme.colorScheme.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: theme.colorScheme.outline.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: () {
                                setState(() => _selectedTema = null);
                                _fetchManga(1);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12, right: 6, top: 4, bottom: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _availableTema.firstWhere(
                                        (t) => t.slug == _selectedTema,
                                        orElse: () => Genre(name: _selectedTema!, slug: _selectedTema!),
                                      ).name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Active demografis chip with dismiss
                      if (_selectedDemografis != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                          child: Material(
                            color: theme.colorScheme.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: theme.colorScheme.outline.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: () {
                                setState(() => _selectedDemografis = null);
                                _fetchManga(1);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12, right: 6, top: 4, bottom: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _availableDemografis.firstWhere(
                                        (d) => d.slug == _selectedDemografis,
                                        orElse: () => Genre(name: _selectedDemografis!, slug: _selectedDemografis!),
                                      ).name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Active status chip with dismiss
                      if (_selectedStatus != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                          child: Material(
                            color: theme.colorScheme.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: theme.colorScheme.outline.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: () {
                                setState(() => _selectedStatus = null);
                                _fetchManga(1);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12, right: 6, top: 4, bottom: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _selectedStatus == 'ongoing' ? 'Masih lanjut' : 'Tamat',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Active selected genre chips (shown right after Genre button)
                      ..._selectedGenres.map((slug) {
                        final genre = _allGenres.firstWhere(
                          (g) => g.slug == slug,
                          orElse: () => Genre(name: slug, slug: slug),
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                          child: Material(
                            color: theme.colorScheme.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: theme.colorScheme.outline.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedGenres.remove(slug);
                                });
                                _fetchManga(1);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8, right: 12, top: 4, bottom: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_rounded,
                                      size: 14,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      genre.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),

                      // Multi-select Genre Chips � unselected only (selected ones shown above)
                      ...displayGenres.where((g) => !_selectedGenres.contains(g.slug)).take(20).map((g) {
                        return Padding(
                           padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                           child: Material(
                             color: theme.colorScheme.surfaceContainerHigh,
                             shape: RoundedRectangleBorder(
                               borderRadius: BorderRadius.circular(8),
                               side: BorderSide(
                                 color: theme.colorScheme.outline.withValues(alpha: 0.25),
                                 width: 1,
                               ),
                             ),
                             child: InkWell(
                               onTap: () {
                                   if (_maxSelectableGenres == 1) {
                                     setState(() {
                                       _selectedGenres.clear();
                                       _selectedGenres.add(g.slug);
                                     });
                                     _fetchManga(1);
                                     return;
                                   }
                                   if (_selectedGenres.length >= _maxSelectableGenres) {
                                     ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                     ScaffoldMessenger.of(context).showSnackBar(
                                       SnackBar(
                                         content: Text('${widget.sourceName} hanya mendukung maksimal $_maxSelectableGenres genre.'),
                                         duration: const Duration(seconds: 2),
                                         behavior: SnackBarBehavior.floating,
                                       ),
                                     );
                                     return;
                                   }
                                   setState(() {
                                     _selectedGenres.add(g.slug);
                                   });
                                   _fetchManga(1);
                               },
                               borderRadius: BorderRadius.circular(8),
                               child: Padding(
                                 padding: EdgeInsets.only(
                                   left: 12,
                                   right: 12,
                                   top: 4,
                                   bottom: 4,
                                 ),
                                 child: Row(
                                   mainAxisSize: MainAxisSize.min,
                                   children: [
                                     Text(
                                       g.name,
                                       style: TextStyle(
                                         fontSize: 13,
                                         fontWeight: FontWeight.w500,
                                         color: theme.colorScheme.onSurface,
                                       ),
                                     ),
                                   ],
                                 ),
                               ),
                             ),
                           ),
                         );
                       }),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Grid / Loading / Error / Empty Content (Kotatsu loading design)
            if (isSearching) ...[
              if (_isSearchLoading && _searchResults.isEmpty)
                const SliverMangaGridShimmer(count: 9)
              else if (_searchError != null && _searchResults.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorView(
                    message: _searchError!,
                    onRetry: () => _performSearch(_searchQuery),
                    cloudflareUrl: MangaSource.getBaseUrlForSource(widget.sourceId),
                    sourceName: widget.sourceName,
                  ),
                )
              else if (!_isSearchLoading && _searchResults.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyView(
                    icon: Icons.search_off_rounded,
                    title: 'Tidak Ada Hasil',
                    subtitle: 'Tidak ada komik ditemukan untuk "$_searchQuery" di ${widget.sourceName}.',
                  ),
                )
              else ...[
                if (_listMode == 'grid')
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _gridColumns,
                        childAspectRatio: _gridColumns == 2
                            ? 0.61
                            : (_gridColumns == 4 ? 0.54 : 0.58),
                        crossAxisSpacing: 11,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = _searchResults[index];
                          return MangaCard(
                            item: item,
                            fallbackSource: widget.sourceId,
                            onTap: () => _openDetails(item),
                          );
                        },
                        childCount: _searchResults.length,
                      ),
                    ),
                  )
                else if (_listMode == 'compact')
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = _searchResults[index];
                          return _buildCompactItem(item);
                        },
                        childCount: _searchResults.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = _searchResults[index];
                          return _buildDetailedItem(item);
                        },
                        childCount: _searchResults.length,
                      ),
                    ),
                  ),

                if (_isSearchLoadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ] else ...[
              if (_isLoading && _items.isEmpty)
                const SliverMangaGridShimmer(count: 9)
              else if (_error != null && _items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorView(
                    message: _error!,
                    onRetry: () => _fetchManga(1),
                    cloudflareUrl: MangaSource.getBaseUrlForSource(widget.sourceId),
                    sourceName: widget.sourceName,
                  ),
                )
              else if (_items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyView(
                    icon: Icons.menu_book_rounded,
                    title: 'Tidak Ada Manga',
                    subtitle: 'Tidak ada item yang sesuai dengan filter ini.',
                  ),
                )
              else ...[
                if (_listMode == 'grid')
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _gridColumns,
                        childAspectRatio: _gridColumns == 2
                            ? 0.61
                            : (_gridColumns == 4 ? 0.54 : 0.58),
                        crossAxisSpacing: 11,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = _items[index];
                          return MangaCard(
                            item: item,
                            fallbackSource: widget.sourceId,
                            onTap: () => _openDetails(item),
                          );
                        },
                        childCount: _items.length,
                      ),
                    ),
                  )
                else if (_listMode == 'compact')
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = _items[index];
                          return _buildCompactItem(item);
                        },
                        childCount: _items.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = _items[index];
                          return _buildDetailedItem(item);
                        },
                        childCount: _items.length,
                      ),
                    ),
                  ),

                if (_isLoadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
            ],
          ),
        ),
      ),
    ),
  ),
);
      },
    );
  }
}

class _SliverGenreHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _SliverGenreHeaderDelegate({required this.child});

  @override
  double get minExtent => 46.0;

  @override
  double get maxExtent => 46.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _SliverGenreHeaderDelegate oldDelegate) => true;
}
