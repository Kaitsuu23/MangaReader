import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/cached_cover.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';
import '../../core/services/sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/manga_details.dart';
import '../../shared/models/chapter.dart';
import '../../shared/widgets/manga_card.dart';
import '../../shared/widgets/shimmer_loading.dart';
import '../../shared/widgets/error_view.dart';
import '../reader/manga_reader_screen.dart';
import '../explore/source_view_screen.dart';
import '../explore/search_screen.dart';
import '../../core/theme/in_place_predictive_back_page_transitions_builder.dart';
import '../favorites/manage_categories_screen.dart';
import '../favorites/category_edit_screen.dart';
import '../../shared/widgets/in_app_browser_screen.dart';
import 'alternatives_screen.dart';
import '../../shared/models/manga_item.dart';
import '../../shared/models/manga_source.dart';
import '../webview/cloudflare_solver_screen.dart';
import '../content_mode/transfer_manga_dialog.dart';
import '../feed/feed_provider.dart';
import '../../core/services/network_service.dart';

class MangaDetailsScreen extends ConsumerStatefulWidget {
  final String slug;
  final String source;
  final String? title;
  final String? cover;
  final String
  origin; // 'source_view', 'history', 'favorites', 'feed', 'explore'
  final String? sourceName;
  final String? id;

  const MangaDetailsScreen({
    super.key,
    required this.slug,
    required this.source,
    this.title,
    this.cover,
    this.origin = 'source_view',
    this.sourceName,
    this.id,
  });

  @override
  ConsumerState<MangaDetailsScreen> createState() => _MangaDetailsScreenState();
}

// Cached per-chapter metadata to avoid recomputing in every build() call.
typedef _ChapterBuildMeta = ({int chIdx, bool isExplicitlyRead});

class _MangaDetailsScreenState extends ConsumerState<MangaDetailsScreen> {
  MangaDetails? _details;
  bool _isLoading = true;
  String? _error;
  bool _isSortAscending = LocalStorage.getChapterSortAscending();
  String _chapterSearchQuery = '';

  late final ScrollController _scrollController;
  final ValueNotifier<double> _titleOpacity = ValueNotifier<double>(0.0);

  // ---- Cached computed data (invalidated on _details / readChapterSlugs change) ----
  List<Chapter>? _cachedChronoChapters;
  final Map<String, _ChapterBuildMeta> _chapterMetaBySlug = {};
  Set<String>? _cachedReadSlugs;
  int _cachedLastReadChronoIndex = -1;
  bool _cachedHasNewerChapters = false;
  bool _cachedIsCompleted = false;

  /// Rebuild the expensive computed data only when inputs change.
  void _rebuildCachedData(List<Chapter> chronoChapters, Set<String> readChapterSlugs,
      Map<String, dynamic>? historyItem) {
    _cachedChronoChapters = chronoChapters;
    _cachedReadSlugs = readChapterSlugs;

    // Recompute lastReadChronoIndex
    int lastReadChronoIndex = -1;
    final rawLastSlug = historyItem?['chapterSlug']?.toString().trim();
    final isHashSlug =
        rawLastSlug != null && rawLastSlug.length >= 8 && int.tryParse(rawLastSlug) != null;

    if (rawLastSlug != null && rawLastSlug.isNotEmpty && chronoChapters.isNotEmpty) {
      final cleanLast = rawLastSlug.replaceAll(RegExp(r'^/+|/+$'), '');
      lastReadChronoIndex = chronoChapters.indexWhere((c) {
        if (c.slug == rawLastSlug || c.chapter == rawLastSlug) return true;
        final cleanC = c.slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
        if (cleanC == cleanLast) return true;
        if (isHashSlug) {
          if (SyncService.hashSlug(c.slug).toString() == cleanLast ||
              SyncService.hashSlug(c.chapter).toString() == cleanLast) {
            return true;
          }
        }
        return false;
      });
    }

    if (lastReadChronoIndex == -1 && historyItem?['chapterTitle'] != null && chronoChapters.isNotEmpty) {
      final chTitle = historyItem!['chapterTitle'].toString().trim().toLowerCase();
      if (chTitle.isNotEmpty) {
        lastReadChronoIndex = chronoChapters.indexWhere(
          (c) => c.title.trim().toLowerCase() == chTitle,
        );
      }
    }

    if (lastReadChronoIndex == -1 && historyItem?['chapterNumber'] != null && chronoChapters.isNotEmpty) {
      final chNumRaw = (historyItem!['chapterNumber'] as num);
      final chNum = chNumRaw.toInt();
      if (chNum > 0) {
        // Coba exact match dengan angka asli (termasuk desimal seperti 3.5)
        var idx = chronoChapters.indexWhere((c) => c.chapterNumber == chNumRaw);
        // Fallback: coba integer match
        if (idx == -1) {
          idx = chronoChapters.indexWhere((c) => c.chapterNumber?.toInt() == chNum);
        }
        if (idx != -1) {
          lastReadChronoIndex = idx;
        } else {
          // Cari chapter terdekat yang <= chNum
          for (int i = chronoChapters.length - 1; i >= 0; i--) {
            final cNum = chronoChapters[i].chapterNumber;
            if (cNum != null && cNum <= chNum) {
              lastReadChronoIndex = i;
              break;
            }
          }
          if (lastReadChronoIndex == -1 && chNum <= chronoChapters.length) {
            lastReadChronoIndex = (chNum - 1).clamp(0, chronoChapters.length - 1);
          }
        }
      }
    }

    final savedPercent = (historyItem?['percent'] as num?)?.toDouble() ?? 0.0;
    final prevTotal = (historyItem?['totalChapters'] as num?)?.toInt();
    if (lastReadChronoIndex == -1 && chronoChapters.isNotEmpty) {
      if (prevTotal != null && prevTotal > 0 && savedPercent > 0) {
        final estCh = (savedPercent * prevTotal).round();
        if (estCh > 0) lastReadChronoIndex = (estCh - 1).clamp(0, prevTotal - 1);
      } else if (savedPercent > 0 && savedPercent < 0.999) {
        lastReadChronoIndex = (savedPercent * (chronoChapters.length - 1))
            .round()
            .clamp(0, chronoChapters.length - 1);
      }
    }

    if (historyItem != null && lastReadChronoIndex == -1 && readChapterSlugs.isNotEmpty && chronoChapters.isNotEmpty) {
      for (int i = chronoChapters.length - 1; i >= 0; i--) {
        final c = chronoChapters[i];
        final cleanSlug = c.slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
        final hashSlug = SyncService.hashSlug(c.slug).toString();
        if (readChapterSlugs.contains(c.slug) ||
            readChapterSlugs.contains(cleanSlug) ||
            readChapterSlugs.contains(c.chapter) ||
            readChapterSlugs.contains(hashSlug)) {
          if (prevTotal != null && prevTotal > 0 && i >= prevTotal && chronoChapters.length > prevTotal) continue;
          lastReadChronoIndex = i;
          break;
        }
      }
    }

    final bool isLastChapter =
        lastReadChronoIndex >= 0 && lastReadChronoIndex == chronoChapters.length - 1;
    final page = (historyItem?['page'] as num?)?.toInt() ?? 1;
    final totalPages = (historyItem?['totalPages'] as num?)?.toInt() ?? 1;
    // Jika source punya chapter lebih banyak dari yang tersimpan di history, ada chapter baru
    final bool hasNewChaptersSinceLastRead =
        prevTotal != null && prevTotal > 0 && chronoChapters.length > prevTotal;
    final bool isCompleted = !hasNewChaptersSinceLastRead &&
        isLastChapter && (savedPercent >= 0.999 || totalPages <= 1 || page >= totalPages);
    final bool hasNewerChapters = !isCompleted &&
        lastReadChronoIndex >= 0 && lastReadChronoIndex < chronoChapters.length - 1;

    _cachedLastReadChronoIndex = lastReadChronoIndex;
    _cachedHasNewerChapters = hasNewerChapters;
    _cachedIsCompleted = isCompleted;

    _chapterMetaBySlug.clear();
    final hashCache = <String, String>{};
    for (int i = 0; i < chronoChapters.length; i++) {
      final ch = chronoChapters[i];
      final cleanSlug = ch.slug.trim().replaceAll(RegExp(r'^[/]+|[/]+$'), '');
      final hashSlug = hashCache.putIfAbsent(ch.slug, () => SyncService.hashSlug(ch.slug).toString());
      final isExplicitlyRead =
          (ch.slug.isNotEmpty && readChapterSlugs.contains(ch.slug)) ||
          (cleanSlug.isNotEmpty && readChapterSlugs.contains(cleanSlug)) ||
          (ch.chapter.isNotEmpty && readChapterSlugs.contains(ch.chapter)) ||
          (hashSlug.isNotEmpty && readChapterSlugs.contains(hashSlug));
      final meta = (chIdx: i, isExplicitlyRead: isExplicitlyRead);
      if (ch.slug.isNotEmpty) _chapterMetaBySlug[ch.slug] = meta;
      if (cleanSlug.isNotEmpty) _chapterMetaBySlug[cleanSlug] = meta;
      if (ch.chapter.isNotEmpty) _chapterMetaBySlug[ch.chapter] = meta;
    }
  }

  void _ensureCachedData(Map<String, dynamic>? historyItem, Set<String> readChapterSlugs) {
    if (_details == null || _details!.chapters.isEmpty) {
      _cachedChronoChapters = [];
      _cachedLastReadChronoIndex = -1;
      _cachedHasNewerChapters = false;
      _cachedIsCompleted = false;
      _chapterMetaBySlug.clear();
      return;
    }
    if (_cachedChronoChapters != null &&
        _cachedChronoChapters!.length == _details!.chapters.length &&
        _cachedReadSlugs != null &&
        _cachedReadSlugs == readChapterSlugs) {
      return;
    }
    final chronoChapters = Chapter.sortChronological(_details!.chapters);
    _rebuildCachedData(chronoChapters, readChapterSlugs, historyItem);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    LocalStorage.listenContentMode().addListener(_onContentModeChanged);
    _fetchDetails();
  }

