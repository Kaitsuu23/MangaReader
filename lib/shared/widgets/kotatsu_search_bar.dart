import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/in_place_predictive_back_page_transitions_builder.dart';
import '../../features/explore/search_screen.dart';
import '../../features/details/manga_details_screen.dart';
import 'search_overlay_notifier.dart';

/// Search bar kapsul Material 3 seragam untuk semua layar.
class KotatsuSearchBar extends StatelessWidget {
  final Widget trailingMenu;
  final String hintText;

  const KotatsuSearchBar({
    super.key,
    required this.trailingMenu,
    this.hintText = 'Cari manga',
  });

  void _openSearchView(BuildContext context) {
    final notifier = SearchOverlayNotifier.of(context);
    notifier?.value = true;

    final suppressKeyboard = ValueNotifier<bool>(false);

    Navigator.of(context).push(
      _SearchOverlayRoute(
        builder: (context) => _SearchOverlayWrapper(
          suppressKeyboard: suppressKeyboard,
          child: KotatsuSearchView(suppressKeyboard: suppressKeyboard),
        ),
      ),
    ).whenComplete(() {
      notifier?.value = false;
      suppressKeyboard.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    hintText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 14.5,
                    ),
                  ),
                ),
                trailingMenu,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Route ────────────────────────────────────────────────────────────────────

/// PageRoute yang pakai Flutter's built-in PredictiveBackPageTransitionsBuilder.
/// Menghasilkan animasi Android 14+ predictive back persis:
/// scale 0.90, miring ke kiri/kanan sesuai swipe edge, Y shift vertikal,
/// corner radius device.
class _SearchOverlayRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;

  _SearchOverlayRoute({required this.builder});

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return const PredictiveBackPageTransitionsBuilder().buildTransitions(
      this,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

// ── Keyboard suppressor ───────────────────────────────────────────────────────

/// Wrapper tipis yang hanya handle suppression keyboard saat predictive back.
/// Tidak ada animasi sendiri — semua animasi dari _SearchOverlayRoute.
class _SearchOverlayWrapper extends StatefulWidget {
  final Widget child;
  final ValueNotifier<bool> suppressKeyboard;

  const _SearchOverlayWrapper({
    required this.suppressKeyboard,
    required this.child,
  });

  @override
  State<_SearchOverlayWrapper> createState() => _SearchOverlayWrapperState();
}

class _SearchOverlayWrapperState extends State<_SearchOverlayWrapper>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    // Suppress keyboard segera saat gesture dimulai
    widget.suppressKeyboard.value = true;
    return false; // biarkan route handle animasi dan pop
  }

  @override
  void handleCancelBackGesture() {
    // Gesture dibatalkan — izinkan keyboard kembali
    if (mounted) widget.suppressKeyboard.value = false;
  }

  @override
  void handleCommitBackGesture() {
    // Route akan di-pop otomatis oleh Flutter
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Search View ───────────────────────────────────────────────────────────────

/// Layar penuh pencarian.
class KotatsuSearchView extends StatefulWidget {
  final String? initialQuery;

  /// Set true saat predictive back gesture aktif — field tidak akan request keyboard.
  final ValueNotifier<bool>? suppressKeyboard;

  const KotatsuSearchView({
    super.key,
    this.initialQuery,
    this.suppressKeyboard,
  });

  @override
  State<KotatsuSearchView> createState() => _KotatsuSearchViewState();
}

class _KotatsuSearchViewState extends State<KotatsuSearchView> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  List<String> _recentSearches = [];

  final List<String> _popularTags = const [
    'Action', 'Romance', 'Fantasy', 'Manhwa', 'Isekai',
    'Comedy', 'Drama', 'Adventure', 'Shounen', 'Sci-Fi',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _loadRecentSearches();
    widget.suppressKeyboard?.addListener(_onSuppressChanged);

    // Minta keyboard setelah transisi masuk selesai
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted && widget.suppressKeyboard?.value != true) {
        _focusNode.requestFocus();
      }
    });
  }

  void _onSuppressChanged() {
    if (widget.suppressKeyboard?.value == true) {
      // Force-hide IME via platform channel saat gesture back dimulai
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      _focusNode.unfocus();
    }
  }

  void _loadRecentSearches() {
    setState(() {
      _recentSearches = LocalStorage.getRecentSearches();
    });
  }

  @override
  void dispose() {
    widget.suppressKeyboard?.removeListener(_onSuppressChanged);
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

  List<Map<String, dynamic>> _getLocalSuggestions(String query) {
    if (query.trim().isEmpty) return [];
    final lower = query.toLowerCase();
    final results = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final item in LocalStorage.getFavorites()) {
      final title = (item['title'] as String? ?? '').toLowerCase();
      final slug = item['slug'] as String? ?? '';
      if (title.contains(lower) && seen.add(slug)) {
        results.add(item);
        if (results.length >= 6) return results;
      }
    }
    for (final item in LocalStorage.getHistory()) {
      final title = (item['title'] as String? ?? '').toLowerCase();
      final slug = item['slug'] as String? ?? '';
      if (title.contains(lower) && seen.add(slug)) {
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
            // Header
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

            // Tag chips
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

            // Suggestions
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
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
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
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
                              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.primary),
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
