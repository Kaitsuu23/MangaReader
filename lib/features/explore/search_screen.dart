import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/manga_item.dart';
import '../../shared/models/manga_source.dart';
import '../../shared/widgets/cached_cover.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../details/manga_details_screen.dart';
import 'source_view_screen.dart';
import '../../core/services/network_service.dart';

/// Jenis pencarian sesuai Kotatsu Redo (SearchKind)
enum SearchKind {
  simple('Sederhana'),
  title('Judul'),
  author('Penulis'),
  tag('Genre');

  final String label;
  const SearchKind(this.label);
}

/// Model hasil pencarian per sumber (SearchResultsListModel Kotatsu Redo)
class _SourceResultGroup {
  final MangaSource source;
  List<MangaItem> items = const [];
  bool isLoading;
  String? error;

  _SourceResultGroup({
    required this.source,
    this.isLoading = true,
  });
}

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late String _currentQuery;
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocusNode = FocusNode();
  bool _isEditingQuery = false;

  // Search parameters & filters (Kotatsu Redo)
  SearchKind _searchKind = SearchKind.simple;
  bool _pinnedOnly = false;
  bool _hideEmpty = false;

  // Search execution state
  List<_SourceResultGroup> _groups = [];
  bool _isGlobalSearching = false;
  int _searchSessionId = 0;

  @override
  void initState() {
    super.initState();
    _currentQuery = widget.initialQuery?.trim() ?? '';
    _editController.text = _currentQuery;

    if (_currentQuery.isNotEmpty) {
      _startGlobalSearch(_currentQuery);
    } else {
      _isEditingQuery = true;
    }
  }

  @override
  void dispose() {
    _searchSessionId++;
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  /// Menjalankan pencarian global lintas semua sumber (Kotatsu Redo Multi-source search)
  Future<void> _startGlobalSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    if (!NetworkService.isConnected) {
      NetworkService.showNoInternetSnackBar(
        context,
        onRetry: () => _startGlobalSearch(cleanQuery),
        hasBottomNavbar: false,
      );
    }

    _searchSessionId++;
    final currentSession = _searchSessionId;

    setState(() {
      _currentQuery = cleanQuery;
      _isEditingQuery = false;
      _isGlobalSearching = true;
      _groups = [];
    });

    // Simpan ke riwayat pencarian
    await LocalStorage.addRecentSearch(cleanQuery);

    try {
      final allSources = await ref.read(sourcesListProvider.future);
      if (currentSession != _searchSessionId) return;

      final disabled = LocalStorage.getDisabledSources();
      var targetSources = allSources.where((s) => !disabled.contains(s.id)).toList();

      if (_pinnedOnly) {
        targetSources = targetSources.where((s) => LocalStorage.isSourcePinned(s.id)).toList();
      }

      // Prioritaskan sumber yang disematkan (pinned first) persis seperti Kotatsu Redo
      targetSources.sort((a, b) {
        final aPinned = LocalStorage.isSourcePinned(a.id) ? 0 : 1;
        final bPinned = LocalStorage.isSourcePinned(b.id) ? 0 : 1;
        if (aPinned != bPinned) return aPinned.compareTo(bPinned);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (!mounted || currentSession != _searchSessionId) return;

      setState(() {
        _groups = targetSources
            .map((s) => _SourceResultGroup(source: s, isLoading: true))
            .toList();
      });

      // Jalankan worker dengan pool concurrency (MAX_PARALLELISM = 4 Kotatsu Redo)
      final queue = List<MangaSource>.from(targetSources);
      const maxParallel = 4;
      final poolSize = min(maxParallel, queue.length);

      Future<void> runWorker() async {
        while (queue.isNotEmpty) {
          if (currentSession != _searchSessionId || !mounted) return;
          final source = queue.removeAt(0);

          try {
            final api = ref.read(parserChannelProvider);
            final res = await api.search(source.id, cleanQuery, page: 1);

            if (currentSession != _searchSessionId || !mounted) return;

            setState(() {
              final idx = _groups.indexWhere((g) => g.source.id == source.id);
              if (idx != -1) {
                _groups[idx].items = res.data;
                _groups[idx].isLoading = false;
              }
            });
          } catch (e) {
            if (currentSession != _searchSessionId || !mounted) return;

            setState(() {
              final idx = _groups.indexWhere((g) => g.source.id == source.id);
              if (idx != -1) {
                _groups[idx].error = e.toString();
                _groups[idx].isLoading = false;
              }
            });
          }
        }
      }

      await Future.wait(List.generate(poolSize, (_) => runWorker()));

      if (currentSession == _searchSessionId && mounted) {
        setState(() {
          _isGlobalSearching = false;
        });
      }
    } catch (e) {
      if (currentSession == _searchSessionId && mounted) {
        setState(() {
          _isGlobalSearching = false;
        });
      }
    }
  }

  void _openFilterSheet(ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Tipe Pencarian',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    RadioGroup<SearchKind>(
                      groupValue: _searchKind,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _searchKind = val);
                          setSheetState(() {});
                          Navigator.pop(ctx);
                          _startGlobalSearch(_currentQuery);
                        }
                      },
                      child: Column(
                        children: SearchKind.values.map((k) {
                          return RadioListTile<SearchKind>(
                            contentPadding: EdgeInsets.zero,
                            value: k,
                            title: Text(k.label, style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 24),
                    Text(
                      'Filter Sumber',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hanya sumber disematkan', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        'Cari hanya pada sumber yang Anda pin',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      value: _pinnedOnly,
                      onChanged: (val) {
                        setState(() => _pinnedOnly = val);
                        setSheetState(() {});
                        _startGlobalSearch(_currentQuery);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sembunyikan sumber kosong', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        'Hanya tampilkan sumber yang memiliki hasil',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      value: _hideEmpty,
                      onChanged: (val) {
                        setState(() => _hideEmpty = val);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Filter daftar kelompok sumber sesuai opsi Kotatsu Redo:
    // Sumber yang punya hasil tampil di atas.
    // Jika _hideEmpty = true, sumber yang selesai dengan hasil 0 disembunyikan.
    final visibleGroups = _groups.where((g) {
      if (_hideEmpty) {
        return g.isLoading || g.items.isNotEmpty;
      }
      return g.isLoading || g.items.isNotEmpty || g.error != null;
    }).toList();

    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_isEditingQuery && _currentQuery.isNotEmpty) {
              setState(() => _isEditingQuery = false);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: _isEditingQuery
            ? TextField(
                controller: _editController,
                focusNode: _editFocusNode,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Cari komik...',
                  border: InputBorder.none,
                  suffixIcon: _editController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _editController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    _startGlobalSearch(val);
                  }
                },
              )
            : GestureDetector(
                onTap: () {
                  setState(() {
                    _isEditingQuery = true;
                    _editController.text = _currentQuery;
                  });
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentQuery.isEmpty ? 'Cari' : _currentQuery,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Hasil pencarian',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          if (!_isEditingQuery)
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () {
                setState(() {
                  _isEditingQuery = true;
                  _editController.text = _currentQuery;
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _openFilterSheet(theme),
          ),
          const SizedBox(width: 4),
        ],
        bottom: _isGlobalSearching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: theme.colorScheme.primary,
                ),
              )
            : null,
      ),
      body: _buildBody(theme, visibleGroups),
    ), // Scaffold
    ); // ScaffoldMessenger
  }

  Widget _buildBody(ThemeData theme, List<_SourceResultGroup> visibleGroups) {
    if (_currentQuery.isEmpty) {
      return const EmptyView(
        icon: Icons.search_rounded,
        title: 'Mulai Pencarian Global',
        subtitle: 'Ketik judul komik untuk mencari di semua sumber sekaligus.',
      );
    }

    if (_groups.isEmpty && _isGlobalSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    // Jika semua sumber telah selesai dan tidak ada komik satupun
    final allDone = !_isGlobalSearching && _groups.every((g) => !g.isLoading);
    final totalFound = _groups.fold<int>(0, (sum, g) => sum + g.items.length);

    if (allDone && totalFound == 0) {
      return EmptyView(
        icon: Icons.search_off_rounded,
        title: 'Tidak ada yang ditemukan',
        subtitle: 'Tidak ada komik ditemukan untuk "$_currentQuery". Coba kata kunci lain.',
      );
    }

    // Tampilkan daftar kelompok per sumber persis desain Kotatsu Redo (foto)
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 28),
      itemCount: visibleGroups.length,
      itemBuilder: (context, index) {
        final group = visibleGroups[index];
        return _buildSourceSection(theme, group);
      },
    );
  }

  /// Membangun satu section per sumber: Header (Nama + Tombol Tampilkan semua) & Horizontal Manga List
  Widget _buildSourceSection(ThemeData theme, _SourceResultGroup group) {
    final source = group.source;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Baris: Nama Sumber + 🔥 di kiri, Tampilkan semua di kanan (Kotatsu Redo)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          source.name,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('🔥', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SourceViewScreen(
                          sourceId: source.id,
                          sourceName: source.name,
                          initialQuery: _currentQuery,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'Tampilkan semua',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Horizontal List Komik / Shimmer jika loading / Error jika gagal
          if (group.isLoading && group.items.isEmpty)
            _buildHorizontalShimmer()
          else if (group.error != null && group.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gagal memuat: ${group.error}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.error,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )
          else if (group.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Tidak ada hasil',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            SizedBox(
              height: 205,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: group.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, cardIndex) {
                  final item = group.items[cardIndex];
                  return _buildHorizontalMangaCard(theme, item, source.id);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Kartu komik horizontal (persis layout di foto user)
  Widget _buildHorizontalMangaCard(ThemeData theme, MangaItem item, String sourceId) {
    const cardWidth = 110.0;

    return SizedBox(
      width: cardWidth,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MangaDetailsScreen(
                slug: item.slug,
                source: item.source ?? sourceId,
                title: item.title,
                cover: item.cover,
                id: item.id,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cover Poster 13:18 aspect ratio dengan rounded corners
            AspectRatio(
              aspectRatio: 13 / 18,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                child: item.cover != null && item.cover!.isNotEmpty
                    ? CachedCover(
                        imageUrl: item.cover!,
                        fit: BoxFit.cover,
                        placeholder: (ctx, url) => const MangaCardCoverShimmer(),
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHigh,
                        child: const Center(
                          child: Icon(Icons.menu_book, size: 28),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            // Judul maksimal 2 baris
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shimmer skeleton horizontal untuk sumber yang sedang loading
  Widget _buildHorizontalShimmer() {
    return SizedBox(
      height: 205,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, _) => SizedBox(
          width: 110,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 13 / 18,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  child: const MangaCardCoverShimmer(),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 11,
                width: 85,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 11,
                width: 55,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