  void _onContentModeChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    // Fade in TopAppBar title as user scrolls past header (offset 40 to 80)
    final targetTitleOpacity = ((offset - 40.0) / 40.0).clamp(0.0, 1.0);
    if ((_titleOpacity.value - targetTitleOpacity).abs() > 0.01) {
      _titleOpacity.value = targetTitleOpacity;
    }
  }

  @override
  void dispose() {
    LocalStorage.listenContentMode().removeListener(_onContentModeChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _titleOpacity.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(parserChannelProvider);
      final details = await api.getDetails(widget.source, widget.slug);
      if (!mounted) return;
      if (details.genres.isNotEmpty) {
        final genreNames = details.genres
            .map((g) => g.name)
            .where((n) => n.isNotEmpty)
            .toList();
        LocalStorage.saveCachedMangaGenres(
          widget.source,
          widget.slug,
          genreNames,
        );
      }
      setState(() {
        _details = details;
        _cachedChronoChapters = null;
        _isLoading = false;
      });
      _syncReadChaptersWithHistory(details);

      // Auto-update favorite metadata if this manga is in favorites (heals missing covers or slug titles)
      if (LocalStorage.isFavorite(widget.slug, source: widget.source)) {
        await LocalStorage.updateFavoriteMetadata(
          slug: widget.slug,
          source: widget.source,
          title: details.title.isNotEmpty ? details.title : null,
          cover: (details.cover != null && details.cover!.isNotEmpty)
              ? details.cover
              : null,
          type: details.type,
          latestChapter: details.chapters.isNotEmpty
              ? details.chapters.first.title
              : null,
        );
      }
      // Also update history metadata if this manga is in history
      await LocalStorage.updateHistoryMetadata(
        slug: widget.slug,
        source: widget.source,
        title: details.title.isNotEmpty ? details.title : null,
        cover: (details.cover != null && details.cover!.isNotEmpty)
            ? details.cover
            : null,
      );

      final effectiveCover = details.cover ?? widget.cover;
      if (effectiveCover != null && effectiveCover.trim().isNotEmpty) {
        LocalStorage.ensureCoverCached(
          slug: widget.slug,
          coverUrl: effectiveCover.trim(),
          source: widget.source,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      // Hanya tampilkan snackbar offline jika sebelumnya detail sudah termuat (misal saat swipe refresh gagal),
      // agar tidak menumpuk dengan tampilan ErrorView layar penuh.
      if (_details != null &&
          (NetworkService.isNetworkError(e) || !NetworkService.isConnected)) {
        NetworkService.showNoInternetSnackBar(
          context,
          onRetry: _fetchDetails,
          hasBottomNavbar: false,
        );
      }
    }
  }

  void _syncReadChaptersWithHistory(MangaDetails details) {
    if (details.chapters.isEmpty) return;
    final historyItem = LocalStorage.getHistoryItem(
      widget.slug,
      source: widget.source,
    );
    if (historyItem == null) {
      // Jika tidak ada riwayat baca aktif (misal bekas baca sudah dihapus atau dimigrasikan),
      // bersihkan sisa readChapterSlugs yang tertinggal agar bab tidak tetap berstatus terbaca (read)
      final existingRead = LocalStorage.getReadChapters(
        widget.slug,
        source: widget.source,
      );
      if (existingRead.isNotEmpty) {
        LocalStorage.clearReadChapters(widget.slug, source: widget.source);
        if (mounted) setState(() {});
      }
      return;
    }

    final chronoChapters = _getChronologicalChapters();
    if (chronoChapters.isEmpty) return;

    int lastReadIndex = -1;
    final rawLastSlug = historyItem['chapterSlug']?.toString().trim();
    final isHash =
        rawLastSlug != null &&
        rawLastSlug.length >= 8 &&
        int.tryParse(rawLastSlug) != null;
    if (rawLastSlug != null && rawLastSlug.isNotEmpty) {
      final cleanLast = rawLastSlug.replaceAll(RegExp(r'^/+|/+$'), '');
      lastReadIndex = chronoChapters.indexWhere((c) {
        if (c.slug == rawLastSlug || c.chapter == rawLastSlug) return true;
        final cleanC = c.slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
        if (cleanC == cleanLast) return true;
        if (isHash) {
          if (SyncService.hashSlug(c.slug).toString() == cleanLast ||
              SyncService.hashSlug(c.chapter).toString() == cleanLast) {
            return true;
          }
        }
        return false;
      });
    }

    if (lastReadIndex == -1 && historyItem['chapterTitle'] != null) {
      final title = historyItem['chapterTitle'].toString().trim().toLowerCase();
      if (title.isNotEmpty) {
        lastReadIndex = chronoChapters.indexWhere(
          (c) => c.title.trim().toLowerCase() == title,
        );
      }
    }

    if (lastReadIndex == -1 && historyItem['chapterNumber'] != null) {
      final chNumRaw = (historyItem['chapterNumber'] as num);
      final chNum = chNumRaw.toDouble();
      if (chNum > 0) {
        // Coba exact match dengan angka asli (desimal 3.5 dst)
        var idx = chronoChapters.indexWhere(
          (c) => c.chapterNumber != null && (c.chapterNumber! - chNum).abs() < 0.01,
        );
        if (idx == -1) {
          idx = chronoChapters.indexWhere(
            (c) => c.chapterNumber?.toInt() == chNum.toInt(),
          );
        }
        if (idx != -1) {
          lastReadIndex = idx;
        } else {
          // Cari chapter terdekat yang <= chNum
          for (int i = chronoChapters.length - 1; i >= 0; i--) {
            final cNum = chronoChapters[i].chapterNumber;
            if (cNum != null && cNum <= chNum) {
              lastReadIndex = i;
              break;
            }
          }
        }
      }
    }

    // Jika belum ketemu, coba cari dari readChapterSlugs yang tersimpan
    if (lastReadIndex == -1 && chronoChapters.isNotEmpty) {
      final readSlugs = LocalStorage.getReadChapters(widget.slug, source: widget.source).toSet();
      if (readSlugs.isNotEmpty) {
        for (int i = chronoChapters.length - 1; i >= 0; i--) {
          final c = chronoChapters[i];
          final cleanSlug = c.slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
          final hashSlug = SyncService.hashSlug(c.slug).toString();
          if (readSlugs.contains(c.slug) ||
              readSlugs.contains(cleanSlug) ||
              readSlugs.contains(c.chapter) ||
              readSlugs.contains(hashSlug)) {
            lastReadIndex = i;
            break;
          }
        }
      }
    }

    final savedPercent = (historyItem['percent'] as num?)?.toDouble() ?? 0.0;
    final savedTotalChapters = (historyItem['totalChapters'] as num?)?.toInt() ?? 0;

    if (lastReadIndex == -1 && savedPercent > 0) {
      // Pakai percent untuk estimasi posisi di chapter list baru.
      // Selalu pakai chronoChapters.length (source baru) bukan prevTotal (source lama)
      // agar tidak meleset setelah migrate ke source dengan jumlah chapter berbeda.
      if (savedPercent < 0.999) {
        lastReadIndex = (savedPercent * chronoChapters.length)
            .floor()
            .clamp(0, chronoChapters.length - 1);
      } else {
        // 100% = chapter terakhir
        lastReadIndex = chronoChapters.length - 1;
      }
    }

    // Jika chapter list di source sekarang lebih panjang dari yang tersimpan di history,
    // berarti ada chapter baru yang belum dibaca — paksa bukan completed.
    final bool hasNewChaptersSinceLastRead =
        savedTotalChapters > 0 && chronoChapters.length > savedTotalChapters;

    final bool isLastChapter =
        (lastReadIndex >= 0 && lastReadIndex == chronoChapters.length - 1);
    final page = (historyItem['page'] as num?)?.toInt() ?? 1;
    final totalPages = (historyItem['totalPages'] as num?)?.toInt() ?? 1;
    final bool isCompleted = !hasNewChaptersSinceLastRead &&
        isLastChapter && (savedPercent >= 0.999 || totalPages <= 1 || page >= totalPages);

    double progressPercent = 0.0;
    if (lastReadIndex >= 0) {
      final pageFrac = (totalPages > 0)
          ? (page / totalPages).clamp(0.0, 1.0)
          : 0.0;
      if (isCompleted) {
        progressPercent = 1.0;
      } else {
        final raw = ((lastReadIndex + pageFrac) / chronoChapters.length);
        final remaining = chronoChapters.length - (lastReadIndex + 1);
        if (remaining >= 2) {
          progressPercent = raw.clamp(0.0, remaining >= 3 ? 0.97 : 0.98);
        } else {
          progressPercent = raw.clamp(0.0, 0.99);
        }
      }
    }

    final bool totalChaptersChanged =
        chronoChapters.length !=
        (historyItem['totalChapters'] as num?)?.toInt();
    final bool percentChanged = (savedPercent - progressPercent).abs() > 0.005;
    final matchedChapter = lastReadIndex >= 0
        ? chronoChapters[lastReadIndex]
        : null;
    final bool shouldHealHash =
        isHash && matchedChapter != null && matchedChapter.slug.isNotEmpty;

    if (totalChaptersChanged || percentChanged || shouldHealHash) {
      LocalStorage.updateHistoryMetadata(
        slug: widget.slug,
        source: widget.source,
        title: _details?.title ?? historyItem['title'] ?? widget.title,
        cover: _details?.cover ?? historyItem['cover'] ?? widget.cover,
        chapterSlug: shouldHealHash ? matchedChapter.slug : null,
        chapterTitle: shouldHealHash ? matchedChapter.title : null,
        chapterNumber:
            matchedChapter?.chapterNumber?.toInt() ??
            (lastReadIndex >= 0 ? lastReadIndex + 1 : null),
        percent: progressPercent,
        totalChapters: chronoChapters.length,
      );
    }

    if (isCompleted || lastReadIndex >= 0) {
      // Kumpulkan slug chapter yang masih unread di feed — chapter ini TIDAK boleh
      // dimasukkan ke toMarkRead agar status "belum dibaca" di umpan tetap terjaga.
      final feedUnreadSlugs = <String>{};
      final feedItems = LocalStorage.getFeedItems();
      for (final item in feedItems) {
        if (item.mangaSlug == widget.slug &&
            (widget.source.isEmpty || item.mangaSource == widget.source)) {
          if (LocalStorage.isFeedItemUnread(item)) {
            feedUnreadSlugs.addAll(item.newChapterSlugs);
            feedUnreadSlugs.addAll(item.newChapters);
          }
        }
      }

      final toMarkRead = <String>[];
      final endIdx = isCompleted ? chronoChapters.length : lastReadIndex + 1;
      for (int i = 0; i < endIdx; i++) {
        final c = chronoChapters[i];
        // Jangan tandai terbaca jika chapter ini masih ada di feed sebagai unread
        final isUnreadInFeed =
            feedUnreadSlugs.contains(c.slug) ||
            feedUnreadSlugs.contains(c.chapter) ||
            feedUnreadSlugs.contains(
              c.slug.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
            ) ||
            (c.slug.isNotEmpty &&
                feedUnreadSlugs.contains(
                  SyncService.hashSlug(c.slug).toString(),
                )) ||
            (c.chapter.isNotEmpty &&
                feedUnreadSlugs.contains(
                  SyncService.hashSlug(c.chapter).toString(),
                ));
        if (isUnreadInFeed) continue;
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
      if (!isCompleted && lastReadIndex >= 0) {
        for (int i = lastReadIndex + 1; i < chronoChapters.length; i++) {
          final c = chronoChapters[i];
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

      // Bersihkan juga slug dari feed items manga ini yang masih aktif/unread
      for (final item in feedItems) {
        if (item.mangaSlug == widget.slug &&
            (widget.source.isEmpty || item.mangaSource == widget.source) &&
            item.isNew) {
          toMarkUnread.addAll(item.newChapterSlugs);
          toMarkUnread.addAll(item.newChapters);
        }
      }

      if (toMarkRead.isNotEmpty || toMarkUnread.isNotEmpty) {
        LocalStorage.setReadChaptersUpTo(
          mangaSlug: widget.slug,
          readSlugs: toMarkRead,
          unreadSlugs: toMarkUnread,
          source: widget.source,
        );
      }

      if (isCompleted) {
        LocalStorage.saveTrackBaseline(
          widget.slug,
          lastChapterSlug: chronoChapters.last.slug,
          totalChapters: chronoChapters.length,
        );
      }
    }
  }

  String? _getEstimatedReadingTime(int chaptersCount) {
    if (!LocalStorage.isReadingTimeEstimationEnabled()) return null;
    if (chaptersCount <= 0) return null;

    // Persis seperti Kotatsu Redo (ReadingTimeUseCase):
    // 20 halaman per bab * detik per halaman
    final secPerPage = LocalStorage.getAverageSecondsPerPage();
    final totalSeconds = (chaptersCount * 20 * secPerPage).round();
    if (totalSeconds < 60) return null;

    final minutes = (totalSeconds / 60).round();
    final hours = minutes ~/ 60;
    final remMinutes = minutes % 60;

    if (hours > 0) {
      return remMinutes > 0 ? '~${hours}j ${remMinutes}m' : '~$hours jam';
    }
    return '~$minutes mnt';
  }

  void _showFavoriteCategoriesDialog(MangaDetails details) {
    final theme = Theme.of(context);
    final customCategories = LocalStorage.getFavoriteCategories();
    final isFav = LocalStorage.isFavorite(widget.slug, source: widget.source);
    final initialCats = LocalStorage.getFavoriteCategoriesForSlug(
      widget.slug,
      source: widget.source,
    );
    final selectedCats = Set<String>.from(
      initialCats.where((c) => c != 'Semua kesukaan' && c != 'Semua'),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return Dialog(
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Cover + Title
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 44,
                            height: 60,
                            child: CachedCover(
                              imageUrl: details.cover ?? widget.cover,
                              source: widget.source,
                              slug: widget.slug,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            details.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Custom categories list with checkboxes
                    if (customCategories.isNotEmpty)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.of(builderContext).size.height * 0.42,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: customCategories.map((cat) {
                              final isChecked = selectedCats.contains(cat);
                              final meta = LocalStorage.getCategoryDetails(cat);
                              final checkNewChapters =
                                  meta['checkNewChapters'] as bool? ?? true;

                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setDialogState(() {
                                    if (isChecked) {
                                      selectedCats.remove(cat);
                                    } else {
                                      selectedCats.add(cat);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Checkbox(
                                          value: isChecked,
                                          activeColor:
                                              theme.colorScheme.primary,
                                          checkColor:
                                              theme.colorScheme.onPrimary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          side: BorderSide(
                                            color: isChecked
                                                ? theme.colorScheme.primary
                                                : theme
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                      .withValues(alpha: 0.7),
                                            width: 2,
                                          ),
                                          onChanged: (val) {
                                            setDialogState(() {
                                              if (val == true) {
                                                selectedCats.add(cat);
                                              } else {
                                                selectedCats.remove(cat);
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                cat,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                            if (checkNewChapters) ...[
                                              const SizedBox(width: 6),
                                              Icon(
                                                Icons
                                                    .notifications_none_rounded,
                                                size: 15,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.8),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_open_outlined,
                              size: 40,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Belum ada kategori kesukaan',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Buat kategori terlebih dahulu untuk menyimpan komik ke favorit.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () async {
                                Navigator.pop(dialogContext);
                                await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const CategoryEditScreen(),
                                  ),
                                );
                                if (mounted) {
                                  setState(() {});
                                  _showFavoriteCategoriesDialog(details);
                                }
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Buat Kategori'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Bottom Action Row: Kelola (left) & Selesai (right)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(dialogContext);
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ManageCategoriesScreen(),
                              ),
                            );
                            if (mounted) {
                              setState(() {});
                              _showFavoriteCategoriesDialog(details);
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text('Kelola'),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(dialogContext);

                            final catsList = selectedCats
                                .where(
                                  (c) => c != 'Semua kesukaan' && c != 'Semua',
                                )
                                .toList();

                            if (catsList.isEmpty) {
                              if (isFav) {
                                await LocalStorage.removeFavorite(
                                  widget.slug,
                                  source: widget.source,
                                );
                                unawaited(
                                  FeedUpdateNotifier.syncTrackedMangaConfig(),
                                );
                                if (mounted) {
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Dihapus dari favorit: ${details.title}',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                      margin: const EdgeInsets.only(
                                        left: 16,
                                        right: 16,
                                        bottom: 16,
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        customCategories.isEmpty
                                            ? 'Belum ada kategori. Buat kategori terlebih dahulu melalui tombol Kelola.'
                                            : 'Pilih minimal satu kategori untuk menambahkan ke favorit.',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                      margin: const EdgeInsets.only(
                                        left: 16,
                                        right: 16,
                                        bottom: 16,
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            } else {
                              await LocalStorage.saveFavorite(
                                slug: widget.slug,
                                title: details.title,
                                cover: details.cover ?? widget.cover,
                                source: widget.source,
                                categories: catsList,
                                type: details.type,
                                latestChapter: details.chapters.isNotEmpty
                                    ? details.chapters.first.chapter
                                    : null,
                              );
                              unawaited(
                                FeedUpdateNotifier.syncTrackedMangaConfig(),
                              );
                              if (mounted) {
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Disimpan ke ${catsList.join(", ")}',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    margin: const EdgeInsets.only(
                                      left: 16,
                                      right: 16,
                                      bottom: 16,
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text('Selesai'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Chapter> _getChronologicalChapters() {
    if (_details == null || _details!.chapters.isEmpty) return [];
    return Chapter.sortChronological(_details!.chapters);
  }

  String _getMangaWebUrl(String source, String slug, {MangaDetails? details}) {
    final cleanSlug = slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    switch (source.toLowerCase()) {
      case 'shinigami':
        final effectiveId = (details?.id ?? _details?.id ?? widget.id ?? '')
            .trim();
        if (effectiveId.isNotEmpty && uuidRegex.hasMatch(effectiveId)) {
          return 'https://s1.shinigami.mx/series/$effectiveId';
        }
        if (uuidRegex.hasMatch(cleanSlug)) {
          return 'https://s1.shinigami.mx/series/$cleanSlug';
        }
        if (effectiveId.isNotEmpty) {
          return 'https://s1.shinigami.mx/series/$effectiveId';
        }
        return 'https://s1.shinigami.mx/series/$cleanSlug';
      case 'softkomik':
        return 'https://softkomik.app/$cleanSlug';
      case 'kiryuu':
        return 'https://v7.kiryuu.to/manga/$cleanSlug/';
      case 'komiku':
        return 'https://komiku.org/manga/$cleanSlug/';
      case 'hwago':
        return 'https://01.hwago.com/comic/$cleanSlug';
      case 'doujindesu':
        return 'https://doujin.desu.xxx/manga/$cleanSlug';
      case 'komiktap':
        return 'https://komiktap.info/manga/$cleanSlug/';
      case 'westmanga':
        return 'https://v1.westmanga.my/comic/$cleanSlug';
      case 'komikindo':
        return 'https://komikindo.click/manga/$cleanSlug/';
      case 'apkomik':
        return 'https://01.apkomik.com/manga/$cleanSlug/';
      case 'bacakomik':
        return 'https://bacakomik.my/komik/$cleanSlug/';
      case 'lumos':
        return 'https://03.lumosgg.com/comic/$cleanSlug';
      case 'holotoon':
        return 'https://holodek.run/comic/$cleanSlug';
      case 'pixhentai':
        return 'https://pixhentai.com/$cleanSlug/';
      case 'ikiru':
        return 'https://09.ikiru.wtf/manga/$cleanSlug';
      case 'hentaicrot':
        return 'https://hentaicrot.com/$cleanSlug/';
      case 'voratoon':
        return 'https://v10.voratoon.com/series/$cleanSlug';
      case 'luvyaa':
        return 'https://v5.luvyaa.co/$cleanSlug/';
      case 'crotpedia':
        return 'https://crotpedia.net/baca/series/$cleanSlug/';
      case 'mihentai':
        return 'https://mihentai.net/manga/$cleanSlug/';
      case 'ainz':
        return 'https://v3.ainzscans01.com/comic/$cleanSlug';
      case 'soulscans':
        return 'https://v1.soulscans.asia/comic/$cleanSlug';
      case 'komikstation':
        return 'https://komikstation.org/manga/$cleanSlug/';
      case 'komikindoch':
        return 'https://komikindo.ch/komik/$cleanSlug/';
      case 'sasangeyou':
        return 'https://sasangeyou.net/manga/$cleanSlug/';
      case 'kanzenin':
        return 'https://kanzenin.info/manga/$cleanSlug/';
      case 'mangasusuku':
      case 'mangsusuku':
        return 'https://mangasusuku.com/komik/$cleanSlug/';
      case 'izanamiscans':
        return 'https://izanamiscans.my.id/manga/$cleanSlug/';
      case 'cgbum':
        return 'https://cgbum.com/komik/$cleanSlug';
      case 'lepoytl':
        return 'https://www.lepoytl.my.id/$cleanSlug';
      case 'yurilab':
        return 'https://yurilab.top/series/$cleanSlug/';
      case 'maid':
        return 'https://www.maid.my.id/manga/$cleanSlug/';
      case 'natsu':
        return 'https://natsu.one/manga/$cleanSlug/';
      case 'komikremaja':
        return 'https://komikremaja.art/komik/$cleanSlug/';
      case 'shirodoujin':
        return 'https://shirodoujin.com/series/$cleanSlug/';
      case 'komikapk':
        return 'https://komikapk.app/komik/$cleanSlug';
      case 'mangapill':
        return 'https://mangapill.com/manga/$cleanSlug';
      case 'fanfox':
        return 'https://fanfox.net/manga/$cleanSlug/';
      default:
        return 'https://www.google.com/search?q=${Uri.encodeComponent('$slug $source')}';
    }
  }

  String _getEffectiveTitle() {
    if (_details?.title != null && _details!.title.trim().isNotEmpty) {
      return _details!.title.trim();
    }
    if (widget.title != null && widget.title!.trim().isNotEmpty) {
      return widget.title!.trim();
    }
    final fav = LocalStorage.getFavorite(widget.slug, source: widget.source);
    final favTitle = fav?['title']?.toString().trim();
    if (favTitle != null && favTitle.isNotEmpty) {
      return favTitle;
    }
    final hist = LocalStorage.getHistoryItem(
      widget.slug,
      source: widget.source,
    );
    final histTitle = hist?['title']?.toString().trim();
    if (histTitle != null && histTitle.isNotEmpty) {
      return histTitle;
    }
    final cleaned = widget.slug
        .replaceAll(RegExp(r'^/+|/+$'), '')
        .split('/')
        .last
        .replaceAll(RegExp(r'[-_]'), ' ')
        .trim();
    if (cleaned.isNotEmpty) {
      return cleaned
          .split(' ')
          .map(
            (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
          )
          .join(' ');
    }
    return 'Detail Komik';
  }

  String? _getEffectiveCover() {
    if (_details?.cover != null && _details!.cover!.trim().isNotEmpty) {
      return _details!.cover!.trim();
    }
    if (widget.cover != null && widget.cover!.trim().isNotEmpty) {
      return widget.cover!.trim();
    }
    final fav = LocalStorage.getFavorite(widget.slug, source: widget.source);
    final favCover = fav?['cover']?.toString().trim();
    if (favCover != null && favCover.isNotEmpty) {
      return favCover;
    }
    final hist = LocalStorage.getHistoryItem(
      widget.slug,
      source: widget.source,
    );
    final histCover = hist?['cover']?.toString().trim();
    if (histCover != null && histCover.isNotEmpty) {
      return histCover;
    }
    return null;
  }

  void _openAlternatives() {
    final sourcesAsync = ref.read(sourcesListProvider);
    final sourceInfo = sourcesAsync.whenOrNull(
      data: (sources) {
        try {
          return sources.firstWhere((s) => s.id == widget.source);
        } catch (_) {
          return null;
        }
      },
    );
    final sourceTitle =
        sourceInfo?.name ?? widget.sourceName ?? widget.source.toUpperCase();
    final effectiveTitle = _getEffectiveTitle();
    final effectiveCover = _getEffectiveCover();
    final totalCh = _details != null
        ? (_details!.totalChapters > 0
              ? _details!.totalChapters
              : _details!.chapters.length)
        : (LocalStorage.getHistoryItem(
                    widget.slug,
                    source: widget.source,
                  )?['totalChapters']
                  as num?)
              ?.toInt();

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    nav
        .push<MangaItem>(
          PredictiveBackPageRoute(
            builder: (_) => AlternativesScreen(
              source: widget.source,
              sourceName: sourceTitle,
              slug: widget.slug,
              title: effectiveTitle,
              cover: effectiveCover,
              totalChapters: totalCh,
            ),
          ),
        )
        .then((migratedManga) {
          if (migratedManga != null && mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Migrasi selesai'),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
                duration: Duration(seconds: 2),
              ),
            );
            nav.pushReplacement(
              PredictiveBackPageRoute(
                builder: (_) => MangaDetailsScreen(
                  slug: migratedManga.slug,
                  source: migratedManga.source ?? widget.source,
                  title: migratedManga.title,
                  cover: migratedManga.cover,
                  origin: widget.origin,
                ),
              ),
            );
          }
        });
  }

  Future<void> _pickCustomCover() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.image,
        dialogTitle: 'Pilih Sampul Manga dari Galeri',
      );
      if (file == null) return;
      final bytes = await file.xFile.readAsBytes();
      if (bytes.isEmpty) return;

      final appDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory('${appDir.path}/custom_covers');
      if (!coversDir.existsSync()) {
        coversDir.createSync(recursive: true);
      }
      final ext = file.extension ?? 'jpg';
      final cleanSlug = widget.slug.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final targetPath =
          '${coversDir.path}/${widget.source}_${cleanSlug}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final savedFile = File(targetPath);
      await savedFile.writeAsBytes(bytes);

      await LocalStorage.setCustomCover(
        widget.slug,
        targetPath,
        source: widget.source,
      );
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
          content: Text('Sampul komik kustom berhasil diterapkan'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          content: Text('Gagal mengganti sampul: $e'),
        ),
      );
    }
  }

  Future<void> _resetCustomCover() async {
    await LocalStorage.removeCustomCover(widget.slug, source: widget.source);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
        content: Text('Sampul dikembalikan ke sampul bawaan situs sumber'),
      ),
    );
  }

  void _viewFullCover() {
    final effectiveCover = _getEffectiveCover();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedCover(
                  imageUrl: effectiveCover,
                  source: widget.source,
                  slug: widget.slug,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 28,
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _showCoverActionsSheet() {
    final hasCustom = LocalStorage.hasCustomCover(
      widget.slug,
      source: widget.source,
    );
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Pengaturan Sampul Komik',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Ganti Sampul dari Galeri'),
                subtitle: const Text(
                  'Pilih gambar kustom dari penyimpanan HP Anda',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickCustomCover();
                },
              ),
              if (hasCustom)
                ListTile(
                  leading: const Icon(
                    Icons.restore_rounded,
                    color: Colors.orange,
                  ),
                  title: const Text(
                    'Kembalikan ke Sampul Asli',
                    style: TextStyle(color: Colors.orange),
                  ),
                  subtitle: const Text(
                    'Hapus sampul kustom dan gunakan gambar dari sumber',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _resetCustomCover();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.fullscreen_rounded),
                title: const Text('Lihat Sampul Penuh'),
                subtitle: const Text(
                  'Tampilkan resolusi penuh dan perbesar gambar',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _viewFullCover();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReader(
    Chapter chapter, {
    int initialPage = 0,
    double initialPageOffset = 0,
    double initialScrollOffset = 0,
    Map<int, double>? initialPageHeights,
    double? initialPageOffsetRatio,
    bool startAtEnd = false,
  }) {
    if (_details == null) return;
    final chronoChapters = _getChronologicalChapters();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaReaderScreen(
          mangaTitle: _details!.title,
          mangaSlug: widget.slug,
          source: widget.source,
          cover: _details!.cover ?? widget.cover,
          chapters: chronoChapters,
          initialChapter: chapter,
          initialPage: initialPage,
          initialPageOffset: initialPageOffset,
          initialScrollOffset: initialScrollOffset,
          initialPageHeights: initialPageHeights,
          initialPageOffsetRatio: initialPageOffsetRatio,
          startAtEnd: startAtEnd,
          origin: 'details',
          detailsOrigin: widget.origin,
          sourceName: widget.sourceName,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  bool _isChapterMatch(Chapter c, Map<String, dynamic> historyItem) {
    final rawSlug = historyItem['chapterSlug']?.toString().trim() ?? '';
    final isHashSlug = rawSlug.length >= 8 && int.tryParse(rawSlug) != null;
    final cleanLast = rawSlug.replaceAll(RegExp(r'^/+|/+$'), '');
    final cleanCSlug = c.slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final cleanCChapter = c.chapter.trim().replaceAll(RegExp(r'^/+|/+$'), '');

    if (rawSlug.isNotEmpty) {
      if (c.slug == rawSlug ||
          c.chapter == rawSlug ||
          cleanCSlug == cleanLast ||
          cleanCChapter == cleanLast) {
        return true;
      }
      if (isHashSlug) {
        if (SyncService.hashSlug(c.slug).toString() == cleanLast ||
            SyncService.hashSlug(c.chapter).toString() == cleanLast) {
          return true;
        }
      }
    }

    final titleMatch = RegExp(
      r'(?:Chapter|Bab|Ch\.?|Episode|Ep\.?)\s*([0-9.]+)',
      caseSensitive: false,
    ).firstMatch(historyItem['chapterTitle']?.toString() ?? '');
    final extractedNum = titleMatch?.group(1);
    if (extractedNum != null && extractedNum.isNotEmpty) {
      if (cleanCSlug == extractedNum ||
          cleanCChapter == extractedNum ||
          cleanCSlug.endsWith('/$extractedNum') ||
          cleanCChapter.endsWith('/$extractedNum')) {
        return true;
      }
    }

    if (historyItem['chapterTitle'] != null) {
      final chTitle = historyItem['chapterTitle']
          .toString()
          .trim()
          .toLowerCase();
      if (chTitle.isNotEmpty && c.title.trim().toLowerCase() == chTitle) {
        return true;
      }
    }

    if (historyItem['chapterNumber'] != null && c.chapterNumber != null) {
      if ((c.chapterNumber! - (historyItem['chapterNumber'] as num).toDouble()).abs() < 0.01) {
        return true;
      }
    }

    final histTitle = historyItem['chapterTitle']?.toString().trim() ?? '';
    final histNumMatch = RegExp(r'(?:Chapter|Bab|Ch\.?|Episode|Ep\.?)\s*([0-9.]+)', caseSensitive: false).firstMatch(histTitle) ??
        RegExp(r'([0-9.]+)').firstMatch(histTitle);
    final cNumMatch = RegExp(r'(?:Chapter|Bab|Ch\.?|Episode|Ep\.?)\s*([0-9.]+)', caseSensitive: false).firstMatch(c.title) ??
        RegExp(r'([0-9.]+)').firstMatch(c.title) ??
        RegExp(r'([0-9.]+)').firstMatch(c.chapter);
    final histNum = (historyItem['chapterNumber'] as num?)?.toDouble() ?? double.tryParse(histNumMatch?.group(1) ?? '');
    final cNum = c.chapterNumber ?? double.tryParse(cNumMatch?.group(1) ?? '');
    if (histNum != null && cNum != null && (histNum - cNum).abs() < 0.01) {
      return true;
    }

    return false;
  }

  Chapter _findLastReadChapter(
    List<Chapter> chronoChapters,
    Map<String, dynamic> historyItem,
  ) {
    for (final c in chronoChapters) {
      if (_isChapterMatch(c, historyItem)) return c;
    }
    final prevTotal = (historyItem['totalChapters'] as num?)?.toInt();
    final pct = (historyItem['percent'] as num?)?.toDouble() ?? 0.0;
    if (prevTotal != null && prevTotal > 0) {
      final estIdx = (pct * prevTotal).floor();
      final clampedIdx = estIdx.clamp(0, chronoChapters.length - 1);
      if (clampedIdx >= 0 && clampedIdx < chronoChapters.length) {
        return chronoChapters[clampedIdx];
      }
    }
    if (pct > 0 && pct < 0.999) {
      final idx = (pct * chronoChapters.length).floor().clamp(
        0,
        chronoChapters.length - 1,
      );
      return chronoChapters[idx];
    }
    // Jika persentase 1.0 tapi bab tidak cocok dan ada bab baru, jangan langsung ke chronoChapters.last
    if (pct >= 0.999 &&
        prevTotal != null &&
        prevTotal > 0 &&
        prevTotal < chronoChapters.length) {
      return chronoChapters[prevTotal - 1];
    }
    if (pct >= 0.999 &&
        (prevTotal == null || prevTotal == chronoChapters.length)) {
      return chronoChapters.last;
    }
    return chronoChapters.first;
  }

  void _openChapterWithHistory(Chapter ch) {
    final historyItem = LocalStorage.getHistoryItem(
      widget.slug,
      source: widget.source,
    );
    if (historyItem != null && _isChapterMatch(ch, historyItem)) {
      final savedPage = (historyItem['page'] as num?)?.toInt() ?? 0;
      final savedOffset = (historyItem['pageOffset'] as num?)?.toDouble() ?? 0;
      final savedScroll =
          (historyItem['scrollOffset'] as num?)?.toDouble() ?? 0;
      final rawHeights = historyItem['pageHeights'];
      Map<int, double>? savedHeights;
      if (rawHeights is Map) {
        savedHeights = {};
        rawHeights.forEach((k, v) {
          final idx = int.tryParse(k.toString());
          final h = (v as num?)?.toDouble();
          if (idx != null && h != null) savedHeights![idx] = h;
        });
      }
      final savedRatio = (historyItem['pageOffsetRatio'] as num?)?.toDouble();
      final savedPercent = (historyItem['percent'] as num?)?.toDouble() ?? 0.0;
      final totalPages = (historyItem['totalPages'] as num?)?.toInt() ?? 0;
      final isChapterFinished = totalPages > 0 && savedPage >= totalPages;
      final chronoChapters = _getChronologicalChapters();
      final targetIdx = chronoChapters.indexOf(ch);
      final isLastChapter =
          targetIdx >= 0 && targetIdx == chronoChapters.length - 1;
      final isCompleted =
          (savedPercent >= 0.999 || isChapterFinished) && isLastChapter;

      _openReader(
        ch,
        initialPage: savedPage,
        initialPageOffset: savedOffset,
        initialScrollOffset: savedScroll,
        initialPageHeights: savedHeights,
        initialPageOffsetRatio: savedRatio,
        startAtEnd: isCompleted,
      );
    } else {
      _openReader(ch);
    }
  }

  void _resumeOrStartReading() {
    if (_details == null || _details!.chapters.isEmpty) return;

    final chronoChapters = _getChronologicalChapters();
    if (chronoChapters.isEmpty) return;

    final historyItem = LocalStorage.getHistoryItem(
      widget.slug,
      source: widget.source,
    );
    final readChapterSlugs = LocalStorage.getReadChapters(
      widget.slug,
      source: widget.source,
    ).toSet();

    if (historyItem != null) {
      final matchedChapter = chronoChapters.where((c) => _isChapterMatch(c, historyItem)).firstOrNull;
      final savedPage = (historyItem['page'] as num?)?.toInt() ?? 0;
      final totalPages = (historyItem['totalPages'] as num?)?.toInt() ?? 0;
      final savedPercent = (historyItem['percent'] as num?)?.toDouble() ?? 0.0;
      final histOffsetRatio = (historyItem['pageOffsetRatio'] as num?)?.toDouble() ?? 0.0;
      final isCurrentChapterFinished = (totalPages > 0 && savedPage >= totalPages) ||
          savedPercent >= 0.999 ||
          (histOffsetRatio >= 0.95 && (totalPages <= 1 || savedPage >= totalPages));

      Chapter? targetChapter;
      bool openAtStart = false;

      if (matchedChapter != null) {
        final matchedIdx = chronoChapters.indexOf(matchedChapter);
        if (!isCurrentChapterFinished) {
          // Masih sedang membaca matchedChapter, lanjutkan di posisi halaman terakhir
          targetChapter = matchedChapter;
          openAtStart = false;
        } else {
          // matchedChapter sudah selesai! Cari bab berikutnya yang BELUM DIBACA
          int nextUnreadIdx = -1;
          for (int i = matchedIdx + 1; i < chronoChapters.length; i++) {
            final c = chronoChapters[i];
            final cleanSlug = c.slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
            final hash = SyncService.hashSlug(c.slug).toString();
            final isRead = readChapterSlugs.contains(c.slug) ||
                readChapterSlugs.contains(cleanSlug) ||
                readChapterSlugs.contains(c.chapter) ||
                readChapterSlugs.contains(hash);
            if (!isRead) {
              nextUnreadIdx = i;
              break;
            }
          }

          if (nextUnreadIdx != -1) {
            targetChapter = chronoChapters[nextUnreadIdx];
            openAtStart = true;
          } else {
            // Seluruh bab dari matchedChapter ke atas sudah dibaca, buka bab paling akhir
            targetChapter = chronoChapters.last;
            openAtStart = false;
          }
        }
      } else {
        // historyItem ada tapi slug bab tidak cocok persis (misal migrasi atau perbedaan source)
        // Cari bab pertama yang BELUM DIBACA
        int firstUnreadIdx = -1;
        for (int i = 0; i < chronoChapters.length; i++) {
          final c = chronoChapters[i];
          final cleanSlug = c.slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
          final hash = SyncService.hashSlug(c.slug).toString();
          final isRead = readChapterSlugs.contains(c.slug) ||
              readChapterSlugs.contains(cleanSlug) ||
              readChapterSlugs.contains(c.chapter) ||
              readChapterSlugs.contains(hash);
          if (!isRead) {
            firstUnreadIdx = i;
            break;
          }
        }

        if (firstUnreadIdx != -1) {
          targetChapter = chronoChapters[firstUnreadIdx];
          openAtStart = true;
        } else {
          targetChapter = _findLastReadChapter(chronoChapters, historyItem);
          openAtStart = false;
        }
      }

      if (openAtStart) {
        // Bab baru / belum pernah dibaca: selalu buka dari halaman 1 (paling awal)
        _openReader(targetChapter, initialPage: 0, startAtEnd: false);
        return;
      }

      final savedOffset = (historyItem['pageOffset'] as num?)?.toDouble() ?? 0;
      final savedScroll = (historyItem['scrollOffset'] as num?)?.toDouble() ?? 0;
      final rawHeights = historyItem['pageHeights'];
      Map<int, double>? savedHeights;
      if (rawHeights is Map) {
        savedHeights = {};
        rawHeights.forEach((k, v) {
          final idx = int.tryParse(k.toString());
          final h = (v as num?)?.toDouble();
          if (idx != null && h != null) savedHeights![idx] = h;
        });
      }
      final savedRatio = (historyItem['pageOffsetRatio'] as num?)?.toDouble();
      final targetIdx = chronoChapters.indexOf(targetChapter);
      final isLastChapter = targetIdx >= 0 && targetIdx == chronoChapters.length - 1;
      final isCompleted = (savedPercent >= 0.999 || isCurrentChapterFinished) && isLastChapter;

      _openReader(
        targetChapter,
        initialPage: savedPage,
        initialPageOffset: savedOffset,
        initialScrollOffset: savedScroll,
        initialPageHeights: savedHeights,
        initialPageOffsetRatio: savedRatio,
        startAtEnd: isCompleted,
      );
    } else {
      // Belum ada riwayat baca: selalu dari bab paling awal kronologis
      final firstChapter = chronoChapters.first;
      _openReader(firstChapter, initialPage: 0, startAtEnd: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final historyItem = LocalStorage.getHistoryItem(
      widget.slug,
      source: widget.source,
    );
    final readChapterSlugs = historyItem != null
        ? LocalStorage.getReadChapters(
            widget.slug,
            source: widget.source,
          ).toSet()
        : <String>{};

    if (_isLoading) {
      return PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
        },
        child: MangaDetailsShimmer(title: widget.title, cover: widget.cover),
      );
    }

    if (_error != null || _details == null) {
      final sourceInfo = ref
          .read(sourcesListProvider)
          .whenOrNull(
            data: (sources) {
              try {
                return sources.firstWhere((s) => s.id == widget.source);
              } catch (_) {
                return null;
              }
            },
          );
      final sourceTitle =
          sourceInfo?.name ?? widget.sourceName ?? widget.source.toUpperCase();
      final title = _getEffectiveTitle();
      final cover = _getEffectiveCover();

      return PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
        },
        child: ScaffoldMessenger(
          child: Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    sourceTitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.swap_horiz_rounded),
                  tooltip: 'Cari Alternatif di Sumber Lain',
                  onPressed: _openAlternatives,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (val) {
                    if (val == 'alternatives') {
                      _openAlternatives();
                    } else if (val == 'open_web') {
                      final webUrl = _getMangaWebUrl(
                        widget.source,
                        widget.slug,
                        details: _details,
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              InAppBrowserScreen(url: webUrl, title: title),
                        ),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'alternatives',
                      child: Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 20),
                          SizedBox(width: 12),
                          Text('Cari Alternatif Sumber'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'open_web',
                      child: Row(
                        children: [
                          Icon(Icons.open_in_browser_rounded, size: 20),
                          SizedBox(width: 12),
                          Text('Buka di Web'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cover != null && cover.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 90,
                          height: 126,
                          child: CachedCover(
                            imageUrl: cover,
                            source: widget.source,
                            slug: widget.slug,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Builder(
                      builder: (context) {
                        final isCf =
                            _error != null &&
                            (_error!.contains('CLOUDFLARE') ||
                                _error!.contains('403') ||
                                _error!.contains('cf-mitigated') ||
                                _error!.contains('challenge'));
                        final cfUrl = widget.slug.startsWith('http')
                            ? widget.slug
                            : '${MangaSource.getBaseUrlForSource(widget.source)}/${widget.slug.replaceFirst(RegExp(r"^/"), "")}';

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isCf
                                  ? Icons.shield_rounded
                                  : Icons.error_outline_rounded,
                              size: 56,
                              color: isCf
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isCf
                                  ? 'Verifikasi Cloudflare'
                                  : 'Terjadi Kesalahan',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              friendlyError(
                                _error ?? 'Gagal memuat detail komik',
                              ),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (isCf) ...[
                              FilledButton.icon(
                                onPressed: () async {
                                  final ok = await CloudflareSolverScreen.open(
                                    context,
                                    url: cfUrl,
                                    sourceName: sourceTitle,
                                  );
                                  if (ok) {
                                    _fetchDetails();
                                  }
                                },
                                icon: const Icon(Icons.verified_user_rounded),
                                label: const Text('Buka Verifikasi Web'),
                              ),
                              const SizedBox(height: 12),
                            ],
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.lightbulb_outline_rounded,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Sumber $sourceTitle sedang bermasalah atau memblokir akses. Pindahkan komik ini ke sumber lain agar bisa terus membaca tanpa kehilangan riwayat & favorit.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(height: 1.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton.icon(
                                  onPressed: _openAlternatives,
                                  icon: const Icon(Icons.swap_horiz_rounded),
                                  label: const Text('Cari Alternatif'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _fetchDetails,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Coba Lagi'),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final details = _details!;
    final isFav = LocalStorage.isFavorite(widget.slug, source: widget.source);
    final favCategories = LocalStorage.getFavoriteCategoriesForSlug(
      widget.slug,
      source: widget.source,
    );
    final String favLabel;
    if (!isFav) {
      favLabel = 'Tambah ke favorit';
    } else if (favCategories.isEmpty) {
      favLabel = 'Favorit';
    } else if (favCategories.length == 1) {
      favLabel = favCategories.first;
    } else {
      final firstCat = favCategories.first;
      final extraCount = favCategories.length - 1;
      final shortFirst = firstCat.length > 10
          ? '${firstCat.substring(0, 9)}…'
          : firstCat;
      favLabel = '$shortFirst (+$extraCount)';
    }
    final coverUrl = details.cover ?? widget.cover;

    // Filter and sort chapters
    // Selalu mulai dari urutan kronologis descending (terbaru di atas = default)
    // agar toggle sort konsisten di semua source.
    _ensureCachedData(historyItem, readChapterSlugs);
    final chronoAsc = _cachedChronoChapters ?? [];
    var displayChapters = _isSortAscending ? chronoAsc : chronoAsc.reversed.toList();
    if (_chapterSearchQuery.isNotEmpty) {
      final q = _chapterSearchQuery.toLowerCase();
      displayChapters = displayChapters
          .where(
            (c) =>
                c.title.toLowerCase().contains(q) ||
                c.chapter.toLowerCase().contains(q),
          )
          .toList();
    }

    final lastReadChronoIndex = _cachedLastReadChronoIndex;
    final hasNewerChapters = _cachedHasNewerChapters;
    final isCompleted = _cachedIsCompleted;

    return ScaffoldMessenger(
      child: Scaffold(
        body: Stack(
          children: [
            // 1. Kotatsu Poster Background (extends down across the metadata card with seamless fade)
            if (coverUrl != null && coverUrl.trim().isNotEmpty)
              AnimatedBuilder(
                animation: _scrollController,
                builder: (context, _) {
                  final scrollY = _scrollController.hasClients
                      ? _scrollController.offset
                      : 0.0;
                  if (scrollY > 470) return const SizedBox.shrink();
                  final fade = (1.0 - (scrollY / 400.0)).clamp(0.0, 1.0);

                  return Opacity(
                    opacity: fade,
                    child: Transform.translate(
                      offset: Offset(0, -scrollY),
                      child: SizedBox(
                        height: 450,
                        width: double.infinity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Soft blurred poster cover image (stops at 375px, blending cleanly at card bottom)
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 375,
                              child: Opacity(
                                opacity: 0.38,
                                child: RepaintBoundary(
                                  child: ImageFiltered(
                                    imageFilter: ImageFilter.blur(
                                      sigmaX: 8,
                                      sigmaY: 8,
                                    ),
                                    child: Transform.scale(
                                      scale: 1.10,
                                      child: CachedCover(
                                        imageUrl: coverUrl,
                                        source: widget.source,
                                        slug: widget.slug,
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Multi-stop gradient overlay: reaches solid background at 0.84, then fades to 0 alpha
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    theme.scaffoldBackgroundColor,
                                    theme.scaffoldBackgroundColor.withValues(
                                      alpha: 0.3,
                                    ),
                                    Colors.transparent,
                                    theme.scaffoldBackgroundColor.withValues(
                                      alpha: 0.65,
                                    ),
                                    theme.scaffoldBackgroundColor,
                                    theme.scaffoldBackgroundColor.withValues(
                                      alpha: 0.0,
                                    ),
                                  ],
                                  stops: const [
                                    0.0,
                                    0.10,
                                    0.38,
                                    0.70,
                                    0.84,
                                    1.0,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

            // 2. Foreground Structure: Fixed TopBar + ScrollView strictly clipped below TopBar (Kotatsu layout)
            Column(
              children: [
                // Kotatsu Sticky TopAppBar
                AppBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  systemOverlayStyle: const SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness: Brightness.light,
                    statusBarBrightness: Brightness.dark,
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.white,
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: ValueListenableBuilder<double>(
                    valueListenable: _titleOpacity,
                    builder: (context, opacity, child) {
                      return Opacity(opacity: opacity, child: child);
                    },
                    child: Text(
                      details.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.share_outlined),
                      color: Colors.white,
                      tooltip: 'Bagikan',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: details.title));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Judul "${details.title}" disalin ke papan klip',
                            ),
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: 16,
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      tooltip: 'Lainnya',
                      offset: const Offset(0, 40),
                      constraints: const BoxConstraints(
                        minWidth: 180,
                        maxWidth: 220,
                      ),
                      onSelected: (val) {
                        if (val == 'alternatives') {
                          _openAlternatives();
                        } else if (val == 'open_web') {
                          final webUrl = _getMangaWebUrl(
                            widget.source,
                            widget.slug,
                            details: details,
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InAppBrowserScreen(
                                url: webUrl,
                                title: details.title,
                              ),
                            ),
                          );
                        } else if (val == 'search') {
                          Navigator.push(
                            context,
                            PredictiveBackPageRoute(
                              builder: (_) =>
                                  SearchScreen(initialQuery: details.title),
                            ),
                          );
                        } else if (val == 'transfer_mode') {
                          showTransferMangaDialog(
                            context,
                            slug: widget.slug,
                            title: details.title,
                          ).then((transferred) {
                            if (transferred == true && mounted) {
                              setState(() {});
                            }
                          });
                        } else if (val == 'change_cover') {
                          _pickCustomCover();
                        } else if (val == 'reset_cover') {
                          _resetCustomCover();
                        } else if (val == 'copy') {
                          Clipboard.setData(ClipboardData(text: details.title));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Judul disalin ke papan klip'),
                              behavior: SnackBarBehavior.floating,
                              margin: EdgeInsets.only(
                                left: 16,
                                right: 16,
                                bottom: 16,
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'alternatives',
                          height: 40,
                          child: Row(
                            children: [
                              Icon(Icons.swap_horiz_rounded, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Alternatif',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'transfer_mode',
                          height: 40,
                          child: Row(
                            children: [
                              Icon(Icons.drive_file_move_outlined, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Pindah mode konten',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'open_web',
                          height: 40,
                          child: Row(
                            children: [
                              Icon(Icons.public_rounded, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Buka di peramban web',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'search',
                          height: 40,
                          child: Row(
                            children: [
                              Icon(Icons.search, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Cari Judul Serupa',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'copy',
                          height: 40,
                          child: Row(
                            children: [
                              Icon(Icons.copy, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Salin Judul',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'change_cover',
                          height: 40,
                          child: Row(
                            children: [
                              Icon(Icons.photo_library_outlined, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Ganti Sampul Komik',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        if (LocalStorage.hasCustomCover(
                          widget.slug,
                          source: widget.source,
                        ))
                          const PopupMenuItem(
                            value: 'reset_cover',
                            height: 40,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.restore_rounded,
                                  size: 18,
                                  color: Colors.orange,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Reset ke Sampul Asli',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Scrollable content strictly clipped below the TopAppBar!
                Expanded(
                  child: ClipRect(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: RefreshIndicator(
                        onRefresh: _fetchDetails,
                        child: CustomScrollView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            // Header Content
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Cover + Title Header
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Cover Portrait (13:18)
                                        GestureDetector(
                                          onTap: _showCoverActionsSheet,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      AppTheme.cardRadius,
                                                    ),
                                                child: SizedBox(
                                                  width: 115,
                                                  height: 160,
                                                  child:
                                                      (coverUrl != null &&
                                                          coverUrl
                                                              .trim()
                                                              .isNotEmpty)
                                                      ? CachedCover(
                                                          imageUrl: coverUrl,
                                                          source: widget.source,
                                                          slug: widget.slug,
                                                          fit: BoxFit.cover,
                                                          placeholder: (
                                                            context,
                                                            url,
                                                          ) => const MangaCardCoverShimmer(),
                                                          errorWidget:
                                                              (
                                                                context,
                                                                url,
                                                                error,
                                                              ) => Container(
                                                                color: theme
                                                                    .colorScheme
                                                                    .surfaceContainerHigh,
                                                                child: const Icon(
                                                                  Icons
                                                                      .broken_image,
                                                                  size: 40,
                                                                ),
                                                              ),
                                                        )
                                                      : Container(
                                                          color: theme
                                                              .colorScheme
                                                              .surfaceContainerHigh,
                                                          child: const Icon(
                                                            Icons.menu_book,
                                                            size: 40,
                                                          ),
                                                        ),
                                                ),
                                              ),
                                              Positioned(
                                                right: 6,
                                                bottom: 6,
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.65,
                                                        ),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.edit_rounded,
                                                    size: 13,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),

                                        // Titles & Favorite Chip
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                details.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      height: 1.2,
                                                    ),
                                              ),
                                              const SizedBox(height: 22),

                                              // Favorite Button (Kotatsu Redo style: [ Category ▼ ])
                                              ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxWidth: isFav ? 140 : 170,
                                                ),
                                                child: Material(
                                                  color: theme
                                                      .colorScheme
                                                      .surfaceContainerHigh,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  child: InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    onTap: () =>
                                                        _showFavoriteCategoriesDialog(
                                                          details,
                                                        ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 14,
                                                            vertical: 7,
                                                          ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Flexible(
                                                            child: Text(
                                                              favLabel,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 13.5,
                                                                fontWeight:
                                                                    isFav
                                                                    ? FontWeight
                                                                          .w600
                                                                    : FontWeight
                                                                          .w500,
                                                                color: isFav
                                                                    ? theme
                                                                          .colorScheme
                                                                          .onSurface
                                                                    : theme
                                                                          .colorScheme
                                                                          .onSurfaceVariant,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .arrow_drop_down,
                                                            size: 20,
                                                            color: theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 20),

                                    // Hitung status pembacaan, jumlah bab, dan progres persis Kotatsu Redo
                                    Builder(
                                      builder: (context) {
                                        final historyItem =
                                            LocalStorage.getHistoryItem(
                                              widget.slug,
                                              source: widget.source,
                                            );
                                        final chronoChapters =
                                            _getChronologicalChapters();
                                        final totalChapters =
                                            chronoChapters.isNotEmpty
                                            ? chronoChapters.length
                                            : details.totalChapters;

                                        int readChapterNumber = 0;
                                        double progressPercent = 0.0;

                                        if (historyItem != null &&
                                            totalChapters > 0) {
                                          // 1. Ambil persen progress total yang tersimpan (dari Reader atau Sync)
                                          if (historyItem['percent'] != null) {
                                            final p =
                                                (historyItem['percent'] as num)
                                                    .toDouble();
                                            if (p > 0) {
                                              progressPercent = p.clamp(
                                                0.0,
                                                1.0,
                                              );
                                            }
                                          }

                                          // 2. Cari bab berdasarkan slug di chronoChapters
                                          final lastChapterSlug =
                                              historyItem['chapterSlug']
                                                  as String?;
                                          if (lastChapterSlug != null &&
                                              lastChapterSlug.isNotEmpty &&
                                              chronoChapters.isNotEmpty) {
                                            final cleanLast = lastChapterSlug
                                                .trim()
                                                .replaceAll(
                                                  RegExp(r'^/+|/+$'),
                                                  '',
                                                );
                                            final idx = chronoChapters
                                                .indexWhere((c) {
                                                  if (c.slug == lastChapterSlug) {
                                                    return true;
                                                  }
                                                  final cleanC = c.slug
                                                      .trim()
                                                      .replaceAll(
                                                        RegExp(r'^/+|/+$'),
                                                        '',
                                                      );
                                                  if (cleanC == cleanLast) {
                                                    return true;
                                                  }
                                                    if (SyncService.hashSlug(
                                                              c.slug,
                                                            ).toString() ==
                                                            cleanLast ||
                                                        SyncService.hashSlug(
                                                              c.chapter,
                                                            ).toString() ==
                                                            cleanLast) {
                                                      return true;
                                                    }
                                                  return false;
                                                });
                                            if (idx >= 0) {
                                              readChapterNumber = idx + 1;
                                            }
                                          }

                                          // 3. Cari berdasarkan chapterNumber jika tersimpan
                                          if (readChapterNumber == 0 &&
                                              historyItem['chapterNumber'] !=
                                                  null) {
                                            final chNumRaw =
                                                (historyItem['chapterNumber']
                                                        as num);
                                            final chNum = chNumRaw.toInt();
                                            if (chNum > 0) {
                                              // Exact match angka asli (desimal 3.5 dst)
                                              var idx = chronoChapters
                                                  .indexWhere((c) =>
                                                      c.chapterNumber ==
                                                      chNumRaw);
                                              if (idx == -1) {
                                                idx = chronoChapters
                                                    .indexWhere((c) =>
                                                        c.chapterNumber
                                                            ?.toInt() ==
                                                        chNum);
                                              }
                                              if (idx >= 0) {
                                                readChapterNumber = idx + 1;
                                              } else {
                                                for (int i = chronoChapters.length - 1; i >= 0; i--) {
                                                  final cNum = chronoChapters[i].chapterNumber;
                                                  if (cNum != null && cNum <= chNum) {
                                                    readChapterNumber = i + 1;
                                                    break;
                                                  }
                                                }
                                                if (readChapterNumber == 0 && chNum <= totalChapters) {
                                                  readChapterNumber = chNum;
                                                }
                                              }
                                            }
                                          }

                                          // 4. Coba parse dari chapterTitle HANYA jika masuk akal (<= totalChapters & < 5000)
                                          // Menghindari ID raksasa (misal 3414762387142711808) dianggap sebagai nomor bab
                                          if (readChapterNumber == 0) {
                                            final chTitle =
                                                historyItem['chapterTitle']
                                                    as String? ??
                                                '';
                                            if (chTitle.isNotEmpty) {
                                              final match = RegExp(
                                                r'(?:ch(?:apter)?\.?\s*|bab\s*|#\s*)(\d+(?:\.\d+)?)',
                                                caseSensitive: false,
                                              ).firstMatch(chTitle);
                                              if (match != null) {
                                                final parsed = double.tryParse(
                                                  match.group(1) ?? '',
                                                );
                                                if (parsed != null &&
                                                    parsed > 0 &&
                                                    parsed <= totalChapters &&
                                                    parsed < 5000) {
                                                  readChapterNumber = parsed
                                                      .toInt();
                                                }
                                              }
                                            }
                                          }

                                          // 5. Jika nomor bab belum didapat tapi ada progressPercent (misal hasil sync server),
                                          // turunkan readChapterNumber dari persentase
                                          if (readChapterNumber == 0 &&
                                              progressPercent > 0) {
                                            final prevTotal =
                                                (historyItem['totalChapters']
                                                        as num?)
                                                    ?.toInt();
                                            if (prevTotal != null &&
                                                prevTotal > 0 &&
                                                prevTotal < totalChapters) {
                                              readChapterNumber =
                                                  (progressPercent * prevTotal)
                                                      .round()
                                                      .clamp(1, prevTotal);
                                            } else {
                                              readChapterNumber =
                                                  (progressPercent *
                                                          totalChapters)
                                                      .round()
                                                      .clamp(1, totalChapters);
                                            }
                                          }

                                          // 6. Selalu sinkronkan progressPercent dengan posisi bab saat ini terhadap total bab terbaru
                                          if (readChapterNumber > 0) {
                                            final page =
                                                (historyItem['page'] as num?)
                                                    ?.toDouble() ??
                                                0.0;
                                            final totalPages =
                                                (historyItem['totalPages']
                                                        as num?)
                                                    ?.toDouble() ??
                                                0.0;
                                            final pageFrac = (totalPages > 0)
                                                ? (page / totalPages).clamp(
                                                    0.0,
                                                    1.0,
                                                  )
                                                : 0.0;
                                            final isLastCh =
                                                (readChapterNumber ==
                                                totalChapters);
                                            final savedPct =
                                                (historyItem['percent'] as num?)
                                                    ?.toDouble() ??
                                                0.0;
                                            final isAtLastPage =
                                                totalPages <= 1 ||
                                                page >= totalPages ||
                                                pageFrac >= 1.0;
                                            if (savedPct >= 0.999 ||
                                                (isLastCh &&
                                                    isAtLastPage)) {
                                              progressPercent = 1.0;
                                            } else {
                                              final raw =
                                                  (((readChapterNumber - 1) +
                                                      pageFrac) /
                                                  totalChapters);
                                              final remaining =
                                                  totalChapters -
                                                  readChapterNumber;
                                              if (remaining >= 2) {
                                                progressPercent = raw.clamp(
                                                  0.0,
                                                  remaining >= 3 ? 0.97 : 0.98,
                                                );
                                              } else {
                                                progressPercent = raw.clamp(
                                                  0.0,
                                                  0.99,
                                                );
                                              }
                                            }
                                          }
                                        }

                                        String chaptersValue = '';
                                        if (readChapterNumber > 0 &&
                                            totalChapters > 0) {
                                          final remainingChapters =
                                              (totalChapters -
                                                      readChapterNumber)
                                                  .clamp(0, totalChapters);
                                          final estTime =
                                              _formatEstimatedTimeShort(
                                                remainingChapters,
                                              );
                                          chaptersValue = estTime != null
                                              ? 'Bab $readChapterNumber dari $totalChapters ($estTime)'
                                              : 'Bab $readChapterNumber dari $totalChapters';
                                        } else if (totalChapters > 0) {
                                          final estTime =
                                              _formatEstimatedTimeShort(
                                                totalChapters,
                                              );
                                          chaptersValue = estTime != null
                                              ? '$totalChapters bab ($estTime)'
                                              : '$totalChapters bab';
                                        }

                                        final dividerColor =
                                            theme.brightness == Brightness.dark
                                            ? Colors.white.withValues(
                                                alpha: 0.18,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.12,
                                              );

                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .surfaceContainer,
                                            borderRadius: BorderRadius.circular(
                                              AppTheme.cardRadius,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              _buildSourceRow(
                                                details.source,
                                                theme,
                                              ),
                                              Divider(
                                                height: 18,
                                                thickness: 1,
                                                color: dividerColor,
                                              ),
                                              _buildMetaRow(
                                                'Penulis',
                                                (details.author != null &&
                                                        details.author!
                                                            .trim()
                                                            .isNotEmpty)
                                                    ? details.author!.trim()
                                                    : '-',
                                                theme,
                                              ),
                                              ...[
                                                Divider(
                                                  height: 18,
                                                  thickness: 1,
                                                  color: dividerColor,
                                                ),
                                                _buildMetaRow(
                                                  'Status',
                                                  (details.status != null && details.status!.isNotEmpty)
                                                      ? _formatStatus(details.status!)
                                                      : '-',
                                                  theme,
                                                ),
                                              ],
                                              if (totalChapters > 0) ...[
                                                Divider(
                                                  height: 18,
                                                  thickness: 1,
                                                  color: dividerColor,
                                                ),
                                                _buildMetaRow(
                                                  'Bab',
                                                  chaptersValue,
                                                  theme,
                                                ),
                                              ],
                                              if (historyItem != null &&
                                                  (readChapterNumber > 0 ||
                                                      progressPercent > 0) &&
                                                  totalChapters > 0) ...[
                                                Divider(
                                                  height: 18,
                                                  thickness: 1,
                                                  color: dividerColor,
                                                ),
                                                _buildProgressRow(
                                                  'Progres',
                                                  progressPercent,
                                                  theme,
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    ),

                                    const SizedBox(height: 16),

                                    // Description / Synopsis Title + Collapsible text (selalu tampil)
                                    _SynopsisSection(
                                      synopsis: details.synopsis,
                                    ),
                                    const SizedBox(height: 16),

                                    // Series / Bagian Lain (e.g. for PixHentai multipart doujinshi)
                                    if (details.series.isNotEmpty) ...[
                                      _SeriesSection(
                                        series: details.series,
                                        currentSlug: details.slug,
                                        widgetSlug: widget.slug,
                                        source: widget.source,
                                      ),
                                      const SizedBox(height: 16),
                                    ],

                                    // Genre Chips
                                    if (details.genres.isNotEmpty) ...[
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: details.genres.map((g) {
                                          return ActionChip(
                                            label: Text(g.name),
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            onPressed: () {
                                              final sourcesAsync = ref.read(
                                                sourcesListProvider,
                                              );
                                              final sourceName =
                                                  sourcesAsync.whenOrNull(
                                                    data: (sources) {
                                                      try {
                                                        return sources
                                                            .firstWhere(
                                                              (s) =>
                                                                  s.id ==
                                                                  widget.source,
                                                            )
                                                            .name;
                                                      } catch (_) {
                                                        return null;
                                                      }
                                                    },
                                                  ) ??
                                                  widget.source.toUpperCase();

                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      SourceViewScreen(
                                                        sourceId: widget.source,
                                                        sourceName: sourceName,
                                                        initialGenre: g.slug,
                                                      ),
                                                ),
                                              );
                                            },
                                          );
                                        }).toList(),
                                      ),
                                      const SizedBox(height: 20),
                                    ],

                                    // Similar Manga Carousel
                                    if (details.similar.isNotEmpty &&
                                        LocalStorage.isRelatedMangaEnabled()) ...[
                                      Text(
                                        'Komik Serupa',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        height: 200,
                                        child: ListenableBuilder(
                                          listenable: Listenable.merge([
                                            LocalStorage.listenFavorites(),
                                            LocalStorage.listenHistory(),
                                            LocalStorage.listenFeed(),
                                          ]),
                                          builder: (context, _) {
                                            return ListView.separated(
                                              scrollDirection: Axis.horizontal,
                                              itemCount: details.similar.length,
                                              separatorBuilder: (_, _) =>
                                                  const SizedBox(width: 12),
                                              itemBuilder: (context, index) {
                                                final item =
                                                    details.similar[index];
                                                return SizedBox(
                                                  width: 105,
                                                  child: MangaCard(
                                                    item: item,
                                                    onTap: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              MangaDetailsScreen(
                                                                slug: item.slug,
                                                                source: widget
                                                                    .source,
                                                                title:
                                                                    item.title,
                                                                cover:
                                                                    item.cover,
                                                                id: item.id,
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
                                      const SizedBox(height: 24),
                                    ],

                                    // Divider before Chapters Sheet
                                    const Divider(),
                                    const SizedBox(height: 12),

                                    // Chapters Header Toolbar
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Chapters (${details.chapters.length})',
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            if (LocalStorage.isReadingTimeEstimationEnabled() &&
                                                _getEstimatedReadingTime(
                                                      details.chapters.length,
                                                    ) !=
                                                    null) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: theme
                                                      .colorScheme
                                                      .primaryContainer
                                                      .withValues(alpha: 0.6),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.schedule_rounded,
                                                      size: 13,
                                                      color: theme
                                                          .colorScheme
                                                          .primary,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      _getEstimatedReadingTime(
                                                        details.chapters.length,
                                                      )!,
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: theme
                                                            .colorScheme
                                                            .primary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            // Sort asc/desc button
                                            IconButton(
                                              icon: Icon(
                                                _isSortAscending
                                                    ? Icons.arrow_upward
                                                    : Icons.arrow_downward,
                                              ),
                                              tooltip: _isSortAscending
                                                  ? 'Urutkan Terbaru'
                                                  : 'Urutkan Terlama',
                                              onPressed: () {
                                                setState(() {
                                                  _isSortAscending =
                                                      !_isSortAscending;
                                                });
                                                unawaited(
                                                  LocalStorage.setChapterSortAscending(
                                                    _isSortAscending,
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),

                                    // Chapter Search Input
                                    TextField(
                                      decoration: InputDecoration(
                                        hintText: 'Cari chapter...',
                                        prefixIcon: const Icon(
                                          Icons.search,
                                          size: 20,
                                        ),
                                        isDense: true,
                                        filled: true,
                                        fillColor:
                                            theme.colorScheme.surfaceContainer,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          _chapterSearchQuery = val.trim();
                                        });
                                      },
                                    ),

                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),

                            // Chapters List Tiles
                            SliverPadding(
                              padding: const EdgeInsets.only(bottom: 96),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                 ) {
                                   final ch = displayChapters[index];
                                   final meta = _chapterMetaBySlug[ch.slug] ??
                                       _chapterMetaBySlug[ch.chapter] ??
                                       (chIdx: -1, isExplicitlyRead: false);
                                   final chIndex = meta.chIdx;
                                   final isExplicitlyRead = meta.isExplicitlyRead;

                                   final isLastRead =
                                       !isCompleted &&
                                       lastReadChronoIndex >= 0 &&
                                       chIndex == lastReadChronoIndex;

                                   final isPreviousOrCurrent =
                                       !hasNewerChapters && isCompleted
                                       ? true
                                       : (lastReadChronoIndex >= 0 &&
                                             chIndex >= 0 &&
                                             chIndex <= lastReadChronoIndex);

                                   final bool isBeyondLastRead =
                                       lastReadChronoIndex >= 0 &&
                                       chIndex > lastReadChronoIndex;

                                   final isRead =
                                       !isBeyondLastRead &&
                                       (isCompleted ||
                                           isPreviousOrCurrent ||
                                           isExplicitlyRead ||
                                           isLastRead);

                                  return ListTile(
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: isLastRead
                                          ? theme.colorScheme.primaryContainer
                                          : (isRead
                                                ? theme
                                                      .colorScheme
                                                      .surfaceContainerHigh
                                                      .withValues(alpha: 0.7)
                                                : theme
                                                      .colorScheme
                                                      .surfaceContainerHigh),
                                      child: Icon(
                                        isRead
                                            ? Icons.check
                                            : Icons.menu_book_outlined,
                                        size: 16,
                                        color: isLastRead
                                            ? theme
                                                  .colorScheme
                                                  .onPrimaryContainer
                                            : (isRead
                                                  ? theme.colorScheme.primary
                                                  : theme
                                                        .colorScheme
                                                        .onSurfaceVariant),
                                      ),
                                    ),
                                    title: Text(
                                      ch.title,
                                      style: TextStyle(
                                        fontWeight: isLastRead
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isLastRead
                                            ? theme.colorScheme.primary
                                            : (isRead
                                                  ? theme.colorScheme.onSurface
                                                        .withValues(alpha: 0.6)
                                                  : null),
                                      ),
                                    ),
                                    subtitle: ch.chapterSubtitle != null
                                        ? Text(
                                            ch.chapterSubtitle!,
                                            style: TextStyle(
                                              color: isRead
                                                  ? theme.colorScheme.onSurface
                                                        .withValues(alpha: 0.5)
                                                  : null,
                                            ),
                                          )
                                        : null,
                                    trailing: const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 14,
                                    ),
                                    onTap: () => _openChapterWithHistory(ch),
                                  );
                                }, childCount: displayChapters.length),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Bottom Floating Primary Action: "Baca / Lanjutkan"
            Positioned(
              right: 20,
              bottom: 20,
              child: SafeArea(
                child: FloatingActionButton.extended(
                  onPressed: _resumeOrStartReading,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    historyItem != null ? 'Lanjutkan' : 'Mulai Membaca',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  elevation: 6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _formatEstimatedTimeShort(int chaptersCount) {
    if (chaptersCount <= 0 || !LocalStorage.isReadingTimeEstimationEnabled()) {
      return null;
    }
    final secPerPage = LocalStorage.getAverageSecondsPerPage();
    final totalSeconds = (chaptersCount * 20 * secPerPage).round();
    if (totalSeconds < 60) return null;

    final minutes = (totalSeconds / 60).round();
    final hours = minutes ~/ 60;
    final remMinutes = minutes % 60;

    if (hours > 0) {
      return remMinutes > 0 ? '$hours j $remMinutes m' : '$hours j';
    }
    return '$minutes m';
  }

  Widget _buildSourceRow(String sourceId, ThemeData theme) {
    final sourcesAsync = ref.watch(sourcesListProvider);
    final sourceInfo = sourcesAsync.whenOrNull(
      data: (sources) {
        try {
          return sources.firstWhere((s) => s.id == sourceId);
        } catch (_) {
          return null;
        }
      },
    );
    final sourceIcon = sourceInfo?.icon;
    final sourceName = sourceInfo?.name ?? sourceId.toUpperCase();

    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            'Sumber',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SourceViewScreen(
                      sourceId: sourceId,
                      sourceName: sourceName,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sourceIcon != null && sourceIcon.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedCover(
                          imageUrl: sourceIcon,
                          width: 18,
                          height: 18,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        sourceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatStatus(String status) {
    final lower = status.trim().toLowerCase();
    if (lower == 'ongoing' ||
        lower == 'publishing' ||
        lower == 'berjalan' ||
        lower == 'masih lanjut') {
      return 'Masih lanjut';
    }
    if (lower == 'completed' ||
        lower == 'tamat' ||
        lower == 'end' ||
        lower == 'finished' ||
        lower == 'selesai') {
      return 'Tamat';
    }
    if (lower == 'hiatus') return 'Hiatus';
    if (lower == 'cancelled') return 'Dibatalkan';
    final trimmed = status.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  Widget _buildMetaRow(
    String label,
    String value,
    ThemeData theme, {
    bool isRating = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isRating ? Colors.amber[700] : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressRow(String label, double percent, ThemeData theme) {
    // Kotatsu Redo: PROGRESS_COMPLETED_THRESHOLD = 0.999f
    // Hanya boleh 100% jika seluruh bab telah selesai dibaca (>= 0.999).
    // Bab terakhir yang belum selesai dibaca dibatasi maksimal 99% agar konsisten dengan badge riwayat.
    final isDone = percent >= 0.999;
    final percentInt = isDone ? 100 : ((percent * 100).round()).clamp(0, 99);
    final barValue = isDone ? 1.0 : (percentInt / 100.0);
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: barValue,
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$percentInt%',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Synopsis section that always displays the synopsis title and content
/// (or "Tidak ada sinopsis." placeholder if empty), and only shows "Selengkapnya"
/// when text actually overflows 3 lines.
class _SynopsisSection extends StatefulWidget {
  final String? synopsis;
  const _SynopsisSection({this.synopsis});

  @override
  State<_SynopsisSection> createState() => _SynopsisSectionState();
}

class _SynopsisSectionState extends State<_SynopsisSection> {
  bool _expanded = false;
  bool _hasOverflow = false;

  bool get _isEmpty =>
      widget.synopsis == null || widget.synopsis!.trim().isEmpty;
  String get _displayText =>
      _isEmpty ? 'Tidak ada sinopsis.' : widget.synopsis!.trim();

  @override
  void initState() {
    super.initState();
    // Measure after first frame whether text overflows 3 lines
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(_SynopsisSection old) {
    super.didUpdateWidget(old);
    if (old.synopsis != widget.synopsis) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
    }
  }

  void _checkOverflow() {
    if (!mounted) return;
    if (_isEmpty) {
      if (_hasOverflow) setState(() => _hasOverflow = false);
      return;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: _displayText,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
      ),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: context.size?.width ?? double.infinity);

    final overflows = tp.didExceedMaxLines;
    if (overflows != _hasOverflow) {
      setState(() => _hasOverflow = overflows);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Sinopsis',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_hasOverflow)
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Ringkas' : 'Selengkapnya'),
              ),
          ],
        ),
        Text(
          _displayText,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _isEmpty
                ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
                : theme.colorScheme.onSurface.withValues(alpha: 0.85),
            fontStyle: _isEmpty ? FontStyle.italic : FontStyle.normal,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// Series section showing other parts of a multi-part manga / doujinshi.
/// Current part is plain text (not clickable), other parts are clickable links to details.
class _SeriesSection extends StatelessWidget {
  final List<SeriesItem> series;
  final String currentSlug;
  final String widgetSlug;
  final String source;

  const _SeriesSection({
    required this.series,
    required this.currentSlug,
    required this.widgetSlug,
    required this.source,
  });

  String _normalize(String s) {
    return s.trim().replaceAll(RegExp(r'^/+|\/+$'), '').toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normCurrent = _normalize(currentSlug);
    final normWidget = _normalize(widgetSlug);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bagian Seri',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.35,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < series.length; i++) ...[
                if (i > 0) const Divider(height: 14, thickness: 0.5),
                _buildItem(context, theme, series[i], normCurrent, normWidget),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    ThemeData theme,
    SeriesItem item,
    String normCurrent,
    String normWidget,
  ) {
    final itemSlug = item.slug;
    final normItem = itemSlug != null ? _normalize(itemSlug) : '';
    final isCurrent =
        itemSlug == null ||
        normItem.isEmpty ||
        normItem == normCurrent ||
        normItem == normWidget;

    if (isCurrent) {
      // Current active part: text only (non-clickable)
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Saat Ini',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Other parts: clickable text navigating to manga details
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MangaDetailsScreen(slug: item.slug!, source: source),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Icon(Icons.link, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary.withValues(
                    alpha: 0.5,
                  ),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
