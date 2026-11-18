import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/models/chapter.dart';
import '../../shared/widgets/floating_navbar.dart';
import '../../shared/widgets/search_overlay_notifier.dart';
import '../auth/pin_lock_screen.dart';
import '../details/manga_details_screen.dart';
import '../explore/explore_screen.dart';
import '../explore/source_view_screen.dart';
import '../favorites/favorites_screen.dart';
import '../feed/feed_screen.dart';
import '../feed/feed_provider.dart';
import '../history/history_screen.dart';
import '../reader/manga_reader_screen.dart';
import '../../core/services/network_service.dart';
import '../../core/services/tracker_notification_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _isLocked = false;

  final GlobalKey<FavoritesScreenState> _favoritesKey = GlobalKey<FavoritesScreenState>();
  final GlobalKey<HistoryScreenState> _historyKey = GlobalKey<HistoryScreenState>();
  final ValueNotifier<bool> _searchOpenNotifier = ValueNotifier<bool>(false);

  late final List<Widget> _screens = [
    HistoryScreen(key: _historyKey),
    FavoritesScreen(
      key: _favoritesKey,
      onExploreTap: () => _onTabSelected(2),
    ),
    const ExploreScreen(),
    FeedScreen(
      onExploreTap: () => _onTabSelected(2),
    ),
  ];

  void _onTabSelected(int index) {
    if (_currentIndex == 1 && index != 1) {
      _favoritesKey.currentState?.resetToFirstTab();
    } else if (index == 1) {
      _favoritesKey.currentState?.resetToFirstTab();
    }
    // Reset scroll Riwayat ke atas sebelum setState — sama persis dengan
    // cara resetToFirstTab di FavoritesScreen (jumpTo dipanggil sebelum rebuild)
    if (index == 0 && _currentIndex != 0) {
      _historyKey.currentState?.scrollToTop();
    }
    setState(() {
      _currentIndex = index;
    });
    final unread = LocalStorage.getTotalUnreadNewChaptersCount();
    TrackerNotificationService.setBadgeCount(unread);
  }

  bool _hasCheckedRestoration = false;

  Future<void> _checkPendingBackgroundUpdates() async {
    await FeedUpdateNotifier.importPendingUpdates();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreSystemUI();
    NetworkService.init();
    NetworkService.isConnectedNotifier.addListener(_onConnectivityChanged);
    if (LocalStorage.isAppLockEnabled() && LocalStorage.getAppLockPin() != null) {
      _isLocked = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndRestoreActiveReaderSession();
        _checkPendingBackgroundUpdates();
        FeedUpdateNotifier.syncTrackedMangaConfig();
        // Cek koneksi awal setelah layout selesai
        if (!NetworkService.isConnected) {
          NetworkService.showNoInternetSnackBar(context);
        }
      });
    }
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    final isOnline = NetworkService.isConnectedNotifier.value;
    if (!isOnline) {
      NetworkService.showNoInternetSnackBar(context);
    } else {
      NetworkService.showBackOnlineSnackBar(context);
    }
  }

  void _checkAndRestoreActiveReaderSession() {
    if (!mounted || _hasCheckedRestoration || _isLocked) return;
    _hasCheckedRestoration = true;

    final session = LocalStorage.getActiveReaderSession();
    if (session == null || session['isOpen'] != true) return;

    // Cek batas kedaluwarsa sesi (maksimal 2 jam setelah background kill)
    final ts = session['timestamp'] as int? ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > const Duration(hours: 2).inMilliseconds) {
      LocalStorage.clearActiveReaderSession();
      return;
    }

    // Segera bersihkan sesi agar tidak terpicu berulang kali
    LocalStorage.clearActiveReaderSession();

    final source = session['source'] as String?;
    final mangaSlug = session['mangaSlug'] as String?;
    final mangaTitle = session['mangaTitle'] as String? ?? '';
    final cover = session['cover'] as String?;
    final chRaw = session['chapter'];
    if (source == null || mangaSlug == null || chRaw == null || chRaw is! Map) return;

    final currentChapter = Chapter.fromJson(Map<String, dynamic>.from(chRaw));
    final chaptersRaw = session['chapters'] as List?;
    final chapters = <Chapter>[];
    if (chaptersRaw != null) {
      for (final item in chaptersRaw) {
        if (item is Map) {
          chapters.add(Chapter.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    if (chapters.isEmpty) {
      chapters.add(currentChapter);
    }

    final page = (session['page'] as num?)?.toInt() ?? 1;
    final pageOffset = (session['pageOffset'] as num?)?.toDouble() ?? 0.0;
    final scrollOffset = (session['scrollOffset'] as num?)?.toDouble() ?? 0.0;
    final rawHeights = session['pageHeights'];
    Map<int, double>? savedHeights;
    if (rawHeights is Map) {
      savedHeights = {};
      rawHeights.forEach((k, v) {
        final idx = int.tryParse(k.toString());
        final h = (v as num?)?.toDouble();
        if (idx != null && h != null) savedHeights![idx] = h;
      });
    }
    final savedRatio = (session['pageOffsetRatio'] as num?)?.toDouble();

    final origin = session['origin'] as String? ?? 'details';
    final detailsOrigin = session['detailsOrigin'] as String? ?? 'source_view';
    final sourceName = session['sourceName'] as String?;
    final navigator = Navigator.of(context);

    if (origin == 'history') {
      // Masuk ke reader langsung dari tab Riwayat (HistoryScreen)
      setState(() {
        _currentIndex = 0; // Pastikan tab aktif adalah Riwayat
      });

      // Langsung dorong MangaReaderScreen (tanpa DetailsScreen)
      // sehingga saat user menekan Back, otomatis kembali ke Riwayat!
      navigator.push(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => MangaReaderScreen(
            source: source,
            mangaSlug: mangaSlug,
            mangaTitle: mangaTitle,
            cover: cover,
            initialChapter: currentChapter,
            chapters: chapters,
            initialPage: page,
            initialPageOffset: pageOffset,
            initialScrollOffset: scrollOffset,
            initialPageHeights: savedHeights,
            initialPageOffsetRatio: savedRatio,
            origin: 'history',
            detailsOrigin: detailsOrigin,
            sourceName: sourceName,
          ),
          transitionDuration: Duration.zero,
        ),
      );
    } else {
      // Masuk ke reader dari MangaDetailsScreen
      // Rekonstruksi rute sebelum DetailsScreen berdasarkan detailsOrigin
      if (detailsOrigin == 'history') {
        _onTabSelected(0);
      } else if (detailsOrigin == 'favorites') {
        _onTabSelected(1);
      } else if (detailsOrigin == 'feed') {
        _onTabSelected(3);
      } else {
        // Default: source_view (Katalog / Browse Source)
        _onTabSelected(2);
        navigator.push(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => SourceViewScreen(
              sourceId: source,
              sourceName: sourceName ?? source,
            ),
            transitionDuration: Duration.zero,
          ),
        );
      }

      // 1. Dorong MangaDetailsScreen di atas rute asalnya
      navigator.push(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => MangaDetailsScreen(
            source: source,
            slug: mangaSlug,
            title: mangaTitle,
            cover: cover,
            origin: detailsOrigin,
            sourceName: sourceName,
          ),
          transitionDuration: Duration.zero,
        ),
      );

      // 2. Dorong MangaReaderScreen di atas DetailsScreen
      navigator.push(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => MangaReaderScreen(
            source: source,
            mangaSlug: mangaSlug,
            mangaTitle: mangaTitle,
            cover: cover,
            initialChapter: currentChapter,
            chapters: chapters,
            initialPage: page,
            initialPageOffset: pageOffset,
            initialScrollOffset: scrollOffset,
            initialPageHeights: savedHeights,
            initialPageOffsetRatio: savedRatio,
            origin: 'details',
            detailsOrigin: detailsOrigin,
            sourceName: sourceName,
          ),
          transitionDuration: Duration.zero,
        ),
      );
    }
  }

  @override
  void dispose() {
    NetworkService.isConnectedNotifier.removeListener(_onConnectivityChanged);
    WidgetsBinding.instance.removeObserver(this);
    _searchOpenNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreSystemUI();
      NetworkService.checkConnection();
      _checkPendingBackgroundUpdates();
    } else if (state == AppLifecycleState.paused) {
      if (LocalStorage.isAppLockEnabled() && LocalStorage.getAppLockPin() != null) {
        setState(() {
          _isLocked = true;
        });
      }
    }
  }

  void _restoreSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return PinLockScreen(
        onUnlock: () {
          setState(() {
            _isLocked = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkAndRestoreActiveReaderSession();
            _checkPendingBackgroundUpdates();
            FeedUpdateNotifier.syncTrackedMangaConfig();
          });
        },
      );
    }

    final indexedStack = IndexedStack(
      index: _currentIndex,
      children: _screens,
    );

    return SearchOverlayNotifier(
      notifier: _searchOpenNotifier,
      child: ListenableBuilder(
      listenable: Listenable.merge([
        LocalStorage.listenSettings(),
        LocalStorage.listenContentMode(),
        LocalStorage.listenFeed(),
      ]),
      child: indexedStack,
      builder: (context, child) {
        final isFloatingNav = LocalStorage.isFloatingNavEnabled();
        final isShowLabels = LocalStorage.isShowNavLabels();
        final activeModeId = LocalStorage.getActiveContentModeId();
        final unreadCount = LocalStorage.getTotalUnreadNewChaptersCount(modeId: activeModeId);

        return PopScope(
          canPop: _currentIndex == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_currentIndex != 0) {
              _onTabSelected(0);
            }
          },
          child: Scaffold(
            body: Stack(
              children: [
                // IndexedStack preserves state of each tab when switching
                child!,

                    // Floating Navigation Bar positioned at bottom with dynamic Feed badge
                    if (isFloatingNav)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: FloatingNavbar(
                          currentIndex: _currentIndex,
                          searchOpenNotifier: _searchOpenNotifier,
                          items: [
                            const FloatingNavbarItem(
                              icon: Icons.history_rounded,
                              activeIcon: Icons.history_toggle_off_rounded,
                              label: 'Riwayat',
                              svgAsset: 'assets/history.svg',
                            ),
                            const FloatingNavbarItem(
                              icon: Icons.favorite_border_rounded,
                              activeIcon: Icons.favorite_rounded,
                              label: 'Disukai',
                            ),
                            const FloatingNavbarItem(
                              icon: Icons.explore_outlined,
                              activeIcon: Icons.explore_rounded,
                              label: 'Jelajah',
                            ),
                            FloatingNavbarItem(
                              icon: Icons.rss_feed_rounded,
                              activeIcon: Icons.rss_feed_rounded,
                              label: 'Umpan',
                              badgeCount: unreadCount,
                            ),
                          ],
                          showLabels: isShowLabels,
                          onTap: _onTabSelected,
                        ),
                      ),
                  ],
                ),
                bottomNavigationBar: isFloatingNav
                    ? null
                    : FloatingNavbar(
                        isFloating: false,
                        currentIndex: _currentIndex,
                        searchOpenNotifier: _searchOpenNotifier,
                        items: [
                          const FloatingNavbarItem(
                            icon: Icons.history_rounded,
                            activeIcon: Icons.history_toggle_off_rounded,
                            label: 'Riwayat',
                            svgAsset: 'assets/history.svg',
                          ),
                          const FloatingNavbarItem(
                            icon: Icons.favorite_border_rounded,
                            activeIcon: Icons.favorite_rounded,
                            label: 'Disukai',
                          ),
                          const FloatingNavbarItem(
                            icon: Icons.explore_outlined,
                            activeIcon: Icons.explore_rounded,
                            label: 'Jelajah',
                          ),
                          FloatingNavbarItem(
                            icon: Icons.rss_feed_rounded,
                            activeIcon: Icons.rss_feed_rounded,
                            label: 'Umpan',
                            badgeCount: unreadCount,
                          ),
                        ],
                        showLabels: isShowLabels,
                        onTap: _onTabSelected,
                      ),
          ),
        );
      },
    ),
    );
  }
}
