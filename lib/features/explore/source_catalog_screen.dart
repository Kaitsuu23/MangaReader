import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/models/manga_item.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../../shared/widgets/empty_view.dart';
import '../../shared/widgets/error_view.dart';
import '../details/manga_details_screen.dart';
import '../../core/services/network_service.dart';

enum CatalogMode { popular, latest, rating, az, genre, type }

class SourceCatalogScreen extends ConsumerStatefulWidget {
  final String source;
  final CatalogMode mode;
  final String? filterValue; // genre slug or type name
  final String title;

  const SourceCatalogScreen({
    super.key,
    required this.source,
    required this.mode,
    this.filterValue,
    required this.title,
  });

  @override
  ConsumerState<SourceCatalogScreen> createState() =>
      _SourceCatalogScreenState();
}

class _SourceCatalogScreenState extends ConsumerState<SourceCatalogScreen> {
  final List<MangaItem> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  bool _hasNextPage = true;

  @override
  void initState() {
    super.initState();
    _fetchPage(1);
  }

  Future<void> _fetchPage(int page) async {
    if (page == 1) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final api = ref.read(parserChannelProvider);
      final ({List<MangaItem> data, dynamic pagination}) result;

      switch (widget.mode) {
        case CatalogMode.popular:
          result = await api.getPopular(widget.source, page: page);
          break;
        case CatalogMode.latest:
          result = await api.getLatest(widget.source, page: page);
          break;
        case CatalogMode.rating:
          result = await api.getBySort(widget.source, 'rating', page: page);
          break;
        case CatalogMode.az:
          result = await api.getBySort(widget.source, 'az', page: page);
          break;
        case CatalogMode.genre:
          result = await api.getByGenre(
            widget.source,
            widget.filterValue ?? '',
            page: page,
          );
          break;
        case CatalogMode.type:
          result = await api.getByType(
            widget.source,
            widget.filterValue ?? '',
            page: page,
          );
          break;
      }

      setState(() {
        if (page == 1) {
          _items.clear();
        }
        _items.addAll(result.data);
        _currentPage = page;
        _hasNextPage =
            result.pagination?.hasNextPage ?? (result.data.isNotEmpty);
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _isLoadingMore = false;
        });
        if (NetworkService.isNetworkError(e) || !NetworkService.isConnected) {
          NetworkService.showNoInternetSnackBar(
            context,
            onRetry: () => _fetchPage(page),
            hasBottomNavbar: false,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: NotificationListener<ScrollNotification>(
          onNotification: (scrollInfo) {
            if (scrollInfo.metrics.pixels >=
                scrollInfo.metrics.maxScrollExtent - 200) {
              if (!_isLoadingMore && _hasNextPage && !_isLoading) {
                _fetchPage(_currentPage + 1);
              }
            }
            return false;
          },
          child: _buildBody(),
        ),
      ), // Scaffold
    ); // ScaffoldMessenger
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const MangaGridShimmer(count: 9);
    }

    if (_error != null && _items.isEmpty) {
      return ErrorView(message: _error!, onRetry: () => _fetchPage(1));
    }

    if (_items.isEmpty) {
      return const EmptyView(
        icon: Icons.menu_book_rounded,
        title: 'Tidak Ada Manga',
        subtitle: 'Tidak ada item yang ditemukan pada katalog ini.',
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        LocalStorage.listenFavorites(),
        LocalStorage.listenHistory(),
        LocalStorage.listenFeed(),
      ]),
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: () => _fetchPage(1),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.58,
                    crossAxisSpacing: 11,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = _items[index];
                    return MangaCard(
                      item: item,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MangaDetailsScreen(
                              slug: item.slug,
                              source: item.source ?? widget.source,
                              title: item.title,
                              cover: item.cover,
                            ),
                          ),
                        );
                      },
                    );
                  }, childCount: _items.length),
                ),
              ),
              if (_isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
