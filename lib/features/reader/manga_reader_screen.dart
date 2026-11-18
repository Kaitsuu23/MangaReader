import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/widgets/cached_cover.dart';
import '../../shared/widgets/webtoon_safe_image.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';
import '../../core/services/sync_service.dart';
import '../../shared/models/chapter.dart';
import '../../shared/models/chapter_pages.dart';
import '../../shared/models/manga_source.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/predictive_back_bottom_sheet.dart';
import '../../shared/widgets/reader_mode_icons.dart';
import '../../shared/widgets/sliced_page_image.dart';
import '../../core/services/network_service.dart';
import '../translator/widgets/reader_page_translator_wrapper.dart';
import '../translator/widgets/translation_settings_sheet.dart';
import '../translator/providers/translator_settings_provider.dart';

enum ReaderMode { webtoon, pagedLtr, pagedRtl, verticalPager }

/// Kotatsu Redo: Struktur pasangan halaman untuk Double-Page Spread di mode Lanskap
class _PageSpread {
  final int firstIndex;
  final int? secondIndex;

  const _PageSpread(this.firstIndex, [this.secondIndex]);

  bool get isDual => secondIndex != null;
}

class MangaReaderScreen extends ConsumerStatefulWidget {
  final String mangaTitle;
  final String mangaSlug;
  final String source;
  final String? cover;
  final List<Chapter> chapters;
  final Chapter initialChapter;
  final int initialPage; // 1-indexed, 0 = start from beginning
  final double initialPageOffset; // pixels from the top of initialPage
  final double initialScrollOffset; // absolute webtoon ListView offset
  final String origin; // 'details' or 'history'
  final String detailsOrigin; // 'source_view', 'history', 'favorites', 'feed', 'explore'
  final String? sourceName;

  final Map<int, double>? initialPageHeights;
  final double? initialPageOffsetRatio;
  final bool startAtEnd;

  const MangaReaderScreen({
    super.key,
    required this.mangaTitle,
    required this.mangaSlug,
    required this.source,
    this.cover,
    required this.chapters,
    required this.initialChapter,
    this.initialPage = 0,
    this.initialPageOffset = 0,
    this.initialScrollOffset = 0,
    this.initialPageHeights,
    this.initialPageOffsetRatio,
    this.startAtEnd = false,
    this.origin = 'details',
    this.detailsOrigin = 'source_view',
    this.sourceName,
  });

  @override
  ConsumerState<MangaReaderScreen> createState() => _MangaReaderScreenState();
}

