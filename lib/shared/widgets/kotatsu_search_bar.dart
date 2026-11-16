import 'package:flutter/material.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/in_place_predictive_back_page_transitions_builder.dart';
import '../../features/explore/search_screen.dart';
import '../../features/details/manga_details_screen.dart';

/// Search bar kapsul Material 3 seragam untuk semua layar (Riwayat, Disukai, Jelajah, Umpan).
/// Tampilan dan fungsi pencarian 100% sama di semua layar, hanya menu titik 3 (trailingMenu) yang disesuaikan.
/// Ketika diklik, search bar bertransformasi (morph) menjadi halaman pencarian penuh dari posisi aslinya.
class KotatsuSearchBar extends StatefulWidget {
  final Widget trailingMenu;
  final String hintText;

  const KotatsuSearchBar({
    super.key,
    required this.trailingMenu,
    this.hintText = 'Cari manga',
  });

  @override
  State<KotatsuSearchBar> createState() => _KotatsuSearchBarState();
}

class _KotatsuSearchBarState extends State<KotatsuSearchBar> {
  final GlobalKey _searchBarKey = GlobalKey();

  void _openSearchView(BuildContext context) {
    final renderBox = _searchBarKey.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.sizeOf(context);
    final anchorRect = renderBox != null && renderBox.hasSize
        ? (renderBox.localToGlobal(Offset.zero) & renderBox.size)
        : Rect.fromLTWH(16, MediaQuery.paddingOf(context).top + 8, screenSize.width - 32, 48);

    Navigator.of(context).push(
      PredictiveBackPageRoute(
        anchorRect: anchorRect,
        builder: (_) => const KotatsuSearchView(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
      child: Container(
        key: _searchBarKey,
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
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _openSearchView(context),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.search_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.hintText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 14.5,
                    ),
                  ),
                ),
                widget.trailingMenu,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tampilan layar penuh pencarian (Material 3 SearchView) yang seragam di seluruh aplikasi
class KotatsuSearchView extends StatefulWidget {
  final String? initialQuery;

  const KotatsuSearchView({
    super.key,
    this.initialQuery,
  });

  @override
  State<KotatsuSearchView> createState() => _KotatsuSearchViewState();
}

class _KotatsuSearchViewState extends State<KotatsuSearchView> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  List<String> _recentSearches = [];

  final List<String> _popularTags = const [
    'Action',
    'Romance',
    'Fantasy',
    'Manhwa',
    'Isekai',
    'Comedy',
    'Drama',
    'Adventure',
    'Shounen',
    'Sci-Fi',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _loadRecentSearches();

    // Tunggu transisi morph container selesai (~300ms) sebelum memunculkan keyboard
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _loadRecentSearches() {
    setState(() {
      _recentSearches = LocalStorage.getRecentSearches();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submitSearch(String queryText) async {
    final query = queryText.trim();
    if (query.isEmpty) return;

    await LocalStorage.addRecentSearch(query);

    if (!mounted) return;

    _focusNode.unfocus();
    Navigator.pushReplacement(
      context,
      PredictiveBackPageRoute(
        builder: (_) => SearchScreen(initialQuery: query),
      ),
    );
  }

  /// Menampilkan saran instan dari manga yang pernah dibaca / difavoritkan
  List<Map<String, dynamic>> _getLocalSuggestions(String query) {
    if (query.trim().isEmpty) return [];
    final lower = query.toLowerCase();

    final results = <Map<String, dynamic>>[];
    final seen = <String>{};

    // Ambil dari favorit
    for (final item in LocalStorage.getFavorites()) {
      final title = (item['title'] as String? ?? '').toLowerCase();
      final slug = item['slug'] as String? ?? '';
      if (title.contains(lower) && !seen.contains(slug)) {
        seen.add(slug);
        results.add(item);
        if (results.length >= 6) return results;
      }
    }

    // Ambil dari riwayat
    for (final item in LocalStorage.getHistory()) {
      final title = (item['title'] as String? ?? '').toLowerCase();
      final slug = item['slug'] as String? ?? '';
      if (title.contains(lower) && !seen.contains(slug)) {
        seen.add(slug);
        results.add(item);
        if (results.length >= 6) return results;
      }
    }

    return results;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentText = _controller.text;
    final localMatches = _getLocalSuggestions(currentText);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Search Header (Material 3 Search View AppBar)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Kembali',
                      onPressed: () {
                        _focusNode.unfocus();
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Cari manga...',
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (v) => setState(() {}),
                        onSubmitted: _submitSearch,
                      ),
                    ),
                    if (currentText.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Hapus',
                        onPressed: () {
                          _controller.clear();
                          setState(() {});
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.search_rounded),
                      tooltip: 'Cari',
                      color: theme.colorScheme.primary,
                      onPressed: () => _submitSearch(_controller.text),
                    ),
                  ],
                ),
              ),

            // 2. Horizontal Genre & Tag Populer Chips (di bawah search bar ala Kotatsu Redo)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _popularTags.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final tag = _popularTags[index];
                  return ActionChip(
                    avatar: const Icon(Icons.tag_rounded, size: 14),
                    label: Text(
                      tag,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    backgroundColor: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                    onPressed: () {
                      _controller.text = tag;
                      _submitSearch(tag);
                    },
                  );
                },
              ),
            ),

            // 3. Search Suggestions Content (Saran Pencarian Seragam)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // A. Hasil pratinjau cepat jika sedang mengetik
                  if (currentText.isNotEmpty && localMatches.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        'Saran Komik',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    ...localMatches.map((item) {
                      final title = item['title'] as String? ?? '';
                      final slug = item['slug'] as String? ?? '';
                      final source = item['source'] as String? ?? 'shinigami';
                      final cover = item['cover'] as String?;

                      return ListTile(
                        leading: const Icon(Icons.menu_book_rounded, size: 20),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5),
                        ),
                        subtitle: Text(
                          source,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: const Icon(Icons.north_west_rounded, size: 16),
                        onTap: () {
                          _focusNode.unfocus();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MangaDetailsScreen(
                                slug: slug,
                                source: source,
                                title: title,
                                cover: cover,
                              ),
                            ),
                          );
                        },
                      );
                    }),
                    const Divider(height: 16),
                  ],

                  // B. Riwayat Pencarian Terakhir (Recent Searches)
                  if (_recentSearches.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Pencarian Terakhir',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              await LocalStorage.clearRecentSearches();
                              _loadRecentSearches();
                            },
                            child: Text(
                              'Hapus Semua',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ..._recentSearches.take(8).map((term) {
                      return ListTile(
                        leading: const Icon(Icons.history_rounded, size: 20),
                        title: Text(term, style: const TextStyle(fontSize: 14.5)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          tooltip: 'Hapus riwayat',
                          onPressed: () async {
                            await LocalStorage.removeRecentSearch(term);
                            _loadRecentSearches();
                          },
                        ),
                        onTap: () {
                          _controller.text = term;
                          _submitSearch(term);
                        },
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
