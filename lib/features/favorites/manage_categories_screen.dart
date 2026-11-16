import 'package:flutter/material.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/widgets/cached_cover.dart';
import 'category_edit_screen.dart';

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  List<String> _categories = [];
  bool _isAllVisible = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  void _loadCategories() {
    setState(() {
      _categories = LocalStorage.getFavoriteCategories();
      _isAllVisible = LocalStorage.isAllFavoritesVisible();
    });
  }

  Future<void> _openCreateCategory() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const CategoryEditScreen(),
      ),
    );
    if (result == true) {
      _loadCategories();
    }
  }

  Future<void> _openEditCategory(String name) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryEditScreen(initialName: name),
      ),
    );
    if (result == true) {
      _loadCategories();
    }
  }

  Widget _buildCoverStack(List<Map<String, dynamic>> items, ThemeData theme) {
    final covers = items
        .map((e) => e['cover'] as String?)
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .take(3)
        .toList();

    const double coverHeight = 56.0;
    const double coverWidth = 40.0; // ~ 13:18 aspect ratio
    const double totalWidth = 74.0;
    const double totalHeight = 72.0;

    return SizedBox(
      width: totalWidth,
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cover 3 (furthest back, furthest right, tilted ~6.3 degrees)
          Positioned(
            left: 28,
            top: 0,
            child: Transform.rotate(
              angle: 0.11,
              alignment: Alignment.bottomCenter,
              child: covers.length >= 3
                  ? _buildCoverImage(covers[2], coverWidth, coverHeight, theme, darkTintAlpha: 0.45)
                  : _buildCoverPlaceholder(coverWidth, coverHeight, theme, opacity: 0.25),
            ),
          ),
          // Cover 2 (middle, tilted ~3.1 degrees)
          Positioned(
            left: 14,
            top: 7,
            child: Transform.rotate(
              angle: 0.055,
              alignment: Alignment.bottomCenter,
              child: covers.length >= 2
                  ? _buildCoverImage(covers[1], coverWidth, coverHeight, theme, darkTintAlpha: 0.22)
                  : _buildCoverPlaceholder(coverWidth, coverHeight, theme, opacity: 0.40),
            ),
          ),
          // Cover 1 (front, furthest left, upright)
          Positioned(
            left: 0,
            top: 14,
            child: covers.isNotEmpty
                ? _buildCoverImage(covers[0], coverWidth, coverHeight, theme, darkTintAlpha: 0.0)
                : _buildEmptyFrontCover(coverWidth, coverHeight, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFrontCover(double width, double height, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder(double width, double height, ThemeData theme, {required double opacity}) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 4,
            offset: const Offset(1, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage(String url, double width, double height, ThemeData theme, {required double darkTintAlpha}) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.10),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 4,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5.2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedCover(
              imageUrl: url,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              errorWidget: (context, url, error) => Container(
                color: theme.colorScheme.surfaceContainerHigh,
                child: const Icon(Icons.broken_image, size: 16),
              ),
            ),
            if (darkTintAlpha > 0)
              Container(
                color: Colors.black.withValues(alpha: darkTintAlpha),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allFavorites = LocalStorage.getFavorites();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: _openCreateCategory,
        tooltip: 'Kategori baru',
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: ValueListenableBuilder(
        valueListenable: LocalStorage.listenFavorites(),
        builder: (context, box, _) {
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Material 3 Collapsing Top App Bar (Title slides up on scroll, matching Photo 1)
              SliverAppBar.medium(
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text(
                  'Atur kategori',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              // Pinned Item 1: "Semua kesukaan" (matching Image 1)
              SliverToBoxAdapter(
                child: Material(
                  color: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        _buildCoverStack(allFavorites, theme),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Semua kesukaan',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                allFavorites.isEmpty
                                    ? 'Kosong'
                                    : '${allFavorites.length} item',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _isAllVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 22,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          tooltip: _isAllVisible ? 'Sembunyikan dari rak' : 'Tampilkan di rak',
                          onPressed: () async {
                            final newVal = !_isAllVisible;
                            await LocalStorage.setAllFavoritesVisible(newVal);
                            setState(() => _isAllVisible = newVal);
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),

              // Reorderable Custom Categories List (matching Image 1)
              if (_categories.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 88),
                  sliver: SliverReorderableList(
                    itemCount: _categories.length,
                    onReorderItem: (oldIndex, newIndex) async {
                      await LocalStorage.reorderFavoriteCategories(oldIndex, newIndex);
                      _loadCategories();
                    },
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final catItems = LocalStorage.getFavorites(category: cat);
                      final meta = LocalStorage.getCategoryDetails(cat);
                      final checkNewChapters = meta['checkNewChapters'] as bool? ?? true;
                      final showOnShelf = meta['showOnShelf'] as bool? ?? true;

                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(cat),
                        index: index,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _openEditCategory(cat),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  _buildCoverStack(catItems, theme),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          cat,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              catItems.isEmpty
                                                  ? 'Kosong'
                                                  : '${catItems.length} item',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                            if (checkNewChapters) ...[
                                              const SizedBox(width: 6),
                                              Icon(
                                                Icons.notifications_none_rounded,
                                                size: 14,
                                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                              ),
                                            ],
                                            if (!showOnShelf) ...[
                                              const SizedBox(width: 6),
                                              Icon(
                                                Icons.visibility_off_outlined,
                                                size: 14,
                                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 21),
                                    tooltip: 'Sunting kategori',
                                    onPressed: () => _openEditCategory(cat),
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      child: Icon(
                                        Icons.drag_indicator_rounded,
                                        size: 22,
                                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