class _MangaReaderScreenState extends ConsumerState<MangaReaderScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _deviceChannel = MethodChannel('org.dhiksn.yomika/device');
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  late Chapter _currentChapter;
  late List<Chapter> _chapters;
  ChapterPages? _chapterPages;
  bool _isLoading = true;
  String? _error;

  ReaderMode _readerMode = ReaderMode.webtoon;
  String _activeCdn = 'cdn1';
  int _activeServer = 1;
  bool _showControls = true;
  int _currentPageIndex = 0; // 0-indexed
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(0);
  final TransformationController _webtoonTransformController = TransformationController();
  final ValueNotifier<bool> _isWebtoonZoomedNotifier = ValueNotifier<bool>(false);

  Timer? _statusBarAutoHideTimer;

  void _hideStatusBarNow() {
    _statusBarAutoHideTimer?.cancel();
    if (!mounted || _showControls) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _deviceChannel.invokeMethod('setReaderImmersive', {'enable': true});
    _deviceChannel.invokeMethod('hideStatusBar');
  }

  void _scheduleStatusBarAutoHide({Duration duration = const Duration(milliseconds: 2000)}) {
    _statusBarAutoHideTimer?.cancel();
    if (_showControls || !mounted) return;
    _statusBarAutoHideTimer = Timer(duration, () {
      if (mounted && !_showControls) {
        _hideStatusBarNow();
      }
    });
  }

  // Per-page item heights for accurate webtoon tracking
  final Map<int, double> _pageHeights = {};
  double _estimatedPageHeight = 1200.0;

  /// Track which pages failed to load so they can be reloaded automatically when internet reconnects.
  final Set<int> _failedPageIndices = {};
  /// Per-page retry counter to force fresh widget state when retrying.
  final Map<int, int> _pageRetryCounters = {};
  int _globalRetryCounter = 0;

  /// Keys for the page items, so resume can anchor on the real position of a
  /// page instead of summing estimated heights.
  final Map<int, GlobalKey> _pageKeys = {};
  bool _resumeFollowAnchor = false;
  bool _resumeAnchorScheduled = false;
  Timer? _resumeFollowTimer;
  int _resumeStableFrames = 0;

  late final PageController _pageController;
  final ScrollController _scrollController = ScrollController();

  // Battery & Clock HUD
  Timer? _clockTimer;
  Timer? _batteryTimer;
  late final ValueNotifier<String> _currentTimeNotifier;
  late final ValueNotifier<int?> _batteryLevelNotifier;

  // Screen orientation & Double-Page Spread (Kotatsu Redo)
  String _orientationSetting = 'system';
  bool _dualPageInLandscape = true;
  bool _shiftFirstPageCover = true;

  // Auto-scroll
  bool _autoScrollEnabled = false;
  double _autoScrollSpeed = 0.4; // 0.1 - 3.0
  bool _showFloatingControl = true;
  bool _isAutoScrollPaused = false;
  bool _tapNavigationEnabled = true;
  bool _isSavingPage = false;
  bool _isSharingPage = false;
  bool _isPopupMenuOpen = false;

  // Reading Statistics Session
  DateTime _sessionStartTime = DateTime.now();
  int _sessionInitialPage = 0;
  bool _showAutoScrollPanel = false;
  Timer? _autoScrollTimer;
  Ticker? _autoScrollTicker;
  Duration _lastTickerElapsed = Duration.zero;

  // Slider drag & jump state
  bool _isSliderDragging = false;
  int? _webtoonJumpTargetIndex;
  Timer? _webtoonJumpTimer;
  Timer? _webtoonJumpFollowTimer;
  bool _jumpAnchorScheduled = false;
  int _jumpStableFrames = 0;

  // Precise resume (webtoon)
  bool _resumePending = false;
  bool _applyingResume = false;
  int _resumePageIndex = 0;
  double _resumePageOffset = 0;

  /// Fraction (0..1) of the target page that was already read. Computed once at
  /// load time so it survives page heights changing while images load, and so
  /// older history entries without a stored ratio still resume in the right
  /// place (derived from the saved page height).
  double? _resumeRatio;
  final Set<int> _loadedPages = {};
  Timer? _progressSaveDebounce;
  Timer? _resumeSettleTimer;
  Timer? _controlsAutoHideTimer;
  int _resumeFrameTries = 0;
  bool _isChangingChapter = false;
  bool _targetInitialPageAtEnd = false;
  bool _isExiting = false;
  double _lastKnownScrollOffset = 0.0;
  bool _isAtEndKnown = false;
  bool _resumeToEnd = false;

  // Kotatsu-style Pull-to-Chapter Gestures
  static const double _pullThreshold = 85.0;
  final ValueNotifier<double> _pullTopNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _pullBottomNotifier = ValueNotifier<double>(0.0);
  bool _isUserDragging = false;
  bool _isHapticTriggeredTop = false;
  bool _isHapticTriggeredBottom = false;
  double _accumulatedOverscrollTop = 0.0;
  double _accumulatedOverscrollBottom = 0.0;
  bool _pullGestureEnabled = true;

  // Smooth Tap Navigation Chaining (Kotatsu-Redo)
  double? _targetScrollOffset;
  int? _targetPageIndex;

  // Kotatsu-style Chapter Announcement Toast (ReaderToastView)
  bool _chapterToastEnabled = true;
  AnimationController? _toastAnimController;
  Animation<double>? _toastFadeAnim;
  Animation<double>? _toastScaleAnim;
  String _toastMessage = '';
  Timer? _toastHideTimer;

  void _showChapterToast(String title) {
    if (!_chapterToastEnabled || title.trim().isEmpty) return;
    _toastHideTimer?.cancel();
    if (mounted) {
      setState(() {
        _toastMessage = title;
      });
      _toastAnimController?.forward(from: 0.0);
      _toastHideTimer = Timer(const Duration(milliseconds: 2000), () {
        if (mounted) {
          _toastAnimController?.reverse();
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.initialChapter;
    _chapters = Chapter.sortChronological(widget.chapters);
    if (_chapters.length <= 1) {
      _fetchFullChapterList();
    }
    _pageController = PageController();

    final savedMode = LocalStorage.getReaderMode();
    _readerMode = _parseReaderMode(savedMode);
    _activeCdn = LocalStorage.getReaderCdn();
    _activeServer = LocalStorage.getShinigamiServer();
    _tapNavigationEnabled = LocalStorage.isTapNavigationEnabled();
    _chapterToastEnabled = LocalStorage.isReaderChapterToastEnabled();
    _pullGestureEnabled = LocalStorage.isPullGestureEnabled();

    _toastAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 250),
    );
    _toastFadeAnim = CurvedAnimation(
      parent: _toastAnimController!,
      curve: Curves.decelerate,
      reverseCurve: Curves.easeIn,
    );
    _toastScaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _toastAnimController!,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );

    _currentTimeNotifier = ValueNotifier<String>('');
    _batteryLevelNotifier = ValueNotifier<int?>(null);

    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _updateClock());

    _getBatteryLevel();
    _batteryTimer = Timer.periodic(const Duration(seconds: 30), (_) => _getBatteryLevel());

    // Sembunyikan status bar & navigasi Android (immersive mode)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _deviceChannel.invokeMethod('setReaderImmersive', {'enable': true});

    // Auto-hide status bar jika muncul karena peek/swipe notifikasi dari atas layar
    SystemChrome.setSystemUIChangeCallback((systemOverlaysAreVisible) async {
      if (systemOverlaysAreVisible && mounted && !_showControls) {
        _scheduleStatusBarAutoHide();
      }
    });

    // Terapkan Orientasi Layar & Double-Page Spread dari Pengaturan (Kotatsu Redo)
    final savedOrientation = LocalStorage.getReaderOrientation();
    _orientationSetting = savedOrientation;
    _applyOrientation(savedOrientation);
    _dualPageInLandscape = LocalStorage.isDualPageInLandscape();
    _shiftFirstPageCover = LocalStorage.isShiftFirstPageCover();

    // Cegah Layar Mati jika diaktifkan di pengaturan
    if (LocalStorage.isKeepScreenOn()) {
      _deviceChannel.invokeMethod('setKeepScreenOn', {'enable': true});
    }

    // Registrasi sesi reader aktif agar bisa dipulihkan jika aplikasi tertutup/di-background
    LocalStorage.saveActiveReaderSession({
      'source': widget.source,
      'mangaSlug': widget.mangaSlug,
      'mangaTitle': widget.mangaTitle,
      'cover': widget.cover,
      'chapter': widget.initialChapter.toJson(),
      'chapters': widget.chapters.map((c) => c.toJson()).toList(),
      'page': widget.initialPage > 0 ? widget.initialPage : 1,
      'pageOffset': widget.initialPageOffset,
      'pageOffsetRatio': widget.initialPageOffsetRatio,
      'scrollOffset': widget.initialScrollOffset,
      'pageHeights': widget.initialPageHeights?.map((k, v) => MapEntry(k.toString(), v)),
      'origin': widget.origin,
      'detailsOrigin': widget.detailsOrigin,
      'sourceName': widget.sourceName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'isOpen': true,
    });

    WidgetsBinding.instance.addObserver(this);
    NetworkService.isConnectedNotifier.addListener(_onConnectivityChanged);
    _targetInitialPageAtEnd = widget.startAtEnd;
    _loadChapterPages(isInitial: true);
    _scrollController.addListener(_onWebtoonScroll);
    _webtoonTransformController.addListener(_onWebtoonTransformChanged);

    // Auto-hide controls setelah 3 detik saat masuk ke manga reader
    _scheduleAutoHideControls(duration: const Duration(seconds: 3));
  }

  void _onWebtoonTransformChanged() {
    final scale = _webtoonTransformController.value.getMaxScaleOnAxis();
    final isZoomed = scale > 1.02;
    if (_isWebtoonZoomedNotifier.value != isZoomed) {
      _isWebtoonZoomedNotifier.value = isZoomed;
    }
  }

  void _exitReader() {
    _isExiting = true;
    if (!_resumePending && !_applyingResume) {
      _saveProgress(isClosing: true);
    }
    LocalStorage.clearActiveReaderSession();
    if (mounted) Navigator.pop(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted && !_showControls) {
        _scheduleStatusBarAutoHide(duration: const Duration(milliseconds: 300));
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _saveProgress();
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      if (!_showControls) {
        try {
          final topPadding = View.of(context).viewPadding.top;
          if (topPadding > 0) {
            _scheduleStatusBarAutoHide(duration: const Duration(milliseconds: 1500));
          }
        } catch (_) {}
      }
      // Sinkronkan halaman PageView saat orientasi layar berganti antara Potret dan Lanskap
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_readerMode != ReaderMode.webtoon && _pageController.hasClients) {
          if (_isDualPageActive) {
            final spreads = _currentSpreads;
            final targetSpread = _spreadIndexForPage(_currentPageIndex, spreads);
            if (_pageController.hasClients && _pageController.page?.round() != targetSpread) {
              _pageController.jumpToPage(targetSpread);
            }
          } else {
            if (_pageController.hasClients && _pageController.page?.round() != _currentPageIndex) {
              _pageController.jumpToPage(_currentPageIndex);
            }
          }
        }
      });
    }
  }

  ReaderMode _parseReaderMode(String mode) {
    switch (mode) {
      case 'paged_ltr': return ReaderMode.pagedLtr;
      case 'paged_rtl': return ReaderMode.pagedRtl;
      case 'vertical':  return ReaderMode.verticalPager;
      default:          return ReaderMode.webtoon;
    }
  }

  String _serializeReaderMode(ReaderMode mode) {
    switch (mode) {
      case ReaderMode.pagedLtr:      return 'paged_ltr';
      case ReaderMode.pagedRtl:      return 'paged_rtl';
      case ReaderMode.verticalPager: return 'vertical';
      case ReaderMode.webtoon:       return 'webtoon';
    }
  }

  bool _isHashOrInvalidChapter(Chapter ch) {
    final s = ch.slug.trim();
    if (s.isEmpty) return true;
    // Kotatsu 64-bit integer hash ID (contoh: 6516582176887332904)
    if (int.tryParse(s) != null && s.length >= 8) return true;
    final c = ch.chapter.trim();
    if (int.tryParse(c) != null && c.length >= 8) return true;
    return false;
  }

  Future<void> _fetchFullChapterList() async {
    try {
      final cleanSlug = widget.mangaSlug.trim().replaceAll(RegExp(r'^/+|/+$'), '').replaceFirst(RegExp(r'^manga/', caseSensitive: false), '').replaceAll(RegExp(r'^/+|/+$'), '');
      final effectiveMangaSlug = cleanSlug.isNotEmpty ? cleanSlug : widget.mangaSlug;
      final api = ref.read(parserChannelProvider);
      final details = await api.getDetails(widget.source, effectiveMangaSlug);
      if (!mounted) return;
      if (details.chapters.isNotEmpty) {
        final sorted = Chapter.sortChronological(details.chapters);
        _chapters = sorted;
        final idx = _findChapterIndex(_currentChapter);
        if (idx != -1) {
          _currentChapter = sorted[idx];
        } else {
          // Jika chapter hash tidak cocok, cocokkan berdasarkan riwayat baca lokal / sinkronisasi
          final hist = LocalStorage.getHistoryItem(effectiveMangaSlug, source: widget.source) ?? LocalStorage.getHistoryItem(widget.mangaSlug, source: widget.source);
          final percent = (hist?['percent'] as num?)?.toDouble() ?? 0.0;
          if (percent >= 0.999) {
            _currentChapter = sorted.last;
          } else if (percent > 0) {
            final targetIdx = (percent * sorted.length).floor().clamp(0, sorted.length - 1);
            _currentChapter = sorted[targetIdx];
          } else {
            _currentChapter = sorted.first;
          }
        }
        // Perbarui riwayat lokal dengan slug bab sebenarnya agar pembacaan berikutnya langsung tepat
        final hist = LocalStorage.getHistoryItem(effectiveMangaSlug, source: widget.source) ?? LocalStorage.getHistoryItem(widget.mangaSlug, source: widget.source);
        final histChSlug = hist?['chapterSlug']?.toString().trim() ?? '';
        final cleanHist = histChSlug.replaceAll(RegExp(r'^/+|/+$'), '');
        final cleanCurSlug = _currentChapter.slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
        final cleanCurCh = _currentChapter.chapter.trim().replaceAll(RegExp(r'^/+|/+$'), '');
        final histTitle = hist?['chapterTitle']?.toString() ?? '';
        final histNum = (hist?['chapterNumber'] as num?)?.toDouble() ??
            double.tryParse(RegExp(r'(?:Chapter|Bab|Ch\.?|Episode|Ep\.?)\s*([0-9.]+)', caseSensitive: false).firstMatch(histTitle)?.group(1) ?? '') ??
            double.tryParse(RegExp(r'([0-9.]+)').firstMatch(histTitle)?.group(1) ?? '');
        final curNum = _currentChapter.chapterNumber ??
            double.tryParse(RegExp(r'(?:Chapter|Bab|Ch\.?|Episode|Ep\.?)\s*([0-9.]+)', caseSensitive: false).firstMatch(_currentChapter.title)?.group(1) ?? '') ??
            double.tryParse(RegExp(r'([0-9.]+)').firstMatch(_currentChapter.title)?.group(1) ?? '') ??
            double.tryParse(RegExp(r'([0-9.]+)').firstMatch(_currentChapter.chapter)?.group(1) ?? '');
        final sameNumber = histNum != null && curNum != null && (histNum - curNum).abs() < 0.01;
        final sameTitle = histTitle.isNotEmpty && _currentChapter.title.trim().toLowerCase() == histTitle.trim().toLowerCase();
        final isHashSlug = cleanHist.length >= 8 && int.tryParse(cleanHist) != null;
        final isHashMatch = isHashSlug && (
          SyncService.hashSlug(_currentChapter.slug).toString() == cleanHist ||
          SyncService.hashSlug(_currentChapter.chapter).toString() == cleanHist
        );

        final isSameChapter = (histChSlug.isNotEmpty && (
          _currentChapter.slug == histChSlug ||
          _currentChapter.chapter == histChSlug ||
          cleanCurSlug == cleanHist ||
          cleanCurCh == cleanHist ||
          isHashMatch
        )) || sameNumber || sameTitle;

        final curIdx = _chapters.isNotEmpty ? _findChapterIndex(_currentChapter) : -1;
        final isLastCh = _chapters.isNotEmpty && curIdx == _chapters.length - 1;
        final histPct = (hist?['percent'] as num?)?.toDouble() ?? 0.0;
        final isCompleted = isSameChapter && isLastCh && histPct >= 0.99;

        final savedPage = isSameChapter
            ? (widget.initialPage > 0 ? widget.initialPage : (hist?['page'] as num?)?.toInt() ?? 1)
            : (widget.initialPage > 0 ? widget.initialPage : 1);
        final savedTotalPages = isSameChapter ? ((hist?['totalPages'] as num?)?.toInt() ?? 1) : 1;
        final savedOffset = isSameChapter
            ? (widget.initialPageOffset > 0 ? widget.initialPageOffset : (hist?['pageOffset'] as num?)?.toDouble() ?? 0)
            : (widget.initialPageOffset > 0 ? widget.initialPageOffset : 0.0);
        final savedScroll = isSameChapter
            ? (widget.initialScrollOffset > 0 ? widget.initialScrollOffset : (hist?['scrollOffset'] as num?)?.toDouble() ?? 0)
            : (widget.initialScrollOffset > 0 ? widget.initialScrollOffset : 0.0);
        final savedHeights = isSameChapter
            ? (widget.initialPageHeights ?? (hist?['pageHeights'] is Map ? (hist!['pageHeights'] as Map).map((k, v) => MapEntry(int.tryParse(k.toString()) ?? 0, (v as num).toDouble())) : null))
            : widget.initialPageHeights;
        final savedRatio = isSameChapter
            ? (widget.initialPageOffsetRatio ?? (hist?['pageOffsetRatio'] as num?)?.toDouble())
            : widget.initialPageOffsetRatio;
        final savedPercent = isSameChapter ? (hist?['percent'] as num?)?.toDouble() : null;

        LocalStorage.saveHistory(
          slug: effectiveMangaSlug,
          title: widget.mangaTitle,
          cover: widget.cover,
          source: widget.source,
          chapterSlug: _currentChapter.slug,
          chapterTitle: _currentChapter.title,
          page: savedPage,
          totalPages: savedTotalPages,
          pageOffset: savedOffset,
          scrollOffset: savedScroll,
          pageHeights: savedHeights,
          pageOffsetRatio: savedRatio,
          percent: savedPercent,
          totalChapters: _chapters.isNotEmpty ? _chapters.length : null,
        );
        if (_chapters.isNotEmpty && curIdx >= 0) {
          final endIdx = isCompleted ? _chapters.length : curIdx;

          final toMarkRead = <String>[];
          for (int i = 0; i < endIdx; i++) {
            final c = _chapters[i];
            if (c.slug.isNotEmpty) {
              toMarkRead.add(c.slug);
              toMarkRead.add(SyncService.hashSlug(c.slug).toString());
            }
            if (c.chapter.isNotEmpty) {
              toMarkRead.add(c.chapter);
              toMarkRead.add(SyncService.hashSlug(c.chapter).toString());
            }
          }

          final toMarkUnread = <String>[];
          if (!isCompleted) {
            for (int i = curIdx + 1; i < _chapters.length; i++) {
              final c = _chapters[i];
              if (c.slug.isNotEmpty) {
                toMarkUnread.add(c.slug);
                toMarkUnread.add(SyncService.hashSlug(c.slug).toString());
              }
              if (c.chapter.isNotEmpty) {
                toMarkUnread.add(c.chapter);
                toMarkUnread.add(SyncService.hashSlug(c.chapter).toString());
              }
            }
          }

          if (toMarkRead.isNotEmpty || toMarkUnread.isNotEmpty) {
            LocalStorage.setReadChaptersUpTo(
              mangaSlug: effectiveMangaSlug,
              readSlugs: toMarkRead,
              unreadSlugs: toMarkUnread,
              source: widget.source,
            );
          }
        }
        setState(() {});
      }
    } catch (e) {
      debugPrint('[MangaReader] Error fetching full chapter list: $e');
    }
  }

  int _findChapterIndex(Chapter target) {
    if (_chapters.isEmpty) return -1;
    // 1. Berdasarkan slug persis
    int idx = _chapters.indexWhere((c) => c.slug.isNotEmpty && c.slug == target.slug);
    if (idx != -1) return idx;

    // 2. Berdasarkan slug bersih (hapus trailing / leading slash)
    final cleanTarget = target.slug.replaceAll(RegExp(r'^/+|/+$'), '');
    if (cleanTarget.isNotEmpty) {
      idx = _chapters.indexWhere((c) => c.slug.replaceAll(RegExp(r'^/+|/+$'), '') == cleanTarget);
      if (idx != -1) return idx;
    }

    // 3. Berdasarkan string chapter
    if (target.chapter.isNotEmpty) {
      idx = _chapters.indexWhere((c) => c.chapter == target.chapter);
      if (idx != -1) return idx;
    }

    // 4. Berdasarkan FNV-1a Hash ID dari Kotatsu Sync (angka murni panjang)
    final targetSlugTrim = target.slug.trim();
    if (int.tryParse(targetSlugTrim) != null && targetSlugTrim.length >= 8) {
      idx = _chapters.indexWhere((c) {
        final hash1 = SyncService.hashSlug(c.slug).toString();
        final hash2 = SyncService.hashSlug(c.chapter).toString();
        return hash1 == targetSlugTrim || hash2 == targetSlugTrim;
      });
      if (idx != -1) return idx;
    }

    // 5. Berdasarkan nilai numerik chapterNumber (abaikan jika angka hash besar)
    final targetNum = target.chapterNumber;
    if (targetNum != null && targetNum < 100000) {
      idx = _chapters.indexWhere((c) => c.chapterNumber == targetNum);
      if (idx != -1) return idx;
    }

    // 6. Berdasarkan title jika sama persis
    if (target.title.trim().isNotEmpty) {
      final t = target.title.trim().toLowerCase();
      idx = _chapters.indexWhere((c) => c.title.trim().toLowerCase() == t);
      if (idx != -1) return idx;
    }

    // 7. Berdasarkan nomor chapter dari title (Kotatsu findSameChapter regex)
    final match = RegExp(r'(?:chapter|ch\.?|bab)\s*([0-9.]+)', caseSensitive: false).firstMatch(target.title);
    if (match != null) {
      final numVal = double.tryParse(match.group(1)!);
      if (numVal != null && numVal > 0 && numVal < 100000) {
        idx = _chapters.indexWhere((c) => c.chapterNumber == numVal);
        if (idx != -1) return idx;
      }
    }

    return -1;
  }

  bool get _hasNextChapter {
    final idx = _findChapterIndex(_currentChapter);
    return idx != -1 && idx < _chapters.length - 1;
  }

  bool get _hasPreviousChapter {
    final idx = _findChapterIndex(_currentChapter);
    return idx > 0;
  }

  Chapter? get _nextChapter {
    final idx = _findChapterIndex(_currentChapter);
    if (idx != -1 && idx < _chapters.length - 1) {
      return _chapters[idx + 1];
    }
    return null;
  }

  Chapter? get _previousChapter {
    final idx = _findChapterIndex(_currentChapter);
    if (idx > 0) {
      return _chapters[idx - 1];
    }
    return null;
  }

  void _updateClock() {
    if (!mounted) return;
    _currentTimeNotifier.value = DateFormat('HH.mm').format(DateTime.now());
  }

  Future<void> _getBatteryLevel() async {
    try {
      final int level = await _deviceChannel.invokeMethod('getBatteryLevel');
      if (mounted) {
        _batteryLevelNotifier.value = level >= 0 ? level : null;
      }
    } catch (_) {}
  }

  void _applyOrientation(String setting) {
    _orientationSetting = setting;
    if (setting == 'landscape') {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else if (setting == 'portrait') {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      // 'system' or 'sensor': ikuti sensor accelerometer perangkat
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _setOrientation(String setting) {
    _applyOrientation(setting);
    LocalStorage.setReaderOrientation(setting);
    setState(() {});
  }

  // --- Double-Page Spread Engine (Kotatsu Redo) ---
  bool get _isDualPageActive {
    if (!_dualPageInLandscape) return false;
    if (_readerMode != ReaderMode.pagedLtr && _readerMode != ReaderMode.pagedRtl) return false;
    if (!mounted) return false;
    return MediaQuery.orientationOf(context) == Orientation.landscape;
  }

  List<_PageSpread> get _currentSpreads {
    final count = _chapterPages?.pages.length ?? 0;
    return _buildSpreads(count, _isDualPageActive, _shiftFirstPageCover);
  }

  List<_PageSpread> _buildSpreads(int totalPages, bool isDualActive, bool shiftFirstPage) {
    if (totalPages <= 0) return const [];
    if (!isDualActive || totalPages <= 1) {
      return List.generate(totalPages, (i) => _PageSpread(i));
    }

    final spreads = <_PageSpread>[];
    int startIdx = 0;

    if (shiftFirstPage) {
      spreads.add(const _PageSpread(0));
      startIdx = 1;
    }

    for (int i = startIdx; i < totalPages; i += 2) {
      if (i + 1 < totalPages) {
        spreads.add(_PageSpread(i, i + 1));
      } else {
        spreads.add(_PageSpread(i));
      }
    }

    return spreads;
  }

  int _spreadIndexForPage(int pageIndex, List<_PageSpread> spreads) {
    if (spreads.isEmpty) return 0;
    for (int i = 0; i < spreads.length; i++) {
      if (spreads[i].firstIndex == pageIndex || spreads[i].secondIndex == pageIndex) {
        return i;
      }
    }
    return pageIndex.clamp(0, spreads.length - 1);
  }

  String _formatPageDisplay(int pageIndex, int totalPages) {
    if (_isLoading) return '...';
    if (!_isDualPageActive) return '${pageIndex + 1}';
    final spreads = _currentSpreads;
    final spreadIdx = _spreadIndexForPage(pageIndex, spreads);
    if (spreadIdx < 0 || spreadIdx >= spreads.length) return '${pageIndex + 1}';
    final spread = spreads[spreadIdx];
    if (spread.isDual) {
      final pFirst = spread.firstIndex + 1;
      final pSecond = spread.secondIndex! + 1;
      return '$pFirst-$pSecond';
    }
    return '${spread.firstIndex + 1}';
  }

  // --- Auto Scroll Engine ---
  void _startAutoScroll() {
    _stopAutoScroll();
    if (!_autoScrollEnabled || _isAutoScrollPaused) return;

    if (_readerMode == ReaderMode.webtoon) {
      _lastTickerElapsed = Duration.zero;
      _autoScrollTicker = createTicker((Duration elapsed) {
        if (!mounted || !_autoScrollEnabled || _isAutoScrollPaused) {
          _stopAutoScroll();
          return;
        }
        if (_lastTickerElapsed == Duration.zero) {
          _lastTickerElapsed = elapsed;
          return;
        }
        final double dt = (elapsed - _lastTickerElapsed).inMicroseconds / 1000000.0;
        _lastTickerElapsed = elapsed;
        if (dt <= 0.0 || dt > 0.1) return;

        if (_scrollController.hasClients) {
          final maxExtent = _scrollController.position.maxScrollExtent;
          final current = _scrollController.offset;
          // Calibrate pixels per second matching Kotatsu ScrollTimer formula
          final pixelsPerSecond = _autoScrollSpeed * 115.0;
          final step = pixelsPerSecond * dt;
          if (current + step >= maxExtent) {
            _stopAutoScroll();
            _goToNextChapter();
          } else {
            _scrollController.jumpTo(current + step);
          }
        }
      });
      _autoScrollTicker!.start();
    } else {
      final ms = (4000 / _autoScrollSpeed).clamp(1000, 15000).toInt();
      _autoScrollTimer = Timer.periodic(Duration(milliseconds: ms), (timer) {
        if (!mounted || !_autoScrollEnabled || _isAutoScrollPaused) {
          timer.cancel();
          return;
        }
        if (_chapterPages != null && _currentPageIndex < _chapterPages!.pages.length - 1) {
          final nextIndex = _currentPageIndex + 1;
          if (_pageController.hasClients) {
            _pageController.animateToPage(
              nextIndex,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            );
          } else {
            _jumpToPage(nextIndex);
          }
        } else {
          timer.cancel();
          _goToNextChapter();
        }
      });
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollTicker?.stop();
    _autoScrollTicker?.dispose();
    _autoScrollTicker = null;
    _lastTickerElapsed = Duration.zero;
  }

  // Accurate webtoon scroll tracking using cumulative page heights
  void _onWebtoonScroll() {
    if (_chapterPages == null || _chapterPages!.pages.isEmpty) return;
    if (_isSliderDragging) return;
    if (_webtoonJumpTargetIndex != null) return;
    if (_applyingResume) return;
    if (_resumeToEnd) return; // Jangan recalculate page index saat sedang scroll-to-end
    if (_resumePending) return; // Kunci scroll listener saat proses resume posisi berlangsung

    final offset = _scrollController.offset;
    _lastKnownScrollOffset = offset;
    final pages = _chapterPages!.pages;

    if (_showControls && !_isSliderDragging && _webtoonJumpTargetIndex == null && !_showAutoScrollPanel && !_applyingResume) {
      _hideControls();
    }

    final hasContentDims = _scrollController.hasClients && _scrollController.position.hasContentDimensions;
    final maxExtent = hasContentDims ? _scrollController.position.maxScrollExtent : 0.0;
    final extentAfter = hasContentDims ? _scrollController.position.extentAfter : double.infinity;
    // Hanya anggap di ujung akhir jika list memiliki dimensi nyata (maxExtent > 100) dan user memang telah scroll ke bawah (offset > 50)
    final isAtEnd = maxExtent > 100 && offset > 50 && (offset >= maxExtent - 40 || extentAfter <= 40);
    _isAtEndKnown = isAtEnd;

    int newIndex = 0;
    // 1. Jika berada di puncak paling atas (halaman 1)
    if (offset <= 10) {
      newIndex = 0;
    }
    // 2. Jika sudah scroll sampai ujung paling bawah (atau sedang melihat footer selesai)
    else if (isAtEnd) {
      newIndex = pages.length - 1;
    }
    // 3. Posisi halaman yang sedang dibaca di bagian atas layar (scrollOffset)
    else {
      double cumulative = 0.0;
      for (int i = 0; i < pages.length; i++) {
        final h = _pageHeights[i] ?? _estimatedPageHeight;
        if (offset < cumulative + h - 1.0) {
          newIndex = i;
          break;
        }
        cumulative += h;
        newIndex = i;
      }
      newIndex = newIndex.clamp(0, pages.length - 1);
    }

    if (newIndex != _currentPageIndex) {
      _currentPageIndex = newIndex;
      _currentPageNotifier.value = newIndex;
    }
    _scheduleSaveProgress();
  }

  void _onPageHeightMeasured(int index, double height) {
    if (height <= 0) return;
    if (_pageHeights[index] == height) {
      if (_resumePending) _tryApplyWebtoonResume();
      return;
    }
    _pageHeights[index] = height;
    final realHeights = _pageHeights.values.where((h) => h > 100);
    if (realHeights.isNotEmpty) {
      _estimatedPageHeight = realHeights.reduce((a, b) => a + b) / realHeights.length;
    }
    if (_resumePending) {
      _tryApplyWebtoonResume();
    }
    _followResumeAnchor();
    if (_webtoonJumpTargetIndex != null && index <= _webtoonJumpTargetIndex!) {
      _followJumpAnchor();
    }
  }

  void _onPageImageLoaded(int index) {
    if (_loadedPages.add(index)) {
      _prefetchNextPages(index + 1);
      if (_resumePending) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tryApplyWebtoonResume();
        });
      }
      if (_webtoonJumpTargetIndex != null && index <= _webtoonJumpTargetIndex!) {
        _followJumpAnchor();
      }
    }
  }

  /// Downloads and slices the next couple of pages in the background (the same
  /// anticipation Kotatsu's reader does), so scrolling rarely lands on a page
  /// that is still loading.
  void _prefetchNextPages(int start) {
    const lookahead = 3;
    final pages = _chapterPages?.pages;
    if (pages == null || pages.isEmpty) return;
    final end = start + lookahead < pages.length ? start + lookahead : pages.length;
    for (var i = start; i < end; i++) {
      final page = pages[i];
      unawaited(PageSliceCache.instance.load(
        page.url,
        referer: _chapterPages?.referer ?? refererFor(page.url, source: widget.source)['Referer'],
      ));
    }
  }

  void _precacheSurroundingPages(int currentIndex) {
    if (!mounted) return;
    final pages = _chapterPages?.pages;
    if (pages == null || pages.isEmpty) return;

    final targets = [
      currentIndex + 1,
      currentIndex - 1,
    ];

    for (final idx in targets) {
      if (idx >= 0 && idx < pages.length) {
        final url = pages[idx].url;
        if (url.trim().isNotEmpty) {
          final refHeaders = refererFor(url, source: widget.source);
          final headers = <String, String>{
            ...refHeaders,
            if (_chapterPages?.referer != null) 'Referer': _chapterPages!.referer!,
          };
          final provider = CachedNetworkImageProvider(
            url,
            headers: headers,
          );
          precacheImage(provider, context);
        }
      }
    }
  }

  double _currentScrollOffset() {
    if (_readerMode != ReaderMode.webtoon) {
      return 0;
    }
    try {
      if (_scrollController.hasClients && _scrollController.position.hasPixels) {
        _lastKnownScrollOffset = _scrollController.offset;
        return _scrollController.offset;
      }
    } catch (_) {}
    return _lastKnownScrollOffset;
  }

  void _scheduleSaveProgress() {
    if (_resumePending || _applyingResume) return;
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted && !_resumePending && !_applyingResume) _saveProgress();
    });
  }

  /// Fraction of the target page that was already read when the position was
  /// saved.
  ///
  /// Prefers the stored ratio. Older history entries were saved before that
  /// field existed, so fall back to `savedOffset / savedPageHeight` — the
  /// saved height is what the offset was measured against at save time.
  double? _computeResumeRatio(int pageIndex) {
    final ratio = widget.initialPageOffsetRatio;
    if (ratio != null && ratio > 0) {
      return ratio.clamp(0.0, 1.0);
    }
    final savedHeight = widget.initialPageHeights?[pageIndex] ?? _pageHeights[pageIndex];
    if (savedHeight != null && savedHeight > 0 && _resumePageOffset > 0) {
      return (_resumePageOffset / savedHeight).clamp(0.0, 1.0);
    }
    if (pageIndex == 0 && savedHeight != null && savedHeight > 0 && widget.initialScrollOffset > 0) {
      return (widget.initialScrollOffset / savedHeight).clamp(0.0, 1.0);
    }
    return null;
  }

  double _resumeTargetOffset() {
    // Jika target page memiliki tinggi yang diketahui dan ratio tersimpan, sinkronkan offset
    final targetHeight = _pageHeights[_resumePageIndex];
    final ratio = _resumeRatio;
    if (targetHeight != null && targetHeight > 0 && ratio != null && ratio > 0) {
      _resumePageOffset = targetHeight * ratio;
    }
    return _offsetForPage(_resumePageIndex) + _resumePageOffset;
  }

  void _jumpToResumeOffset(double offset) {
    if (!_scrollController.hasClients || offset <= 0) return;
    _applyingResume = true;
    _scrollController.jumpTo(offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyingResume = false;
    });
  }

  /// Scrolls so the saved position *inside* the resume page is at the top of
  /// the viewport.
  ///
  /// The in-page offset is recomputed from the page's real height, so neither
  /// estimated heights nor pages that are still growing around it can pull the
  /// reading position back to the start of the page. Returns the applied scroll
  /// offset, or `null` while the page is not laid out yet.
  double? _applyResumeAnchor() {
    if (!_scrollController.hasClients) return null;
    final box = _pageKeys[_resumePageIndex]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.height <= 0) return null;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      // Jika konten muat seluruhnya di viewport (misal 1 halaman)
      return 0.0;
    }
    final isPageLoaded = _loadedPages.contains(_resumePageIndex);
    final ratio = _resumeRatio;
    if (isPageLoaded && ratio != null && ratio > 0) {
      _resumePageOffset = box.size.height * ratio;
    }
    final anchor = RenderAbstractViewport.of(box)
            .getOffsetToReveal(box, 0.0)
            .offset +
        _resumePageOffset;
    final clamped = anchor.clamp(0.0, maxExtent);
    _jumpToResumeOffset(clamped);
    return clamped;
  }

  void _scheduleResumeFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _resumePending) _tryApplyWebtoonResume();
    });
  }

  void _tryApplyWebtoonResume() {
    if (!_resumePending || !mounted) return;
    if (!_scrollController.hasClients || _chapterPages == null) {
      _scheduleResumeFrame();
      return;
    }

    final lastIndex = _chapterPages!.pages.length - 1;
    if (lastIndex <= 0) {
      _resumePending = false;
      _resumeToEnd = false;
      _resumeFrameTries = 0;
      _resumeStableFrames = 0;
      _saveProgress();
      return;
    }
    _resumePageIndex = _resumePageIndex.clamp(0, lastIndex);

    if (_resumeToEnd) {
      // Kunci info bar & slider di halaman terakhir selama proses scroll-to-end
      _currentPageIndex = lastIndex;
      _currentPageNotifier.value = lastIndex;
      if (_scrollController.hasClients) {
        final pos = _scrollController.position;
        if (pos.hasContentDimensions && pos.maxScrollExtent > 0) {
          _scrollController.jumpTo(pos.maxScrollExtent);
          _lastKnownScrollOffset = pos.maxScrollExtent;
        }
      }
      _resumeFrameTries++;
      final isTargetLoaded = _loadedPages.contains(_resumePageIndex);
      final hasContentDims = _scrollController.hasClients && _scrollController.position.hasContentDimensions;
      final atEnd = hasContentDims && _scrollController.position.extentAfter <= 4.0;

      if (atEnd && isTargetLoaded) {
        _resumeStableFrames++;
      } else {
        _resumeStableFrames = 0;
      }

      if (_resumeStableFrames < 4 && _resumeFrameTries < 300) {
        _scheduleResumeFrame();
        return;
      }

      _resumeToEnd = false;
      _resumeFrameTries = 0;
      _resumeStableFrames = 0;
      _resumePending = false;
      _isAtEndKnown = true;
      // Pastikan tetap di halaman terakhir setelah selesai
      _currentPageIndex = lastIndex;
      _currentPageNotifier.value = lastIndex;
      _onWebtoonScroll();
      return;
    }

    final anchor = _applyResumeAnchor();
    if (anchor == null) {
      // The page is not laid out yet: land near it using the stored heights so
      // the list is forced to build it, then anchor precisely on later frames.
      final bool hasReliableScrollOffset = widget.initialScrollOffset > 10.0;
      final targetJump = hasReliableScrollOffset
          ? widget.initialScrollOffset
          : _resumeTargetOffset();
      _jumpToResumeOffset(targetJump);
    }

    _resumeFrameTries++;
    final isTargetLoaded = _loadedPages.contains(_resumePageIndex);
    final atAnchor = anchor != null &&
        _scrollController.hasClients &&
        (_scrollController.offset - anchor).abs() <= 1;
    final ready = anchor != null && isTargetLoaded && atAnchor;
    _resumeStableFrames = ready ? _resumeStableFrames + 1 : 0;

    // While the target page is still slicing/downloading, do not count frame tries towards timeout
    if (!isTargetLoaded) {
      _resumeFrameTries = 0;
    }

    // Keep anchoring while the pages around the target settle to their real
    // heights; a late-loading page above the target would otherwise push the
    // viewport away from the saved position.
    if (_resumeStableFrames < 6 && _resumeFrameTries < 300) {
      _scheduleResumeFrame();
      return;
    }

    _resumeFrameTries = 0;
    _resumeStableFrames = 0;
    _resumeSettleTimer?.cancel();
    _resumeSettleTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || !_resumePending) return;
      _resumePending = false;
      // Neighbouring pages may still finish measuring after the jump; follow
      // the anchor for a short while so the position does not drift.
      _resumeFollowAnchor = true;
      _resumeFollowTimer?.cancel();
      _resumeFollowTimer = Timer(const Duration(seconds: 15), () {
        _resumeFollowAnchor = false;
      });
      _onWebtoonScroll();
    });
  }

  void _followResumeAnchor() {
    if (!_resumeFollowAnchor || !mounted || _resumeAnchorScheduled) return;
    _resumeAnchorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeAnchorScheduled = false;
      if (!mounted || !_resumeFollowAnchor) return;
      if (!_scrollController.hasClients) return;
      // Never fight the user.
      if (_scrollController.position.isScrollingNotifier.value) return;
      _applyResumeAnchor();
      // Kalau masih ada halaman di atas target yang belum diketahui heightnya,
      // reset timer agar jendela koreksi tetap terbuka sampai semua halaman settled.
      final pagesAbove = _resumePageIndex;
      if (pagesAbove > 0) {
        final missingAbove = List.generate(pagesAbove, (i) => i)
            .any((i) => !_pageHeights.containsKey(i));
        if (missingAbove) {
          _resumeFollowTimer?.cancel();
          _resumeFollowTimer = Timer(const Duration(seconds: 15), () {
            _resumeFollowAnchor = false;
          });
        }
      }
    });
  }

  void _tryApplyPagedResume() {
    if (!_resumePending || !mounted) return;
    if (_pageController.hasClients) {
      if (_isDualPageActive) {
        final spreads = _currentSpreads;
        final spreadIdx = _spreadIndexForPage(_resumePageIndex, spreads);
        _pageController.jumpToPage(spreadIdx);
      } else {
        _pageController.jumpToPage(_resumePageIndex);
      }
      _resumePending = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryApplyPagedResume();
      });
    }
  }

  double _offsetForPage(int index) {
    double offset = 0.0;
    for (int i = 0; i < index; i++) {
      offset += _pageHeights[i] ?? _estimatedPageHeight;
    }
    return offset;
  }

  @override
  void dispose() {
    _isExiting = true;
    _stopAutoScroll();
    _clockTimer?.cancel();
    _batteryTimer?.cancel();
    _currentTimeNotifier.dispose();
    _batteryLevelNotifier.dispose();
    _controlsAutoHideTimer?.cancel();
    _webtoonJumpTimer?.cancel();
    _webtoonJumpFollowTimer?.cancel();
    _toastHideTimer?.cancel();
    _toastAnimController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _progressSaveDebounce?.cancel();
    _resumeSettleTimer?.cancel();
    _resumeFollowTimer?.cancel();
    if (!_resumePending && !_applyingResume) {
      _saveProgress(isClosing: true);
    }
    LocalStorage.clearActiveReaderSession();
    _recordSessionStats();
    NetworkService.isConnectedNotifier.removeListener(_onConnectivityChanged);
    _webtoonTransformController.removeListener(_onWebtoonTransformChanged);
    _webtoonTransformController.dispose();
    _isWebtoonZoomedNotifier.dispose();
    _pullTopNotifier.dispose();
    _pullBottomNotifier.dispose();
    _currentPageNotifier.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    // Kembalikan orientasi layar ke Potret standar aplikasi
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _statusBarAutoHideTimer?.cancel();
    SystemChrome.setSystemUIChangeCallback(null);
    _deviceChannel.invokeMethod('setReaderImmersive', {'enable': false});
    // Kembalikan status bar saat keluar dari reader
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    // Matikan cegah layar mati
    if (LocalStorage.isKeepScreenOn()) {
      _deviceChannel.invokeMethod('setKeepScreenOn', {'enable': false});
    }
    super.dispose();
  }

  Future<void> _loadChapterPages({bool isInitial = false}) async {
    _pageHeights.clear();
    _loadedPages.clear();
    _pageKeys.clear();
    _failedPageIndices.clear();
    _pageRetryCounters.clear();
    _resumeFollowAnchor = false;
    _resumeFollowTimer?.cancel();
    _webtoonJumpTargetIndex = null;
    _webtoonJumpTimer?.cancel();
    _webtoonJumpFollowTimer?.cancel();
    _jumpStableFrames = 0;
    if (!isInitial) {
      _resumePending = false;
      _resumePageOffset = 0;
      _resumeRatio = null;
    } else if (widget.initialPageHeights != null && widget.initialPageHeights!.isNotEmpty) {
      _pageHeights.addAll(widget.initialPageHeights!);
      final real = _pageHeights.values.where((h) => h > 80);
      if (real.isNotEmpty) {
        _estimatedPageHeight = real.reduce((a, b) => a + b) / real.length;
      }
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPageIndex = 0;
      _currentPageNotifier.value = 0;
    });

    try {
      final cleanMangaSlug = widget.mangaSlug.trim().replaceAll(RegExp(r'^/+|/+$'), '').replaceFirst(RegExp(r'^manga/', caseSensitive: false), '').replaceAll(RegExp(r'^/+|/+$'), '');
      final effectiveMangaSlug = cleanMangaSlug.isNotEmpty ? cleanMangaSlug : widget.mangaSlug;

      // Jika bab belum lengkap atau slug bab saat ini adalah ID hash Kotatsu Sync:
      if (_chapters.length <= 1 || _isHashOrInvalidChapter(_currentChapter)) {
        await _fetchFullChapterList();
      }

      final isSoftkomik = widget.source.trim().toLowerCase() == 'softkomik';
      final isShinigami = widget.source.trim().toLowerCase() == 'shinigami';
      final api = ref.read(parserChannelProvider);
      final pages = await api.getPages(
        widget.source,
        effectiveMangaSlug,
        _currentChapter.chapter,
        cdn: isSoftkomik ? _activeCdn : null,
        server: isShinigami ? _activeServer : null,
      );

      if (!mounted) return;
      _pageKeys.clear();
      for (int i = 0; i < pages.pages.length; i++) {
        _pageKeys[i] = GlobalKey();
      }
      if (_pageHeights.isEmpty) {
        _estimatedPageHeight = _readerMode == ReaderMode.webtoon
            ? MediaQuery.sizeOf(context).width * 3.5
            : MediaQuery.sizeOf(context).width * 1.45;
      }
      setState(() {
        _chapterPages = pages;
        _isLoading = false;
        _isChangingChapter = false; // reset so next end-of-chapter can trigger again
      });

      _showChapterToast(_currentChapter.title);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!isInitial && !_targetInitialPageAtEnd) {
          if (_readerMode == ReaderMode.webtoon) {
            if (_scrollController.hasClients) _scrollController.jumpTo(0);
          } else {
            if (_pageController.hasClients) _pageController.jumpToPage(0);
          }
        }
      });

      int initPage = widget.initialPage;
      double initPageOffset = widget.initialPageOffset;
      double initScrollOffset = widget.initialScrollOffset;
      double? initRatio = widget.initialPageOffsetRatio;

      // Fallback: jika reader dibuka tanpa initialPage/initialScrollOffset tapi chapter saat ini cocok dengan riwayat baca
      if (!_targetInitialPageAtEnd && isInitial && initPage <= 0 && initScrollOffset <= 0) {
        final hist = LocalStorage.getHistoryItem(effectiveMangaSlug, source: widget.source) ?? LocalStorage.getHistoryItem(widget.mangaSlug, source: widget.source);
        if (hist != null) {
          final histChSlug = hist['chapterSlug']?.toString().trim() ?? '';
          final cleanHist = histChSlug.replaceAll(RegExp(r'^/+|/+$'), '');
          final cleanCurSlug = _currentChapter.slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
          final cleanCurCh = _currentChapter.chapter.trim().replaceAll(RegExp(r'^/+|/+$'), '');
          final isHashSlug = cleanHist.length >= 8 && int.tryParse(cleanHist) != null;
          final histNum = (hist['chapterNumber'] as num?)?.toDouble();
          final curNum = _currentChapter.chapterNumber;
          final sameNumber = histNum != null && curNum != null && (histNum - curNum).abs() < 0.01;
          final isMatch = (histChSlug.isNotEmpty && (
              _currentChapter.slug == histChSlug ||
              _currentChapter.chapter == histChSlug ||
              cleanCurSlug == cleanHist ||
              cleanCurCh == cleanHist ||
              (isHashSlug && (
                  SyncService.hashSlug(_currentChapter.slug).toString() == cleanHist ||
                  SyncService.hashSlug(_currentChapter.chapter).toString() == cleanHist
              ))
          )) ||
              sameNumber ||
              (hist['chapterTitle'] != null && hist['chapterTitle'].toString().trim().isNotEmpty &&
                  _currentChapter.title.trim().toLowerCase() == hist['chapterTitle'].toString().trim().toLowerCase());
          if (isMatch) {
            final histPct = (hist['percent'] as num?)?.toDouble() ?? 0.0;
            final isCompleted = histPct >= 0.999;
            final chIdx = _findChapterIndex(_currentChapter);
            final isLastCh = _chapters.isNotEmpty && chIdx == _chapters.length - 1;
            if (isCompleted && isLastCh) {
              _targetInitialPageAtEnd = true;
            } else {
              initPage = (hist['page'] as num?)?.toInt() ?? 1;
              initPageOffset = (hist['pageOffset'] as num?)?.toDouble() ?? 0;
              initScrollOffset = (hist['scrollOffset'] as num?)?.toDouble() ?? 0;
              initRatio = (hist['pageOffsetRatio'] as num?)?.toDouble();
              final rawH = hist['pageHeights'];
              if (rawH is Map) {
                final heightsMap = <int, double>{};
                rawH.forEach((k, v) {
                  final idx = int.tryParse(k.toString());
                  final h = (v as num?)?.toDouble();
                  if (idx != null && h != null) heightsMap[idx] = h;
                });
                _pageHeights.addAll(heightsMap);
              }
            }
          }
        }
      }

      if (!_targetInitialPageAtEnd && isInitial && (initPage > 0 || initScrollOffset > 0)) {
        final targetIndex = (initPage > 0 ? initPage - 1 : 0)
            .clamp(0, pages.pages.length - 1);
        _resumePageIndex = targetIndex;
        _resumePageOffset = initPageOffset.clamp(0.0, double.infinity);
        if (_resumePageOffset <= 0 && initScrollOffset > 0) {
          if (targetIndex == 0 && initScrollOffset > 10.0) {
            _resumePageOffset = initScrollOffset;
          } else {
            final pageStart = _offsetForPage(targetIndex);
            if (initScrollOffset > pageStart) {
              _resumePageOffset = initScrollOffset - pageStart;
            }
          }
        }
        _resumeRatio = initRatio ?? _computeResumeRatio(targetIndex);

        _resumeFrameTries = 0;
        _resumePending = true;
        _currentPageIndex = targetIndex;
        _currentPageNotifier.value = targetIndex;
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_readerMode == ReaderMode.webtoon) {
            _tryApplyWebtoonResume();
          } else {
            _tryApplyPagedResume();
          }
        });
      }

      if (_targetInitialPageAtEnd && pages.pages.isNotEmpty) {
        _targetInitialPageAtEnd = false;
        final lastIdx = pages.pages.length - 1;
        _resumePageIndex = lastIdx;
        _resumeRatio = 0.0;
        _currentPageIndex = lastIdx;
        _currentPageNotifier.value = lastIdx;
        if (_readerMode == ReaderMode.webtoon) {
          // Gunakan mekanisme _resumeToEnd yang sudah ada — ia akan terus
          // jumpTo(maxScrollExtent) di setiap frame sampai halaman terakhir
          // benar-benar ter-render dan viewport berada di ujung bawah.
          _resumePending = true;
          _resumeToEnd = true;
          _resumeFrameTries = 0;
          _resumeStableFrames = 0;
          _scheduleResumeFrame();
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_pageController.hasClients) {
              _pageController.jumpToPage(lastIdx);
            }
          });
        }
      }

      if (!isInitial || pages.pages.length <= 1) _saveProgress();
      if (_autoScrollEnabled) _startAutoScroll();
      if (pages.pages.isNotEmpty) {
        final prefetchTarget = _currentPageIndex.clamp(0, pages.pages.length - 1);
        _prefetchNextPages(prefetchTarget);
        _precacheSurroundingPages(prefetchTarget);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isChangingChapter = false;
      });
      if (NetworkService.isNetworkError(e) || !NetworkService.isConnected) {
        NetworkService.showNoInternetSnackBar(
          context,
          onRetry: () => _loadChapterPages(),
          hasBottomNavbar: false,
          messengerState: _messengerKey.currentState,
        );
      }
    }
  }

  void _recordSessionStats({bool chapterCompleted = false}) {
    if (!LocalStorage.isReadingStatsEnabled()) return;
    final now = DateTime.now();
    final durationSeconds = now.difference(_sessionStartTime).inSeconds;
    final pagesRead = (_currentPageIndex - _sessionInitialPage).abs();

    if (durationSeconds >= 2 || pagesRead > 0 || chapterCompleted) {
      LocalStorage.recordReadingStats(
        slug: widget.mangaSlug,
        title: widget.mangaTitle,
        seconds: durationSeconds,
        pages: pagesRead > 0 ? pagesRead : 1,
        chapterCompleted: chapterCompleted,
      );
    }
    _sessionStartTime = now;
    _sessionInitialPage = _currentPageIndex;
  }

  void _saveProgress({bool isClosing = false, bool markAsCompleted = false}) {
    if (_chapterPages == null) return;
    if (_resumePending || _applyingResume || _isSliderDragging || _webtoonJumpTargetIndex != null) return; // Cegah overwrite saat resume atau jump slider

    int anchorPageIndex = _currentPageIndex;
    double pageOffset = 0.0;
    double? pageRatio;
    final scrollOffset = _currentScrollOffset();

    if (_readerMode == ReaderMode.webtoon && _chapterPages != null && _chapterPages!.pages.isNotEmpty) {
      final pagesCount = _chapterPages!.pages.length;
      final hasContentDims = _scrollController.hasClients && _scrollController.position.hasContentDimensions;
      final maxExtent = hasContentDims ? _scrollController.position.maxScrollExtent : 0.0;
      final extentAfter = hasContentDims ? _scrollController.position.extentAfter : double.infinity;
      final isAtEnd = markAsCompleted || _isAtEndKnown || (maxExtent > 100 && scrollOffset > 50 && (scrollOffset >= maxExtent - 40 || extentAfter <= 40));

      if (isAtEnd) {
        anchorPageIndex = pagesCount - 1;
        final h = _pageHeights[anchorPageIndex] ?? _estimatedPageHeight;
        pageOffset = h;
        pageRatio = 1.0;
      } else {
        double cumulative = 0.0;
        for (int i = 0; i < pagesCount; i++) {
          final h = _pageHeights[i] ?? _estimatedPageHeight;
          if (i == pagesCount - 1 || scrollOffset < cumulative + h - 1.0) {
            anchorPageIndex = i;
            pageOffset = (scrollOffset - cumulative).clamp(0.0, h);
            pageRatio = h > 0 ? (pageOffset / h).clamp(0.0, 1.0) : 0.0;
            break;
          }
          cumulative += h;
        }
      }
      if (anchorPageIndex != _currentPageIndex) {
        _currentPageIndex = anchorPageIndex;
        _currentPageNotifier.value = anchorPageIndex;
      }
    } else {
      anchorPageIndex = markAsCompleted ? (_chapterPages?.pages.length ?? 1) - 1 : _currentPageIndex;
      pageOffset = 0.0;
      pageRatio = markAsCompleted ? 1.0 : null;
    }

    // Hitung progress pembacaan manga persis seperti Kotatsu Redo (computePercent)
    final chIdx = _findChapterIndex(_currentChapter);
    final totalChs = _chapters.length;
    final pagesCount = _chapterPages!.totalPages;
    double? totalProgress;
    if (totalChs > 0 && chIdx >= 0) {
      final pageFrac = pagesCount > 0 ? (anchorPageIndex + 1) / pagesCount : 0.0;
      final raw = ((chIdx + pageFrac) / totalChs).clamp(0.0, 1.0);
      final remaining = totalChs - (chIdx + 1);
      final isLastCh = (chIdx == totalChs - 1);
      final isDone = markAsCompleted || (isLastCh && (pagesCount > 0 && (anchorPageIndex + 1 >= pagesCount || (pageRatio != null && pageRatio >= 0.99))));
      if (isDone) {
        totalProgress = 1.0;
      } else if (remaining >= 2) {
        totalProgress = raw.clamp(0.0, remaining >= 3 ? 0.97 : 0.98);
      } else {
        totalProgress = raw.clamp(0.0, 0.99);
      }
    }

    LocalStorage.saveHistory(
      slug: widget.mangaSlug,
      title: widget.mangaTitle,
      cover: widget.cover,
      source: widget.source,
      chapterSlug: _currentChapter.slug,
      chapterTitle: _currentChapter.title,
      page: anchorPageIndex + 1,
      totalPages: pagesCount,
      pageOffset: pageOffset,
      pageOffsetRatio: pageRatio,
      scrollOffset: scrollOffset,
      percent: totalProgress,
      totalChapters: totalChs > 0 ? totalChs : null,
      chapterNumber: _currentChapter.chapterNumber ??
          (chIdx >= 0 ? (chIdx + 1).toDouble() : null),
      pageHeights: _pageHeights.isNotEmpty ? Map<int, double>.from(_pageHeights) : null,
    );

    // Otomatis tandai bab saat ini dan seluruh bab sebelumnya sebagai sudah dibaca,
    // serta ubah bab-bab setelahnya menjadi unread jika membaca ulang bab sebelumnya (persis seperti Kotatsu)
    if (_chapters.isNotEmpty) {
      final isCompleted = totalProgress != null && totalProgress >= 0.99;
      final endIdx = isCompleted ? _chapters.length : (chIdx >= 0 ? chIdx + 1 : 0);

      final toMarkRead = <String>[];
      for (int i = 0; i < endIdx; i++) {
        final c = _chapters[i];
        if (c.slug.isNotEmpty) {
          toMarkRead.add(c.slug);
          toMarkRead.add(SyncService.hashSlug(c.slug).toString());
        }
        if (c.chapter.isNotEmpty) {
          toMarkRead.add(c.chapter);
          toMarkRead.add(SyncService.hashSlug(c.chapter).toString());
        }
      }

      final toMarkUnread = <String>[];
      if (!isCompleted && chIdx >= 0) {
        for (int i = chIdx + 1; i < _chapters.length; i++) {
          final c = _chapters[i];
          if (c.slug.isNotEmpty) {
            toMarkUnread.add(c.slug);
            toMarkUnread.add(SyncService.hashSlug(c.slug).toString());
          }
          if (c.chapter.isNotEmpty) {
            toMarkUnread.add(c.chapter);
            toMarkUnread.add(SyncService.hashSlug(c.chapter).toString());
          }
        }
      }

      if (toMarkRead.isNotEmpty || toMarkUnread.isNotEmpty) {
        LocalStorage.setReadChaptersUpTo(
          mangaSlug: widget.mangaSlug,
          readSlugs: toMarkRead,
          unreadSlugs: toMarkUnread,
          source: widget.source,
        );
      }

      // Advance tracker baseline if reading the latest chapter
      if (chIdx == _chapters.length - 1 || isCompleted) {
        LocalStorage.saveTrackBaseline(
          widget.mangaSlug,
          lastChapterSlug: _chapters.last.slug,
          totalChapters: _chapters.length,
        );
      }
    }

    // Simpan sesi reader aktif secara real-time HANYA jika reader sedang aktif dan TIDAK sedang ditutup/exit
    if (!isClosing && !_isExiting && mounted) {
      LocalStorage.saveActiveReaderSession({
        'source': widget.source,
        'mangaSlug': widget.mangaSlug,
        'mangaTitle': widget.mangaTitle,
        'cover': widget.cover,
        'chapter': _currentChapter.toJson(),
        'chapters': _chapters.map((c) => c.toJson()).toList(),
        'page': _currentPageIndex + 1,
        'pageOffset': pageOffset,
        'pageOffsetRatio': pageRatio,
        'scrollOffset': scrollOffset,
        'pageHeights': _pageHeights.isNotEmpty
            ? _pageHeights.map((k, v) => MapEntry(k.toString(), v))
            : null,
        'origin': widget.origin,
        'detailsOrigin': widget.detailsOrigin,
        'sourceName': widget.sourceName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isOpen': true,
      });
    } else {
      LocalStorage.clearActiveReaderSession();
    }
  }

  void _goToPreviousChapter({bool startAtEnd = false}) {
    _recordSessionStats();
    final prev = _previousChapter;
    if (prev != null) {
      _targetInitialPageAtEnd = startAtEnd;
      if (!startAtEnd) {
        _currentPageIndex = 0;
        _currentPageNotifier.value = 0;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      }
      setState(() {
        _currentChapter = prev;
        _isChangingChapter = false;
      });
      _loadChapterPages();
    } else {
      _isChangingChapter = false;
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Sudah di chapter paling awal'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
        ),
      );
    }
  }

  void _goToNextChapter() {
    _recordSessionStats(chapterCompleted: true);
    final next = _nextChapter;
    if (next != null) {
      _currentPageIndex = 0;
      _currentPageNotifier.value = 0;
      setState(() {
        _currentChapter = next;
        _isChangingChapter = false;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _loadChapterPages();
    } else {
      _isChangingChapter = false;
      if (!_resumePending && !_applyingResume) {
        _saveProgress(markAsCompleted: true);
      }
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Sudah di chapter paling baru'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
        ),
      );
    }
  }

  void _jumpToChapter(Chapter targetChapter) {
    if (targetChapter.slug == _currentChapter.slug ||
        (targetChapter.chapter.isNotEmpty && targetChapter.chapter == _currentChapter.chapter)) {
      return;
    }
    _stopAutoScroll();
    _recordSessionStats();
    _targetInitialPageAtEnd = false;
    _currentPageIndex = 0;
    _currentPageNotifier.value = 0;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    setState(() {
      _currentChapter = targetChapter;
      _isChangingChapter = false;
    });
    _loadChapterPages();
  }

  void _jumpToPage(int targetIndex) {
    if (_chapterPages == null || _chapterPages!.pages.isEmpty) return;
    final clampedIndex = targetIndex.clamp(0, _chapterPages!.pages.length - 1);
    _currentPageIndex = clampedIndex;
    _currentPageNotifier.value = clampedIndex;
    if (_readerMode == ReaderMode.webtoon) {
      _scrollToWebtoonPage(clampedIndex);
    } else {
      if (_pageController.hasClients) {
        if (_isDualPageActive) {
          final spreads = _currentSpreads;
          final spreadIdx = _spreadIndexForPage(clampedIndex, spreads);
          _pageController.jumpToPage(spreadIdx);
        } else {
          _pageController.jumpToPage(clampedIndex);
        }
      }
    }
  }

  void _scrollToWebtoonPage(int targetIndex) {
    if (!_scrollController.hasClients) return;
    _webtoonJumpTargetIndex = targetIndex;
    _jumpStableFrames = 0;
    _webtoonJumpTimer?.cancel();
    _webtoonJumpFollowTimer?.cancel();
    _precacheSurroundingPages(targetIndex);
    _prefetchNextPages(targetIndex);

    if (targetIndex == 0) {
      _scrollController.jumpTo(0.0);
      _lastKnownScrollOffset = 0.0;
      _currentPageIndex = 0;
      _currentPageNotifier.value = 0;
      _webtoonJumpTargetIndex = null;
      _saveProgress();
      return;
    }

    final targetOffset = _offsetForPage(targetIndex);
    _scrollController.jumpTo(targetOffset);
    _lastKnownScrollOffset = targetOffset;
    _currentPageIndex = targetIndex;
    _currentPageNotifier.value = targetIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _webtoonJumpTargetIndex == targetIndex) {
        _stepScrollToWebtoonPage(targetIndex, 0);
      }
    });
  }

  double? _applyJumpAnchor(int targetIndex) {
    if (!_scrollController.hasClients) return null;
    final ctx = _pageKeys[targetIndex]?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached || box.size.height <= 0) {
      return null;
    }
    final maxExtent = _scrollController.position.hasContentDimensions
        ? _scrollController.position.maxScrollExtent
        : double.infinity;
    if (maxExtent <= 0 && targetIndex > 0) return null;

    final revealOffset = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.0).offset;
    final isLastPage = _chapterPages != null && targetIndex >= _chapterPages!.pages.length - 1;
    final targetOffset = (isLastPage && maxExtent > 0) ? revealOffset.clamp(0.0, maxExtent) : revealOffset;

    if ((_scrollController.offset - targetOffset).abs() > 0.5) {
      _scrollController.jumpTo(targetOffset);
      _lastKnownScrollOffset = targetOffset;
    }
    _currentPageIndex = targetIndex;
    _currentPageNotifier.value = targetIndex;
    return targetOffset;
  }

  void _followJumpAnchor() {
    final targetIndex = _webtoonJumpTargetIndex;
    if (targetIndex == null || !mounted || _jumpAnchorScheduled) return;
    if (!_scrollController.hasClients) return;
    if (_isUserDragging || _scrollController.position.isScrollingNotifier.value) return;

    _jumpAnchorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpAnchorScheduled = false;
      if (!mounted || _webtoonJumpTargetIndex != targetIndex) return;
      if (!_scrollController.hasClients) return;
      if (_isUserDragging || _scrollController.position.isScrollingNotifier.value) return;
      _applyJumpAnchor(targetIndex);
    });
  }

  void _stepScrollToWebtoonPage(int targetIndex, int attempt) {
    if (!mounted || _webtoonJumpTargetIndex != targetIndex) return;
    if (!_scrollController.hasClients) return;

    final clamped = _applyJumpAnchor(targetIndex);

    if (clamped != null) {
      final currentOffset = _scrollController.offset;
      final offsetDiff = (currentOffset - clamped).abs();
      final isPositionStable = offsetDiff <= 2.0;

      if (isPositionStable) {
        _jumpStableFrames++;
      } else {
        _jumpStableFrames = 0;
      }

      if (_jumpStableFrames >= 2 || attempt >= 20) {
        _jumpStableFrames = 0;
        _webtoonJumpFollowTimer?.cancel();
        _webtoonJumpFollowTimer = Timer(const Duration(milliseconds: 400), () {
          if (mounted && _webtoonJumpTargetIndex == targetIndex) {
            _webtoonJumpTargetIndex = null;
            _saveProgress();
          }
        });
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _webtoonJumpTargetIndex == targetIndex) {
          _stepScrollToWebtoonPage(targetIndex, attempt + 1);
        }
      });
      return;
    }

    if (attempt >= 20) {
      _webtoonJumpTargetIndex = null;
      _onWebtoonScroll();
      return;
    }

    final targetOffset = _offsetForPage(targetIndex);
    _scrollController.jumpTo(targetOffset);
    _lastKnownScrollOffset = targetOffset;
    _currentPageIndex = targetIndex;
    _currentPageNotifier.value = targetIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _webtoonJumpTargetIndex == targetIndex) {
        _stepScrollToWebtoonPage(targetIndex, attempt + 1);
      }
    });
  }

  void _scheduleAutoHideControls({Duration duration = const Duration(seconds: 3)}) {
    _controlsAutoHideTimer?.cancel();
    if (!_showControls || _isPopupMenuOpen) return;
    _controlsAutoHideTimer = Timer(duration, () {
      if (mounted && _showControls && !_isSliderDragging && !_showAutoScrollPanel && !_isPopupMenuOpen) {
        _hideControls();
      }
    });
  }

  void _hideControls() {
    if (!_showControls || _isPopupMenuOpen) return;
    _controlsAutoHideTimer?.cancel();
    setState(() => _showControls = false);
    _hideStatusBarNow();
  }

  void _toggleControls() {
    _controlsAutoHideTimer?.cancel();
    final showing = !_showControls;
    setState(() => _showControls = showing);
    // Tampilkan status bar saat controls muncul, sembunyikan saat hidden
    if (showing) {
      _statusBarAutoHideTimer?.cancel();
      _deviceChannel.invokeMethod('setReaderImmersive', {'enable': false});
      if (!_resumePending && !_applyingResume) {
        _saveProgress(); // Kotatsu openMenu() behavior: commit current reading position when controls appear
      }
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top],
      );
      // Auto-hide controls setelah 3 detik jika tidak disentuh
      _scheduleAutoHideControls(duration: const Duration(seconds: 3));
    } else {
      _hideStatusBarNow();
    }
  }

  void _handleReaderTap(TapUpDetails details) {
    if (_showControls) {
      _toggleControls();
      return;
    }

    _hideStatusBarNow();

    if (!_tapNavigationEnabled) {
      _toggleControls();
      return;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;

    // Kotatsu 3-Zone Tap Navigation:
    // Sisi Kiri (28%): Prev page / Scroll up
    // Sisi Tengah (44%): Munculkan Menu / Controls
    // Sisi Kanan (28%): Next page / Scroll down
    final isRtl = _readerMode == ReaderMode.pagedRtl;
    final leftThreshold = screenWidth * 0.28;
    final rightThreshold = screenWidth * 0.72;

    if (x < leftThreshold) {
      if (isRtl) {
        _navigateForward();
      } else {
        _navigateBackward();
      }
    } else if (x > rightThreshold) {
      if (isRtl) {
        _navigateBackward();
      } else {
        _navigateForward();
      }
    } else {
      _toggleControls();
    }
  }

  void _navigateForward() {
    if (_readerMode == ReaderMode.webtoon) {
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final current = _scrollController.offset;

      // Jika sudah berada di ujung bawah (dalam 20px), tap berikutnya membuka bab selanjutnya
      if (current >= maxExtent - 20) {
        _goToNextChapter();
        return;
      }

      final step = MediaQuery.of(context).size.height * 0.85;
      final base = (_targetScrollOffset != null && (_targetScrollOffset! - current).abs() < step * 2.5)
          ? _targetScrollOffset!
          : current;
      final target = (base + step).clamp(0.0, maxExtent);
      _targetScrollOffset = target;

      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ).then((_) {
        if (_targetScrollOffset == target) {
          _targetScrollOffset = null;
        }
      }).catchError((_) {});
    } else {
      if (!_pageController.hasClients) return;
      final totalPages = _chapterPages?.pages.length ?? 0;
      if (totalPages == 0) return;

      final isDual = _isDualPageActive;
      final spreads = isDual ? _currentSpreads : null;
      final totalItems = isDual ? (spreads?.length ?? 0) : totalPages;
      final currentItem = isDual
          ? (spreads != null ? _spreadIndexForPage(_currentPageIndex, spreads) : 0)
          : _currentPageIndex;

      final base = _targetPageIndex ?? currentItem;
      if (base < totalItems - 1) {
        final target = base + 1;
        _targetPageIndex = target;
        _pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutQuad,
        ).then((_) {
          if (_targetPageIndex == target) {
            _targetPageIndex = null;
          }
        }).catchError((_) {});
      } else {
        _goToNextChapter();
      }
    }
  }

  void _navigateBackward() {
    if (_readerMode == ReaderMode.webtoon) {
      if (!_scrollController.hasClients) return;
      final current = _scrollController.offset;

      // Jika sudah di puncak paling atas (dalam 20px), tap backward membuka bab sebelumnya
      if (current <= 20) {
        _goToPreviousChapter(startAtEnd: true);
        return;
      }

      final step = MediaQuery.of(context).size.height * 0.85;
      final base = (_targetScrollOffset != null && (_targetScrollOffset! - current).abs() < step * 2.5)
          ? _targetScrollOffset!
          : current;
      final target = (base - step).clamp(0.0, _scrollController.position.maxScrollExtent);
      _targetScrollOffset = target;

      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ).then((_) {
        if (_targetScrollOffset == target) {
          _targetScrollOffset = null;
        }
      }).catchError((_) {});
    } else {
      if (!_pageController.hasClients) return;
      final totalPages = _chapterPages?.pages.length ?? 0;
      if (totalPages == 0) return;

      final isDual = _isDualPageActive;
      final spreads = isDual ? _currentSpreads : null;
      final currentItem = isDual
          ? (spreads != null ? _spreadIndexForPage(_currentPageIndex, spreads) : 0)
          : _currentPageIndex;

      final base = _targetPageIndex ?? currentItem;
      if (base > 0) {
        final target = base - 1;
        _targetPageIndex = target;
        _pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutQuad,
        ).then((_) {
          if (_targetPageIndex == target) {
            _targetPageIndex = null;
          }
        }).catchError((_) {});
      } else {
        _goToPreviousChapter(startAtEnd: true);
      }
    }
  }

  Future<File?> _resolveCurrentPageFile() async {
    if (_chapterPages == null || _chapterPages!.pages.isEmpty) return null;
    final pageIndex = _currentPageIndex.clamp(0, _chapterPages!.pages.length - 1);
    final page = _chapterPages!.pages[pageIndex];
    final pageUrl = page.url.trim();
    if (pageUrl.isEmpty) return null;

    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(pageUrl);
      if (fileInfo?.file != null && fileInfo!.file.existsSync()) {
        return fileInfo.file;
      }
      return await DefaultCacheManager().getSingleFile(pageUrl);
    } catch (e) {
      debugPrint('Error downloading page: $e');
      return null;
    }
  }

  Future<void> _saveCurrentPageToGallery() async {
    if (_isSavingPage) return;
    if (_chapterPages == null || _chapterPages!.pages.isEmpty) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Halaman belum siap')),
      );
      return;
    }

    setState(() => _isSavingPage = true);
    _messengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Menyimpan halaman ke galeri...'),
          ],
        ),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      final file = await _resolveCurrentPageFile();
      if (file == null || !file.existsSync()) {
        if (!mounted) return;
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Gagal mengambil gambar halaman')),
        );
        return;
      }

      final pageNum = _currentPageIndex + 1;
      final cleanTitle = widget.mangaTitle
          .replaceAll(RegExp(r'[^\w\s\.-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final cleanCh = _currentChapter.title
          .replaceAll(RegExp(r'[^\w\s\.-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final title = '${cleanTitle}_${cleanCh}_P$pageNum';

      final res = await _deviceChannel.invokeMethod('saveImageToGallery', {
        'filePath': file.path,
        'title': title,
      });

      if (!mounted) return;
      if (res != null) {
        HapticFeedback.lightImpact();
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF8AB4F8), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Halaman $pageNum tersimpan di Galeri (Pictures/Yomika)'),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            backgroundColor: const Color(0xFF232832),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Gagal menyimpan gambar')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Terjadi kesalahan: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingPage = false);
    }
  }

  Future<void> _shareCurrentPage() async {
    if (_isSharingPage) return;
    if (_chapterPages == null || _chapterPages!.pages.isEmpty) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Halaman belum siap')),
      );
      return;
    }

    setState(() => _isSharingPage = true);
    _messengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Menyiapkan gambar untuk dibagikan...'),
          ],
        ),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      final file = await _resolveCurrentPageFile();
      if (file == null || !file.existsSync()) {
        if (!mounted) return;
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Gagal mengambil gambar halaman')),
        );
        return;
      }

      final pageNum = _currentPageIndex + 1;
      final tempDir = await getTemporaryDirectory();
      final cleanTitle = widget.mangaTitle
          .replaceAll(RegExp(r'[^\w\s\.-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final tempFile = File('${tempDir.path}/${cleanTitle}_p$pageNum.jpg');
      await file.copy(tempFile.path);

      final shareText = '${widget.mangaTitle} - ${_currentChapter.title} (Hal. $pageNum)';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path, mimeType: 'image/jpeg', name: '${cleanTitle}_p$pageNum.jpg')],
          text: shareText,
          subject: shareText,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Gagal membagikan: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSharingPage = false);
    }
  }

  void _showAutoScrollPanelOverlay() {
    _controlsAutoHideTimer?.cancel();
    setState(() => _showAutoScrollPanel = true);
  }

  void _hideAutoScrollPanel() {
    if (!_showAutoScrollPanel) return;
    setState(() => _showAutoScrollPanel = false);
    _scheduleAutoHideControls(duration: const Duration(seconds: 3));
  }

  // --- Chapter List Bottom Sheet ---
  Future<void> _showChapterListBottomSheet() async {
    _controlsAutoHideTimer?.cancel();
    if (_autoScrollEnabled) {
      _stopAutoScroll();
    }
    final theme = Theme.of(context);
    final cleanMangaSlug = widget.mangaSlug
        .trim()
        .replaceAll(RegExp(r'^/+|/+$'), '')
        .replaceFirst(RegExp(r'^manga/', caseSensitive: false), '')
        .replaceAll(RegExp(r'^/+|/+$'), '');
    final effectiveMangaSlug = cleanMangaSlug.isNotEmpty ? cleanMangaSlug : widget.mangaSlug;

    if (_chapters.length <= 1) {
      _fetchFullChapterList();
    }

    bool isDescending = true;
    String searchQuery = '';
    final searchController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle(
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 250),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.94,
          snap: true,
          snapSizes: const [0.65, 0.94],
          expand: false,
          builder: (context, scrollController) {
            return PredictiveBackBottomSheet(
              child: Material(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: StatefulBuilder(
                  builder: (context, setSheetState) {
                    final readChapterSlugs = LocalStorage.getReadChapters(
                      effectiveMangaSlug,
                      source: widget.source,
                    ).toSet();

                    List<Chapter> filteredList = _chapters.where((c) {
                      if (searchQuery.trim().isEmpty) return true;
                      final q = searchQuery.trim().toLowerCase();
                      final titleMatch = c.title.toLowerCase().contains(q);
                      final numMatch = c.chapterNumber?.toString().contains(q) ?? false;
                      final slugMatch = c.slug.toLowerCase().contains(q);
                      return titleMatch || numMatch || slugMatch;
                    }).toList();

                    if (isDescending) {
                      filteredList = filteredList.reversed.toList();
                    }

                    return SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          // Handle Bar
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: Center(
                              child: Container(
                                width: 32,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),

                          // Header
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Daftar Chapter',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_chapters.length} chapter tersedia',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Sort button
                                IconButton(
                                  icon: Icon(
                                    isDescending ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                    size: 20,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  tooltip: isDescending ? 'Urutan: Terbaru ke Terlama' : 'Urutan: Terlama ke Terbaru',
                                  onPressed: () {
                                    setSheetState(() {
                                      isDescending = !isDescending;
                                    });
                                  },
                                ),

                                // Close button
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 20),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ),

                          // Search Bar
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: TextField(
                              controller: searchController,
                              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                              decoration: InputDecoration(
                                hintText: 'Cari chapter...',
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                ),
                                prefixIcon: Icon(
                                  Icons.search_rounded,
                                  size: 20,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                suffixIcon: searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 18),
                                        onPressed: () {
                                          searchController.clear();
                                          setSheetState(() => searchQuery = '');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (val) {
                                setSheetState(() => searchQuery = val);
                              },
                            ),
                          ),

                          const Divider(height: 1),

                          // Chapters List
                          Expanded(
                            child: filteredList.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        searchQuery.isNotEmpty
                                            ? 'Chapter tidak ditemukan'
                                            : 'Tidak ada chapter',
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurfaceVariant,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: scrollController,
                                    itemCount: filteredList.length,
                                    itemBuilder: (context, index) {
                                      final ch = filteredList[index];
                                      final isCurrent = ch.slug == _currentChapter.slug ||
                                          (ch.chapter.isNotEmpty && ch.chapter == _currentChapter.chapter);

                                      final cleanSlug = ch.slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
                                      final hashSlug = SyncService.hashSlug(ch.slug).toString();
                                      final isRead = readChapterSlugs.contains(ch.slug) ||
                                          readChapterSlugs.contains(cleanSlug) ||
                                          readChapterSlugs.contains(ch.chapter) ||
                                          readChapterSlugs.contains(hashSlug);

                                      return ListTile(
                                        dense: true,
                                        selected: isCurrent,
                                        selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        leading: CircleAvatar(
                                          radius: 14,
                                          backgroundColor: isCurrent
                                              ? theme.colorScheme.primary
                                              : (isRead
                                                  ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.7)
                                                  : theme.colorScheme.surfaceContainerHigh),
                                          child: Icon(
                                            isCurrent
                                                ? Icons.auto_stories_rounded
                                                : (isRead ? Icons.check_rounded : Icons.menu_book_outlined),
                                            size: 14,
                                            color: isCurrent
                                                ? theme.colorScheme.onPrimary
                                                : (isRead
                                                    ? theme.colorScheme.primary
                                                    : theme.colorScheme.onSurfaceVariant),
                                          ),
                                        ),
                                        title: Text(
                                          ch.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                            color: isCurrent
                                                ? theme.colorScheme.primary
                                                : (isRead
                                                    ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                                                    : theme.colorScheme.onSurface),
                                          ),
                                        ),
                                        subtitle: ch.chapterSubtitle != null
                                            ? Text(
                                                ch.chapterSubtitle!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isCurrent
                                                      ? theme.colorScheme.primary.withValues(alpha: 0.8)
                                                      : (isRead
                                                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                                                          : theme.colorScheme.onSurfaceVariant),
                                                ),
                                              )
                                            : null,
                                        trailing: isCurrent
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme.primaryContainer,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  'Sedang Dibaca',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: theme.colorScheme.onPrimaryContainer,
                                                  ),
                                                ),
                                              )
                                            : null,
                                        onTap: () {
                                          Navigator.pop(context);
                                          if (!isCurrent) {
                                            _jumpToChapter(ch);
                                          }
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
    searchController.dispose();
    if (mounted) {
      _scheduleAutoHideControls(duration: const Duration(seconds: 3));
    }
  }

  // --- Reader Settings Bottom Sheet ---
  void _showReaderSettingsSheet() async {
    _controlsAutoHideTimer?.cancel();
    final isSoftkomik = widget.source.trim().toLowerCase() == 'softkomik';
    final isShinigami = widget.source.trim().toLowerCase() == 'shinigami';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle(
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 250),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          initialChildSize: 0.52,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          snap: true,
          snapSizes: const [0.52, 0.92],
          expand: false,
          builder: (context, scrollController) {
            return PredictiveBackBottomSheet(
              child: Material(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                clipBehavior: Clip.antiAlias,
                child: StatefulBuilder(
                  builder: (context, setSheetState) {
                    return SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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

                      if (isSoftkomik) ...[
                        Text(
                          'CDN / Server gambar',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'cdn1', label: Text('CDN 1')),
                              ButtonSegment(value: 'cdn2', label: Text('CDN 2')),
                              ButtonSegment(value: 'cdn3', label: Text('CDN 3')),
                            ],
                            selected: {_activeCdn},
                            showSelectedIcon: false,
                            expandedInsets: EdgeInsets.zero,
                            style: SegmentedButton.styleFrom(
                              selectedBackgroundColor: theme.colorScheme.secondaryContainer,
                              selectedForegroundColor: theme.colorScheme.onSecondaryContainer,
                            ),
                            onSelectionChanged: (s) {
                              final sel = s.first;
                              setState(() => _activeCdn = sel);
                              setSheetState(() {});
                              LocalStorage.setReaderCdn(sel);
                              _loadChapterPages();
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      if (isShinigami) ...[
                        Text(
                          'Server gambar',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 1, label: Text('Server 1')),
                              ButtonSegment(value: 2, label: Text('Server 2')),
                              ButtonSegment(value: 3, label: Text('Server 3')),
                              ButtonSegment(value: 4, label: Text('Server 4')),
                            ],
                            selected: {_activeServer},
                            showSelectedIcon: false,
                            expandedInsets: EdgeInsets.zero,
                            style: SegmentedButton.styleFrom(
                              selectedBackgroundColor: theme.colorScheme.secondaryContainer,
                              selectedForegroundColor: theme.colorScheme.onSecondaryContainer,
                            ),
                            onSelectionChanged: (s) {
                              final sel = s.first;
                              setState(() => _activeServer = sel);
                              setSheetState(() {});
                              LocalStorage.setShinigamiServer(sel);
                              _loadChapterPages();
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      Text(
                        'Mode baca',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildReaderModeSelector(setSheetState),
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Text(
                          'Konfigurasi yang dipilih akan diingat untuk manga ini',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Divider(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                        height: 16,
                      ),
                      Text(
                        'Orientasi layar',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'portrait',
                              icon: Icon(Icons.stay_current_portrait_rounded, size: 18),
                              label: Text('Potret'),
                            ),
                            ButtonSegment(
                              value: 'system',
                              icon: Icon(Icons.screen_rotation_rounded, size: 18),
                              label: Text('Sensor'),
                            ),
                            ButtonSegment(
                              value: 'landscape',
                              icon: Icon(Icons.stay_current_landscape_rounded, size: 18),
                              label: Text('Lanskap'),
                            ),
                          ],
                          selected: {_orientationSetting},
                          showSelectedIcon: false,
                          expandedInsets: EdgeInsets.zero,
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: theme.colorScheme.secondaryContainer,
                            selectedForegroundColor: theme.colorScheme.onSecondaryContainer,
                          ),
                          onSelectionChanged: (s) {
                            final sel = s.first;
                            _setOrientation(sel);
                            setSheetState(() {});
                          },
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_readerMode == ReaderMode.pagedLtr || _readerMode == ReaderMode.pagedRtl) ...[
                        _buildSettingsListTile(
                          icon: Icons.menu_book_rounded,
                          title: 'Halaman ganda di mode lanskap',
                          subtitle: 'Tampilkan 2 halaman berdampingan saat rotasi lanskap (seperti buku komik)',
                          trailing: Switch(
                            value: _dualPageInLandscape,
                            onChanged: (val) {
                              setState(() => _dualPageInLandscape = val);
                              setSheetState(() {});
                              LocalStorage.setDualPageInLandscape(val);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _jumpToPage(_currentPageIndex);
                              });
                            },
                          ),
                          onTap: () {
                            final newVal = !_dualPageInLandscape;
                            setState(() => _dualPageInLandscape = newVal);
                            setSheetState(() {});
                            LocalStorage.setDualPageInLandscape(newVal);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _jumpToPage(_currentPageIndex);
                            });
                          },
                        ),
                        if (_dualPageInLandscape)
                          _buildSettingsListTile(
                            icon: Icons.auto_stories_outlined,
                            title: 'Halaman pertama sebagai sampul',
                            subtitle: 'Halaman 1 tampil sendiri di tengah, halaman selanjutnya berpasangan',
                            trailing: Switch(
                              value: _shiftFirstPageCover,
                              onChanged: (val) {
                                setState(() => _shiftFirstPageCover = val);
                                setSheetState(() {});
                                LocalStorage.setShiftFirstPageCover(val);
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) _jumpToPage(_currentPageIndex);
                                });
                              },
                            ),
                            onTap: () {
                              final newVal = !_shiftFirstPageCover;
                              setState(() => _shiftFirstPageCover = newVal);
                              setSheetState(() {});
                              LocalStorage.setShiftFirstPageCover(newVal);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _jumpToPage(_currentPageIndex);
                              });
                            },
                          ),
                      ],
                      Divider(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                        height: 16,
                      ),
                      _buildSettingsListTile(
                        icon: Icons.timer_outlined,
                        title: 'Pengguliran otomatis',
                        onTap: () {
                          Navigator.pop(context);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _showAutoScrollPanelOverlay();
                          });
                        },
                      ),
                      _buildSettingsListTile(
                        icon: Icons.translate_rounded,
                        title: 'Manga Auto Translator',
                        subtitle: LocalStorage.isAutoTranslateEnabled()
                            ? 'Aktif • ${LocalStorage.getTranslatorSourceLang().toUpperCase()} → ${LocalStorage.getTranslatorTargetLang().toUpperCase()}'
                            : 'Terjemahkan balon manga secara offline',
                        trailing: Switch(
                          value: LocalStorage.isAutoTranslateEnabled(),
                          onChanged: (val) {
                            ref.read(autoTranslateEnabledProvider.notifier).setEnabled(val);
                            setSheetState(() {});
                            setState(() {});
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          TranslationSettingsSheet.show(context);
                        },
                      ),
                      _buildSettingsListTile(
                        icon: Icons.touch_app_rounded,
                        title: 'Navigasi ketukan (Tap Zones)',
                        subtitle: 'Ketuk kiri/kanan untuk geser, tengah untuk menu',
                        trailing: Switch(
                          value: _tapNavigationEnabled,
                          onChanged: (val) {
                            setState(() => _tapNavigationEnabled = val);
                            setSheetState(() {});
                            LocalStorage.setTapNavigationEnabled(val);
                          },
                        ),
                        onTap: () {
                          final newVal = !_tapNavigationEnabled;
                          setState(() => _tapNavigationEnabled = newVal);
                          setSheetState(() {});
                          LocalStorage.setTapNavigationEnabled(newVal);
                        },
                      ),
                      _buildSettingsListTile(
                        icon: Icons.subtitles_outlined,
                        title: 'Notifikasi judul bab',
                        subtitle: 'Tampilkan pop-up judul bab sesaat setelah berpindah bab',
                        trailing: Switch(
                          value: _chapterToastEnabled,
                          onChanged: (val) {
                            setState(() => _chapterToastEnabled = val);
                            setSheetState(() {});
                            LocalStorage.setReaderChapterToastEnabled(val);
                          },
                        ),
                        onTap: () {
                          final newVal = !_chapterToastEnabled;
                          setState(() => _chapterToastEnabled = newVal);
                          setSheetState(() {});
                          LocalStorage.setReaderChapterToastEnabled(newVal);
                        },
                      ),
                      _buildSettingsListTile(
                        icon: Icons.swipe_vertical_rounded,
                        title: 'Gerakan tarik (Pull Gesture)',
                        subtitle: 'Tarik di ujung halaman untuk beralih ke bab sebelumnya / selanjutnya',
                        trailing: Switch(
                          value: _pullGestureEnabled,
                          onChanged: (val) {
                            setState(() => _pullGestureEnabled = val);
                            setSheetState(() {});
                            LocalStorage.setPullGestureEnabled(val);
                          },
                        ),
                        onTap: () {
                          final newVal = !_pullGestureEnabled;
                          setState(() => _pullGestureEnabled = newVal);
                          setSheetState(() {});
                          LocalStorage.setPullGestureEnabled(newVal);
                        },
                      ),
                      Divider(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                        height: 16,
                      ),
                      _buildSettingsListTile(
                        icon: Icons.download_rounded,
                        title: 'Simpan halaman ke galeri',
                        subtitle: 'Simpan gambar halaman ${_currentPageIndex + 1} ke Pictures/Yomika',
                        onTap: () {
                          Navigator.pop(context);
                          _saveCurrentPageToGallery();
                        },
                      ),
                      _buildSettingsListTile(
                        icon: Icons.share_rounded,
                        title: 'Bagikan halaman ini',
                        subtitle: 'Bagikan gambar halaman ${_currentPageIndex + 1} ke aplikasi lain',
                        onTap: () {
                          Navigator.pop(context);
                          _shareCurrentPage();
                        },
                      ),
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
},
);
    if (mounted && _showControls) {
      _scheduleAutoHideControls(duration: const Duration(seconds: 3));
    }
  }

  Widget _buildReaderModeSelector(StateSetter setSheetState) {
    final theme = Theme.of(context);
    return Container(
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
          _buildReaderModeSegment(
            mode: ReaderMode.pagedLtr,
            title: 'Standar',
            icon: ReaderModeIconKind.ltr,
            isFirst: true,
            setSheetState: setSheetState,
          ),
          _buildReaderModeSegment(
            mode: ReaderMode.pagedRtl,
            title: 'Kanan-ke-kiri',
            icon: ReaderModeIconKind.rtl,
            setSheetState: setSheetState,
          ),
          _buildReaderModeSegment(
            mode: ReaderMode.verticalPager,
            title: 'Vertikal',
            icon: ReaderModeIconKind.vertical,
            setSheetState: setSheetState,
          ),
          _buildReaderModeSegment(
            mode: ReaderMode.webtoon,
            title: 'Webtoon',
            icon: ReaderModeIconKind.webtoon,
            isLast: true,
            setSheetState: setSheetState,
          ),
        ],
      ),
    );
  }

  Widget _buildReaderModeSegment({
    required ReaderMode mode,
    required String title,
    required ReaderModeIconKind icon,
    bool isFirst = false,
    bool isLast = false,
    required StateSetter setSheetState,
  }) {
    final isSelected = _readerMode == mode;
    final theme = Theme.of(context);
    final iconColor = isSelected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: () {
          if (_readerMode == mode) return;
          final savedPage = _currentPageIndex;
          if (!_resumePending && !_applyingResume) {
            _saveProgress(); // Kotatsu onReaderModeChanged() behavior: save current state before mode change
          }
          setState(() => _readerMode = mode);
          setSheetState(() {});
          LocalStorage.setReaderMode(_serializeReaderMode(mode));
          if (_autoScrollEnabled) _startAutoScroll();
          // Jump back to same page after mode change rebuild
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _jumpToPage(savedPage);
          });
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
              ReaderModeIcon(
                kind: icon,
                size: 24,
                color: iconColor,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
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

  Widget _buildSettingsListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: iconColor ?? theme.colorScheme.onSurfaceVariant),
      title: Text(
        title,
        style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final topPadding = MediaQuery.of(context).viewPadding.top;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final totalPages = _chapterPages?.totalPages ?? 1;

    // Current chapter display — use position in list (1-indexed from oldest)
    // e.g. if reading Ch 22.5 which is the 23rd item, show "23/37"
    final chIdx = _findChapterIndex(_currentChapter);
    // chapters are sorted ascending (Ch1 = index 0), so position = chIdx + 1
    final chapterPosition = chIdx >= 0 ? chIdx + 1 : '?';
    final totalChapters = _chapters.length;
    final totalPagesDisplay = _isLoading ? '...' : '$totalPages';

    return PopScope(
      canPop: !_showAutoScrollPanel,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _isExiting = true;
          if (!_resumePending && !_applyingResume) {
            _saveProgress(isClosing: true);
          }
          LocalStorage.clearActiveReaderSession();
          return;
        }
        _hideAutoScrollPanel();
      },
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Reader content
            GestureDetector(
              onTapUp: _handleReaderTap,
              onLongPress: _showReaderSettingsSheet,
              child: RepaintBoundary(
                child: _buildReaderBody(),
              ),
            ),

            // ── HUD Top InfoBar (Kotatsu Image 2: Shown when controls are hidden) ──
            if (!_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: RepaintBoundary(
                  child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isLandscape ? 36 : 14,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left HUD: Bab X/Y Hlm. A/B   Z%
                    ValueListenableBuilder<int>(
                      valueListenable: _currentPageNotifier,
                      builder: (context, pageIndex, _) {
                        final pageDisplay = _formatPageDisplay(pageIndex, totalPages);
                        final chIdx = _findChapterIndex(_currentChapter);
                        final int percentRead;
                        if (totalChapters > 0 && chIdx >= 0) {
                          final pageFrac = (!_isLoading && totalPages > 0) ? (pageIndex + 1) / totalPages : 0.0;
                          final raw = (((chIdx + pageFrac) / totalChapters) * 100).round();
                          final remaining = totalChapters - (chIdx + 1);
                          final isLastCh = (chIdx == totalChapters - 1);
                          final isDone = isLastCh && (!_isLoading && totalPages > 0 && pageIndex + 1 >= totalPages);
                          if (isDone) {
                            percentRead = 100;
                          } else if (remaining >= 2) {
                            percentRead = raw.clamp(0, remaining >= 3 ? 97 : 98);
                          } else {
                            percentRead = raw.clamp(0, 99);
                          }
                        } else if (!_isLoading && totalPages > 0) {
                          percentRead = (((pageIndex + 1) / totalPages) * 100).clamp(0, 100).round();
                        } else {
                          percentRead = 0;
                        }
                        return Text(
                          'Bab $chapterPosition/$totalChapters  Hlm. $pageDisplay/$totalPagesDisplay    $percentRead%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                            shadows: [
                              Shadow(offset: Offset(-1, -1), color: Colors.black87, blurRadius: 3),
                              Shadow(offset: Offset(1, -1), color: Colors.black87, blurRadius: 3),
                              Shadow(offset: Offset(1, 1), color: Colors.black87, blurRadius: 3),
                              Shadow(offset: Offset(-1, 1), color: Colors.black87, blurRadius: 3),
                            ],
                          ),
                        );
                      },
                    ),

                    // Right HUD: Battery + Time
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.battery_5_bar_rounded,
                          size: 14,
                          color: Colors.white,
                          shadows: [
                            Shadow(offset: Offset(0, 1), color: Colors.black87, blurRadius: 3),
                          ],
                        ),
                        const SizedBox(width: 4),
                        ValueListenableBuilder<int?>(
                          valueListenable: _batteryLevelNotifier,
                          builder: (context, batteryLevel, _) {
                            return ValueListenableBuilder<String>(
                              valueListenable: _currentTimeNotifier,
                              builder: (context, currentTime, _) {
                                return Text(
                                  '${batteryLevel ?? 70}%  $currentTime',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal,
                                    shadows: [
                                      Shadow(offset: Offset(-1, -1), color: Colors.black87, blurRadius: 3),
                                      Shadow(offset: Offset(1, -1), color: Colors.black87, blurRadius: 3),
                                      Shadow(offset: Offset(1, 1), color: Colors.black87, blurRadius: 3),
                                      Shadow(offset: Offset(-1, 1), color: Colors.black87, blurRadius: 3),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                ),
                ),
              ),

            // ── Top App Bar (Kotatsu Image 1: Solid M3 Toolbar) ──────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              top: _showControls ? 0 : -130,
              left: 0,
              right: 0,
              child: RepaintBoundary(
                child: Container(
                padding: EdgeInsets.only(
                  top: topPadding > 0 ? topPadding + 4 : (isLandscape ? 4 : 8),
                  bottom: isLandscape ? 4 : 8,
                  left: isLandscape ? 28 : 4,
                  right: isLandscape ? 28 : 12,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF16151A),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF2C2A34), width: 0.8),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _exitReader,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _showChapterListBottomSheet,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.mangaTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _currentChapter.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    // More Menu (Share & Download)
                    PopupMenuButton<String>(
                      iconSize: 22,
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                      tooltip: 'Opsi Lainnya',
                      color: const Color(0xFF2A2730),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onOpened: () {
                        _controlsAutoHideTimer?.cancel();
                        _isPopupMenuOpen = true;
                      },
                      onCanceled: () {
                        _isPopupMenuOpen = false;
                        if (mounted && _showControls) {
                          _scheduleAutoHideControls(duration: const Duration(seconds: 3));
                        }
                      },
                      onSelected: (value) {
                        _isPopupMenuOpen = false;
                        if (mounted && _showControls) {
                          _scheduleAutoHideControls(duration: const Duration(seconds: 3));
                        }
                        switch (value) {
                          case 'share':
                            _shareCurrentPage();
                            break;
                          case 'download':
                            _saveCurrentPageToGallery();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined, size: 20, color: Colors.white),
                              SizedBox(width: 12),
                              Text('Bagikan Halaman',
                                style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'download',
                          child: Row(
                            children: [
                              Icon(Icons.download_rounded, size: 20, color: Colors.white),
                              SizedBox(width: 12),
                              Text('Simpan ke Galeri',
                                style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ),
            ),

            // ── Floating Auto-Scroll Control FAB ──────────────────────────
            if (_autoScrollEnabled && _showFloatingControl && !_showAutoScrollPanel)
              Positioned(
                bottom: _showControls ? bottomPadding + 70 : bottomPadding + 24,
                right: isLandscape ? 36 : 16,
                child: Material(
                  elevation: 6,
                  color: const Color(0xFF25232C),
                  shape: const CircleBorder(
                    side: BorderSide(color: Color(0xFF3E3B48), width: 1),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      setState(() {
                        _isAutoScrollPaused = !_isAutoScrollPaused;
                      });
                      if (_isAutoScrollPaused) {
                        _stopAutoScroll();
                      } else {
                        _startAutoScroll();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        _isAutoScrollPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),

            // ── Bottom Docked Bar (Kotatsu Image 1) ─────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              bottom: _showControls ? 0 : -140,
              left: 0,
              right: 0,
              child: RepaintBoundary(
                child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF16151A),
                  border: Border(
                    top: BorderSide(color: Color(0xFF2C2A34), width: 0.8),
                  ),
                ),
                padding: EdgeInsets.only(
                  bottom: bottomPadding > 0 ? bottomPadding + 6 : (isLandscape ? 6 : 12),
                  top: isLandscape ? 4 : 6,
                  left: isLandscape ? 36 : 8,
                  right: isLandscape ? 36 : 8,
                ),
                child: Row(
                  children: [
                    // Skip Prev Chapter
                    IconButton(
                      iconSize: 30,
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        color: _hasPreviousChapter ? Colors.white : Colors.white38,
                      ),
                      tooltip: 'Chapter Sebelumnya',
                      onPressed: _hasPreviousChapter ? _goToPreviousChapter : null,
                    ),

                    // Page slider with floating indicator (Material 3 Expressive Slider)
                    Expanded(
                      child: _chapterPages != null && _chapterPages!.pages.isNotEmpty
                          ? ValueListenableBuilder<int>(
                              valueListenable: _currentPageNotifier,
                              builder: (context, pageIndex, _) {
                                final totalPages = _chapterPages!.pages.length;
                                final isSinglePage = totalPages <= 1;
                                final double sliderMax = isSinglePage ? 1.0 : (totalPages - 1).toDouble();
                                final int? sliderDivisions = isSinglePage ? null : totalPages - 1;
                                final double sliderVal = isSinglePage
                                    ? 0.0
                                    : pageIndex.toDouble().clamp(0.0, sliderMax);

                                return SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 16,
                                    trackShape: M3ExpressiveSliderTrackShape(
                                      trackHeight: 16,
                                      trackRadius: 8,
                                      divisions: isSinglePage ? 0 : totalPages - 1,
                                    ),
                                    thumbShape: const M3ExpressiveBarThumbShape(
                                      thumbWidth: 4,
                                      thumbHeight: 28,
                                      borderRadius: 2,
                                    ),
                                    tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 0),
                                    activeTrackColor: const Color(0xFF8AB4F8),
                                    inactiveTrackColor: const Color(0xFF363C48),
                                    thumbColor: const Color(0xFF8AB4F8),
                                    overlayColor: const Color(0xFF8AB4F8).withValues(alpha: 0.15),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                                    showValueIndicator: ShowValueIndicator.onDrag,
                                    valueIndicatorColor: const Color(0xFF252932),
                                    valueIndicatorTextStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  child: Slider(
                                    value: sliderVal,
                                    min: 0,
                                    max: sliderMax,
                                    divisions: sliderDivisions,
                                    label: '${_formatPageDisplay(pageIndex, _chapterPages!.totalPages)} / ${_chapterPages!.totalPages}',
                                    onChangeStart: isSinglePage ? null : (_) {
                                      _controlsAutoHideTimer?.cancel();
                                      setState(() => _isSliderDragging = true);
                                    },
                                    onChanged: isSinglePage ? (_) {} : (val) {
                                      _currentPageIndex = val.round();
                                      _currentPageNotifier.value = val.round();
                                    },
                                    onChangeEnd: isSinglePage ? null : (val) {
                                      final targetPage = val.round();
                                      _currentPageIndex = targetPage;
                                      _currentPageNotifier.value = targetPage;
                                      _jumpToPage(targetPage);
                                      _isSliderDragging = false;
                                      _scheduleAutoHideControls(duration: const Duration(seconds: 3));
                                    },
                                  ),
                                );
                              },
                            )
                          : const SizedBox.shrink(),
                    ),

                    // Skip Next Chapter
                    IconButton(
                      iconSize: 30,
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: _hasNextChapter ? Colors.white : Colors.white38,
                      ),
                      tooltip: 'Chapter Berikutnya',
                      onPressed: _hasNextChapter ? _goToNextChapter : null,
                    ),

                    // Chapter List Button
                    IconButton(
                      iconSize: 26,
                      icon: const Icon(
                        Icons.format_list_bulleted_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Daftar Chapter',
                      onPressed: _showChapterListBottomSheet,
                    ),

                    // More Menu (opens Reader Settings Sheet)
                    IconButton(
                      iconSize: 26,
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                      tooltip: 'Opsi Reader',
                      onPressed: _showReaderSettingsSheet,
                    ),
                  ],
                ),
              ),
              ),
            ),

            if (_showAutoScrollPanel)
              Positioned(
                left: 16,
                right: 16,
                bottom: (_showControls ? 78 : 16) + bottomPadding,
                child: _buildAutoScrollFloatingCard(),
              ),

            // Kotatsu Chapter Announcement HUD Toast (ReaderToastView)
            _buildChapterToast(context),
          ],
        ),
      ),
    ), // Scaffold
    ); // ScaffoldMessenger
  }

  Widget _buildAutoScrollFloatingCard() {
    final theme = Theme.of(context);
    final speedLabel = 'x${_autoScrollSpeed.toStringAsFixed(1).replaceAll('.', ',')}';

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      'Pengguliran otomatis',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: _hideAutoScrollPanel,
                  icon: Icon(
                    Icons.close,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
              child: Row(
                children: [
                  Text(
                    'Aktifkan',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      speedLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: _autoScrollEnabled,
                    onChanged: (val) {
                      setState(() {
                        _autoScrollEnabled = val;
                        _isAutoScrollPaused = false;
                      });
                      if (val) {
                        _startAutoScroll();
                      } else {
                        _stopAutoScroll();
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
              child: Row(
                children: [
                  Text(
                    'Kecepatan',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 20,
                        trackShape: const M3ExpressiveSliderTrackShape(
                          trackHeight: 20,
                          trackRadius: 10,
                        ),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 12,
                          elevation: 2,
                        ),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                      ),
                      child: Slider(
                        value: _autoScrollSpeed,
                        min: 0.1,
                        max: 3.0,
                        divisions: 29,
                        onChanged: (val) {
                          setState(() => _autoScrollSpeed = val);
                          if (_autoScrollEnabled) _startAutoScroll();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                setState(() => _showFloatingControl = !_showFloatingControl);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tampilkan tombol kontrol mengambang',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Checkbox(
                      value: _showFloatingControl,
                      onChanged: (val) {
                        setState(() => _showFloatingControl = val ?? false);
                      },
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

  // Kotatsu-style Floating Chapter Announcement Toast (ReaderToastView)
  Widget _buildChapterToast(BuildContext context) {
    if (_toastAnimController == null) return const SizedBox.shrink();
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    return Positioned(
      bottom: (_showControls ? 88 : 28) + bottomPadding,
      left: 20,
      right: 20,
      child: AnimatedBuilder(
        animation: _toastAnimController!,
        builder: (context, child) {
          final opacity = _toastFadeAnim?.value ?? 0.0;
          if (opacity <= 0.0) return const SizedBox.shrink();
          final scale = _toastScaleAnim?.value ?? 1.0;
          return Center(
            child: IgnorePointer(
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xDD1E1D24),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0x33FFFFFF),
                        width: 1.0,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_stories_rounded,
                          size: 16,
                          color: Color(0xFF8AB4F8),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _toastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReaderBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Memuat halaman komik...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_error != null || _chapterPages == null) {
      final chSlug = _currentChapter.slug;
      final cfUrl = chSlug.startsWith('http')
          ? chSlug
          : '${MangaSource.getBaseUrlForSource(widget.source)}/${chSlug.replaceFirst(RegExp(r"^/"), "")}';

      return ErrorView(
        message: _error ?? 'Gagal memuat halaman chapter',
        onRetry: _loadChapterPages,
        cloudflareUrl: cfUrl,
        sourceName: widget.sourceName ?? widget.source,
      );
    }

    final pages = _chapterPages!.pages;
    if (pages.isEmpty) {
      return const Center(
        child: Text('Tidak ada gambar pada chapter ini.', style: TextStyle(color: Colors.white)),
      );
    }

    if (_readerMode == ReaderMode.webtoon) {
      return Stack(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _isWebtoonZoomedNotifier,
            builder: (context, isZoomed, child) {
              return InteractiveViewer(
                transformationController: _webtoonTransformController,
                minScale: 1.0,
                maxScale: 3.5,
                panEnabled: isZoomed,
                scaleEnabled: true,
                child: child!,
              );
            },
            child: Listener(
              onPointerDown: (_) => _isUserDragging = true,
              onPointerUp: (_) {
                _isUserDragging = false;
                _handlePullRelease();
              },
              onPointerCancel: (_) {
                _isUserDragging = false;
                _resetPullState();
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleWebtoonScrollNotification,
                child: ListView.builder(
                  controller: _scrollController,
                  physics: WebtoonSmoothScrollPhysics(
                    parent: const AlwaysScrollableScrollPhysics(),
                    isJumpingOrResuming: () =>
                        _webtoonJumpTargetIndex != null ||
                        _resumePending ||
                        _applyingResume,
                  ),
                  // ignore: deprecated_member_use
                  cacheExtent: 3800.0,
                  itemCount: pages.length + 1,
                  padding: EdgeInsets.zero,
                  itemBuilder: (context, index) {
                    if (index < pages.length) {
                      return KeyedSubtree(
                        key: _pageKeys.putIfAbsent(index, () => GlobalKey()),
                        child: _buildWebtoonPageImage(pages[index], index),
                      );
                    }
                    return _buildWebtoonEndTransition();
                  },
                ),
              ),
            ),
          ),

          // Floating Feedback Top (Kotatsu Redo)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 16,
            left: 0,
            right: 0,
            child: Center(
              child: _buildPullFeedbackPill(
                progressNotifier: _pullTopNotifier,
                hasTarget: _hasPreviousChapter,
                readyText: 'Lepas untuk membuka bab sebelumnya',
                emptyText: 'Tidak ada bab sebelumnya',
                isTop: true,
              ),
            ),
          ),

          // Floating Feedback Bottom (Kotatsu Redo)
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 24,
            left: 0,
            right: 0,
            child: Center(
              child: _buildPullFeedbackPill(
                progressNotifier: _pullBottomNotifier,
                hasTarget: _hasNextChapter,
                readyText: 'Lepas untuk membuka bab selanjutnya',
                emptyText: 'Tidak ada bab berikutnya',
                isTop: false,
              ),
            ),
          ),
        ],
      );
    }

    final isRtl = _readerMode == ReaderMode.pagedRtl;
    final isVertical = _readerMode == ReaderMode.verticalPager;

    final IconData prevIcon = isVertical
        ? Icons.arrow_upward_rounded
        : (isRtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded);
    final IconData nextIcon = isVertical
        ? Icons.arrow_downward_rounded
        : (isRtl ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded);

    final bool isDualActive = _isDualPageActive;
    final List<_PageSpread> spreads = isVertical
        ? List.generate(pages.length, (i) => _PageSpread(i))
        : _buildSpreads(pages.length, isDualActive, _shiftFirstPageCover);

    return Stack(
      children: [
        Listener(
          onPointerDown: (_) => _isUserDragging = true,
          onPointerUp: (_) {
            _isUserDragging = false;
            _handlePullRelease();
          },
          onPointerCancel: (_) {
            _isUserDragging = false;
            _resetPullState();
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleWebtoonScrollNotification,
            child: PageView.builder(
              controller: _pageController,
              reverse: isRtl,
              scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
              physics: const PageScrollPhysics(parent: ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics())),
              itemCount: spreads.length,
              onPageChanged: (index) {
                if (!_showControls) {
                  _hideStatusBarNow();
                }
                if (isDualActive && !isVertical) {
                  final spread = spreads[index.clamp(0, spreads.length - 1)];
                  _currentPageIndex = spread.firstIndex;
                  _currentPageNotifier.value = spread.firstIndex;
                } else {
                  _currentPageIndex = index;
                  _currentPageNotifier.value = index;
                }
                _targetPageIndex = null;
                _scheduleSaveProgress();
                _prefetchNextPages(_currentPageIndex);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _precacheSurroundingPages(_currentPageIndex);
                });
              },
              itemBuilder: (context, index) {
                final spread = spreads[index];
                if (!spread.isDual) {
                  final p = spread.firstIndex;
                  return _ZoomablePageItem(
                    key: ValueKey('zoom_page_${pages[p].url}'),
                    onLongPress: _showReaderSettingsSheet,
                    child: Center(
                      child: _buildStandardPageImage(pages[p], pageIndex: p),
                    ),
                  );
                } else {
                  final p1 = spread.firstIndex;
                  final p2 = spread.secondIndex!;
                  // Kotatsu Redo Dual Page:
                  // For RTL (Japanese Manga): right page is p1 (earlier), left page is p2 (later)
                  // For LTR (Western/Korean): left page is p1 (earlier), right page is p2 (later)
                  final leftIndex = isRtl ? p2 : p1;
                  final rightIndex = isRtl ? p1 : p2;

                  return _ZoomablePageItem(
                    key: ValueKey('zoom_spread_${pages[leftIndex].url}_${pages[rightIndex].url}'),
                    onLongPress: _showReaderSettingsSheet,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Center(
                            child: _buildStandardPageImage(pages[leftIndex], pageIndex: leftIndex),
                          ),
                        ),
                        Container(
                          width: 1,
                          color: Colors.black.withValues(alpha: 0.6),
                        ),
                        Expanded(
                          child: Center(
                            child: _buildStandardPageImage(pages[rightIndex], pageIndex: rightIndex),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ),

        // Floating Feedback Prev Chapter (Kotatsu Redo)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 16,
          left: 0,
          right: 0,
          child: Center(
            child: _buildPullFeedbackPill(
              progressNotifier: _pullTopNotifier,
              hasTarget: _hasPreviousChapter,
              readyText: 'Lepas untuk membuka bab sebelumnya',
              emptyText: 'Tidak ada bab sebelumnya',
              isTop: true,
              customIcon: prevIcon,
            ),
          ),
        ),

        // Floating Feedback Next Chapter (Kotatsu Redo)
        Positioned(
          bottom: MediaQuery.paddingOf(context).bottom + 24,
          left: 0,
          right: 0,
          child: Center(
            child: _buildPullFeedbackPill(
              progressNotifier: _pullBottomNotifier,
              hasTarget: _hasNextChapter,
              readyText: 'Lepas untuk membuka bab selanjutnya',
              emptyText: 'Tidak ada bab berikutnya',
              isTop: false,
              customIcon: nextIcon,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWebtoonEndTransition() {
    final next = _nextChapter;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF16151A),
        border: Border(top: BorderSide(color: Color(0xFF2C2A34), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF8AB4F8).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF8AB4F8),
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Selesai: ${_currentChapter.title}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (next != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF201F26),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E2C38)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_rounded, size: 16, color: Color(0xFF8AB4F8)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Selanjutnya: ${next.title}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8AB4F8),
                foregroundColor: const Color(0xFF16151A),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text(
                'Buka Bab Berikutnya',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              onPressed: _goToNextChapter,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swipe_up_rounded, size: 16, color: Colors.white38),
                const SizedBox(width: 6),
                Text(
                  _pullGestureEnabled
                      ? 'Tarik ke atas untuk memuat bab selanjutnya'
                      : 'Tekan tombol di atas untuk bab berikutnya',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ] else ...[
            const Text(
              'Kamu telah membaca bab paling baru!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF363C48)),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Kembali ke Detail', style: TextStyle(fontSize: 13)),
              onPressed: _exitReader,
            ),
          ],
        ],
      ),
    );
  }

  bool _handleWebtoonScrollNotification(ScrollNotification notification) {
    if (!_pullGestureEnabled || _isWebtoonZoomedNotifier.value) return false;

    if (notification is ScrollStartNotification) {
      if (!_showControls) {
        _hideStatusBarNow();
      }
      if (notification.dragDetails != null) {
        _isUserDragging = true;
        _targetScrollOffset = null;
        _targetPageIndex = null;
        _resumeFollowAnchor = false;
        _resumeFollowTimer?.cancel();
        _webtoonJumpTargetIndex = null;
        _webtoonJumpTimer?.cancel();
        _webtoonJumpFollowTimer?.cancel();
        if (_resumePending) {
          _resumePending = false;
          _resumeSettleTimer?.cancel();
        }
      }
    } else if (notification is ScrollUpdateNotification) {
      _lastKnownScrollOffset = notification.metrics.pixels;
      final maxExtent = notification.metrics.maxScrollExtent;
      _isAtEndKnown = maxExtent > 100 &&
          notification.metrics.pixels > 50 &&
          (notification.metrics.pixels >= maxExtent - 40 ||
              notification.metrics.extentAfter <= 40);
      if (_isUserDragging && !_isLoading && !_isChangingChapter) {
        final metrics = notification.metrics;
        final pixels = metrics.pixels;
        final maxExtent = metrics.maxScrollExtent;

        if (pixels < 0) {
          final overscroll = -pixels;
          final progress = (overscroll / _pullThreshold).clamp(0.0, 1.2);
          _pullTopNotifier.value = progress;
          _pullBottomNotifier.value = 0.0;
          if (progress >= 1.0 && !_isHapticTriggeredTop) {
            HapticFeedback.lightImpact();
            _isHapticTriggeredTop = true;
          } else if (progress < 1.0) {
            _isHapticTriggeredTop = false;
          }
        } else if (maxExtent > 0 && pixels > maxExtent) {
          final overscroll = pixels - maxExtent;
          final progress = (overscroll / _pullThreshold).clamp(0.0, 1.2);
          _pullBottomNotifier.value = progress;
          _pullTopNotifier.value = 0.0;
          if (progress >= 1.0 && !_isHapticTriggeredBottom) {
            HapticFeedback.lightImpact();
            _isHapticTriggeredBottom = true;
          } else if (progress < 1.0) {
            _isHapticTriggeredBottom = false;
          }
        } else {
          _accumulatedOverscrollTop = 0.0;
          _accumulatedOverscrollBottom = 0.0;
          if (_pullTopNotifier.value != 0.0) _pullTopNotifier.value = 0.0;
          if (_pullBottomNotifier.value != 0.0) _pullBottomNotifier.value = 0.0;
          _isHapticTriggeredTop = false;
          _isHapticTriggeredBottom = false;
        }
      }
    } else if (notification is OverscrollNotification) {
      if (_isUserDragging && !_isLoading && !_isChangingChapter) {
        if (notification.overscroll < 0) {
          _accumulatedOverscrollTop += -notification.overscroll;
          final progress = (_accumulatedOverscrollTop / _pullThreshold).clamp(0.0, 1.2);
          _pullTopNotifier.value = progress;
          _pullBottomNotifier.value = 0.0;
          if (progress >= 1.0 && !_isHapticTriggeredTop) {
            HapticFeedback.lightImpact();
            _isHapticTriggeredTop = true;
          } else if (progress < 1.0) {
            _isHapticTriggeredTop = false;
          }
        } else if (notification.overscroll > 0) {
          _accumulatedOverscrollBottom += notification.overscroll;
          final progress = (_accumulatedOverscrollBottom / _pullThreshold).clamp(0.0, 1.2);
          _pullBottomNotifier.value = progress;
          _pullTopNotifier.value = 0.0;
          if (progress >= 1.0 && !_isHapticTriggeredBottom) {
            HapticFeedback.lightImpact();
            _isHapticTriggeredBottom = true;
          } else if (progress < 1.0) {
            _isHapticTriggeredBottom = false;
          }
        }
      }
    } else if (notification is ScrollEndNotification) {
      if (!_isUserDragging) {
        _handlePullRelease();
      }
    }
    return false;
  }

  void _handlePullRelease() {
    final topProg = _pullTopNotifier.value;
    final bottomProg = _pullBottomNotifier.value;

    _resetPullState();

    if (!_isLoading && !_isChangingChapter) {
      if (topProg >= 1.0) {
        if (_hasPreviousChapter) {
          HapticFeedback.mediumImpact();
          _isChangingChapter = true;
          _goToPreviousChapter(startAtEnd: true);
        }
      } else if (bottomProg >= 1.0) {
        if (_hasNextChapter) {
          HapticFeedback.mediumImpact();
          _isChangingChapter = true;
          _goToNextChapter();
        }
      }
    }
  }

  void _resetPullState() {
    _accumulatedOverscrollTop = 0.0;
    _accumulatedOverscrollBottom = 0.0;
    _isHapticTriggeredTop = false;
    _isHapticTriggeredBottom = false;
    if (_pullTopNotifier.value != 0.0) _pullTopNotifier.value = 0.0;
    if (_pullBottomNotifier.value != 0.0) _pullBottomNotifier.value = 0.0;
  }

  Widget _buildPullFeedbackPill({
    required ValueNotifier<double> progressNotifier,
    required bool hasTarget,
    required String readyText,
    required String emptyText,
    required bool isTop,
    IconData? customIcon,
  }) {
    if (!_pullGestureEnabled) return const SizedBox.shrink();

    return ValueListenableBuilder<double>(
      valueListenable: progressNotifier,
      builder: (context, progress, child) {
        final clamped = progress.clamp(0.0, 1.2);
        if (clamped <= 0.0) return const SizedBox.shrink();

        final isReady = clamped >= 1.0;
        final alpha = (0.15 + 0.85 * clamped.clamp(0.0, 1.0)).clamp(0.0, 1.0);
        final scale = 0.9 + 0.1 * clamped.clamp(0.0, 1.0);

        final displayText = hasTarget
            ? (isReady
                ? readyText
                : (isTop ? 'Tarik untuk bab sebelumnya' : 'Tarik untuk bab selanjutnya'))
            : emptyText;

        final IconData icon = !hasTarget
            ? Icons.block_rounded
            : (customIcon ?? (isTop ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded));

        final Color primaryAccent = const Color(0xFF8AB4F8);

        return IgnorePointer(
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: alpha,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xCC1E1D24), // #99000000 dim
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isReady && hasTarget
                        ? primaryAccent
                        : const Color(0x33FFFFFF),
                    width: isReady && hasTarget ? 2.0 : 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isReady && hasTarget ? primaryAccent : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      displayText,
                      style: TextStyle(
                        color: isReady && hasTarget ? primaryAccent : Colors.white,
                        fontSize: 13,
                        fontWeight: isReady && hasTarget ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Webtoon page with height measurement for accurate slider tracking
  Widget _buildWebtoonPageImage(MangaPage page, int index) {
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return MeasuredPageWidget(
      onHeight: (h) => _onPageHeightMeasured(index, h),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isLandscape ? 720 : double.infinity,
          ),
          child: _buildPageImage(page, pageIndex: index),
        ),
      ),
    );
  }

  void _onConnectivityChanged() async {
    if (!mounted) return;
    final isConnected = NetworkService.isConnectedNotifier.value;
    if (isConnected) {
      // Debounce sebentar agar interface jaringan stabil
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;

      final hasInternet = await NetworkService.checkConnection();
      if (!mounted || !hasInternet) return;

      _messengerKey.currentState?.hideCurrentSnackBar();

      if (_error != null || _chapterPages == null) {
        _loadChapterPages();
      } else if (_failedPageIndices.isNotEmpty) {
        _retryAllFailedPages();
      }
    }
  }

  void _evictPageCache(String url) {
    if (url.trim().isEmpty) return;
    PageSliceCache.instance.invalidate(url);
    CachedNetworkImage.evictFromCache(url);
    PaintingBinding.instance.imageCache.evict(NetworkImage(url));

    final dimRegex = RegExp(r'-\d+x\d+(?=\.[a-zA-Z0-9]+$)');
    final cleanMaster = url.replaceFirst(dimRegex, '');
    final wsrv = 'https://wsrv.nl/?url=${Uri.encodeComponent(cleanMaster)}&we';
    CachedNetworkImage.evictFromCache(wsrv);
    PaintingBinding.instance.imageCache.evict(NetworkImage(wsrv));
  }

  void _retryPage(MangaPage page, {int? pageIndex}) {
    _evictPageCache(page.url);
    if (pageIndex != null) {
      _loadedPages.remove(pageIndex);
      _failedPageIndices.remove(pageIndex);
    }
    setState(() {
      if (pageIndex != null) {
        _pageRetryCounters[pageIndex] = (_pageRetryCounters[pageIndex] ?? 0) + 1;
      }
      _globalRetryCounter++;
    });
  }

  void _retryAllFailedPages() {
    if (_failedPageIndices.isEmpty) return;
    final pages = _chapterPages?.pages;
    for (final idx in _failedPageIndices.toList()) {
      _loadedPages.remove(idx);
      if (pages != null && idx < pages.length) {
        _evictPageCache(pages[idx].url);
      }
      _pageRetryCounters[idx] = (_pageRetryCounters[idx] ?? 0) + 1;
    }
    _failedPageIndices.clear();
    setState(() {
      _globalRetryCounter++;
    });
  }

  Widget _buildPageImage(MangaPage page, {int? pageIndex}) {
    final retry = (_pageRetryCounters[pageIndex] ?? 0) + _globalRetryCounter;
    final imageWidget = SlicedPageImage(
      key: ValueKey('slice_${page.url}_$retry'),
      url: page.url,
      referer: _chapterPages?.referer ?? refererFor(page.url, source: widget.source)['Referer'],
      onLoaded: pageIndex != null ? () {
        _failedPageIndices.remove(pageIndex);
        _onPageImageLoaded(pageIndex);
      } : null,
      placeholderBuilder: () => _buildPageLoading(pageIndex: pageIndex),
      fallbackBuilder: () => _buildLegacyPageImage(page, pageIndex: pageIndex, retryCount: retry),
    );

    return ReaderPageTranslatorWrapper(
      pageUrl: page.url,
      pageKey: '${_currentChapter.slug}_p${pageIndex ?? page.page}',
      fit: BoxFit.fitWidth,
      child: imageWidget,
    );
  }

  Widget _buildLegacyPageImage(MangaPage page, {int? pageIndex, int retryCount = 0}) {
    return CachedCover(
      key: ValueKey('cover_${page.url}_$retryCount'),
      imageUrl: page.url,
      source: widget.source,
      extraHeaders: _chapterPages?.referer != null ? {'Referer': _chapterPages!.referer!} : null,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      memCacheWidth: (MediaQuery.sizeOf(context).width * 2.2).round(),
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      imageBuilder: (context, imageProvider) {
        if (pageIndex != null) {
          _failedPageIndices.remove(pageIndex);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onPageImageLoaded(pageIndex);
          });
        }
        return WebtoonSafeImage(
          imageProvider: imageProvider,
          fit: BoxFit.fitWidth,
          width: double.infinity,
        );
      },
      progressIndicatorBuilder: (context, url, progress) {
        final percent = progress.progress != null
            ? (progress.progress! * 100).round()
            : null;
        return _buildPageLoading(percent: percent, pageIndex: pageIndex);
      },
      errorWidget: (context, url, error) {
        if (pageIndex != null) {
          _failedPageIndices.add(pageIndex);
        }
        return _buildPageError(page, pageIndex: pageIndex);
      },
    );
  }

  Widget _buildPageLoading({int? percent, int? pageIndex}) {
    final placeholderHeight = (pageIndex != null ? (_pageHeights[pageIndex] ?? widget.initialPageHeights?[pageIndex]) : null) ?? _estimatedPageHeight;
    return SizedBox(
      height: placeholderHeight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                value: percent != null ? percent / 100.0 : null,
                strokeWidth: 3,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              percent != null ? '$percent%' : 'Memuat...',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageError(MangaPage page, {int? pageIndex}) {
    return SizedBox(
      height: 280,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 40),
              const SizedBox(height: 12),
              Text(
                'Gagal memuat hal. ${page.page}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _retryPage(page, pageIndex: pageIndex),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E2E2E),
                  foregroundColor: Colors.white70,
                ),
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandardPageImage(MangaPage page, {int? pageIndex}) {
    final retry = (_pageRetryCounters[pageIndex] ?? 0) + _globalRetryCounter;
    final refHeaders = refererFor(page.url, source: widget.source);
    final headers = <String, String>{
      ...refHeaders,
      if (_chapterPages?.referer != null) 'Referer': _chapterPages!.referer!,
    };
    final pageWidget = CachedCover(
      key: ValueKey('std_page_${page.url}_$retry'),
      imageUrl: page.url,
      source: widget.source,
      extraHeaders: headers.isNotEmpty ? headers : null,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: (MediaQuery.sizeOf(context).width * 2.2).round(),
      fadeInDuration: const Duration(milliseconds: 100),
      fadeOutDuration: Duration.zero,
      imageBuilder: (context, imageProvider) {
        if (pageIndex != null) {
          _failedPageIndices.remove(pageIndex);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onPageImageLoaded(pageIndex);
          });
        }
        return Image(
          image: imageProvider,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.medium,
        );
      },
      progressIndicatorBuilder: (context, url, progress) {
        final percent = progress.progress != null
            ? (progress.progress! * 100).round()
            : null;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  value: percent != null ? percent / 100.0 : null,
                  strokeWidth: 3,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                percent != null ? '$percent%' : 'Memuat...',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
      errorWidget: (context, url, error) {
        if (pageIndex != null) {
          _failedPageIndices.add(pageIndex);
        }
        return _buildPageError(page, pageIndex: pageIndex);
      },
    );

    return ReaderPageTranslatorWrapper(
      pageUrl: page.url,
      pageKey: '${_currentChapter.slug}_p${pageIndex ?? page.page}',
      fit: BoxFit.contain,
      child: pageWidget,
    );
  }
}

/// Kotatsu-style smooth zoomable page item:
/// Uses InteractiveViewer for hardware-accelerated pinch-to-zoom (up to 4.0x).
/// When unzoomed (scale <= 1.05), pan is disabled so PageView swiping receives
/// gestures with zero lag and 120fps tracking.
/// Double-tap recognizer is omitted so tap navigation operates with 0ms arena latency.
class _ZoomablePageItem extends StatefulWidget {
  final Widget child;
  final VoidCallback? onLongPress;

  const _ZoomablePageItem({
    super.key,
    required this.child,
    this.onLongPress,
  });

  @override
  State<_ZoomablePageItem> createState() => _ZoomablePageItemState();
}

class _ZoomablePageItemState extends State<_ZoomablePageItem> {
  late final TransformationController _transformationController;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.addListener(_onTransformationChanged);
  }

  void _onTransformationChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() {
        _isZoomed = zoomed;
      });
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transformationController,
      minScale: 1.0,
      maxScale: 4.0,
      panEnabled: _isZoomed,
      scaleEnabled: true,
      child: widget.child,
    );
  }
}

/// Widget yang mengukur tinggi child-nya setelah layout selesai
class MeasuredPageWidget extends StatefulWidget {
  final Widget child;
  final ValueChanged<double> onHeight;

  const MeasuredPageWidget({super.key, required this.child, required this.onHeight});

  @override
  State<MeasuredPageWidget> createState() => _MeasuredPageWidgetState();
}

class _MeasuredPageWidgetState extends State<MeasuredPageWidget> with AutomaticKeepAliveClientMixin {
  final GlobalKey _key = GlobalKey();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      widget.onHeight(box.size.height);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: Container(key: _key, child: widget.child),
      ),
    );
  }
}

/// Material 3 Expressive Slider - Track Shape berbentuk kapsul/pill tebal dengan titik putih
class M3ExpressiveSliderTrackShape extends SliderTrackShape {
  final double trackHeight;
  final double trackRadius;
  final int divisions;

  const M3ExpressiveSliderTrackShape({
    this.trackHeight = 16.0,
    this.trackRadius = 8.0,
    this.divisions = 0,
  });

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    // Inset travel range so pill caps extend naturally on both sides
    final double trackLeft = offset.dx + 10.0;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = (parentBox.size.width - 20.0).clamp(0.0, double.infinity);
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Canvas canvas = context.canvas;
    final Color inactiveColor = sliderTheme.inactiveTrackColor ?? const Color(0xFF363C48);
    final Color activeColor = sliderTheme.activeTrackColor ?? const Color(0xFF8AB4F8);

    // Pill background extends 6px beyond thumb limits on left & right
    final Rect pillRect = Rect.fromLTRB(
      trackRect.left - 6.0,
      trackRect.top,
      trackRect.right + 6.0,
      trackRect.bottom,
    );
    final RRect fullTrackRRect = RRect.fromRectAndRadius(
      pillRect,
      Radius.circular(trackRadius),
    );

    // 1. Draw Inactive Track (Full rounded pill background)
    final Paint inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(fullTrackRRect, inactivePaint);

    // 2. Draw Active Track (From pillRect.left to thumbCenter.dx)
    final double activeRight = thumbCenter.dx.clamp(pillRect.left, pillRect.right);
    if (activeRight > pillRect.left) {
      final Rect activeRect = Rect.fromLTRB(
        pillRect.left,
        pillRect.top,
        activeRight,
        pillRect.bottom,
      );
      canvas.save();
      canvas.clipRRect(fullTrackRRect);
      final Paint activePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(activeRect, activePaint);
      canvas.restore();
    }

    // 3. Draw Discrete White Dots (Seperti di foto Kotatsu)
    if (divisions > 1) {
      final double trackWidth = trackRect.width;
      final double centerY = trackRect.center.dy;

      int step = 1;
      final double spacing = trackWidth / divisions;
      if (spacing < 8.0) {
        step = (8.0 / spacing).ceil();
      }

      for (int i = 0; i <= divisions; i += step) {
        final double dotX = trackRect.left + (i * (trackWidth / divisions));

        // Lewati jika tertutup oleh handle thumb vertikal
        if ((dotX - thumbCenter.dx).abs() < 4.0) continue;

        final bool isActive = dotX < thumbCenter.dx;
        final Paint dotPaint = Paint()
          ..color = isActive
              ? const Color(0xFF142033)
              : Colors.white
          ..style = PaintingStyle.fill;

        canvas.drawCircle(Offset(dotX, centerY), 2.0, dotPaint);
      }
    }
  }
}

/// Material 3 Expressive Slider - Thumb berbentuk bar/garis vertikal dengan sudut membulat
class M3ExpressiveBarThumbShape extends SliderComponentShape {
  final double thumbWidth;
  final double thumbHeight;
  final double borderRadius;

  const M3ExpressiveBarThumbShape({
    this.thumbWidth = 4.0,
    this.thumbHeight = 28.0,
    this.borderRadius = 2.0,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(thumbWidth, thumbHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: thumbWidth,
        height: thumbHeight,
      ),
      Radius.circular(borderRadius),
    );

    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? const Color(0xFF8AB4F8)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(rect, paint);
  }
}

/// Material 3 Expressive Slider - Tick mark berupa titik putih/gelap di dalam track
class M3ExpressiveTickMarkShape extends SliderTickMarkShape {
  final double tickRadius;

  const M3ExpressiveTickMarkShape({this.tickRadius = 1.8});

  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) {
    return Size.fromRadius(tickRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    required bool isEnabled,
  }) {
    // Sembunyikan titik yang berada tepat di bawah handle thumb
    if ((center.dx - thumbCenter.dx).abs() < 4) return;

    final bool isActive = center.dx < thumbCenter.dx;
    final Color dotColor = isActive
        ? const Color(0xFF142033)
        : Colors.white.withValues(alpha: 0.95);

    final Paint paint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    context.canvas.drawCircle(center, tickRadius, paint);
  }
}

/// Kotatsu-Redo inspired smooth scroll physics for Webtoon mode.
/// Mimics Android RecyclerView's SplineOverScroller with low kinetic friction (0.011),
/// fast gesture responsiveness (reduced touch-slop and low fling threshold),
/// and firm clamping at boundaries without bouncing (no bounce / anti mantul-mantul).
class WebtoonSmoothScrollPhysics extends ClampingScrollPhysics {
  final bool Function()? isJumpingOrResuming;
  const WebtoonSmoothScrollPhysics({super.parent, this.isJumpingOrResuming});

  @override
  WebtoonSmoothScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return WebtoonSmoothScrollPhysics(
      parent: buildParent(ancestor),
      isJumpingOrResuming: isJumpingOrResuming,
    );
  }

  @override
  double get minFlingVelocity => 25.0; // Responsive Kotatsu flick gesture

  @override
  double get dragStartDistanceMotionThreshold => 2.0;

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if (isJumpingOrResuming?.call() == true) {
      return null;
    }
    final Tolerance tolerance = toleranceFor(position);
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    if (velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      friction: 0.011, // Smooth Android SplineOverScroller kinetic deceleration
      tolerance: tolerance,
    );
  }
}
