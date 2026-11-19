import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/tracker_notification_service.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/models/feed_item.dart';

class FeedUpdateState {
  final bool isChecking;
  final String? statusText;
  final int totalToCheck;
  final int currentChecked;
  final int newUpdatesCount;
  final DateTime? lastChecked;

  const FeedUpdateState({
    this.isChecking = false,
    this.statusText,
    this.totalToCheck = 0,
    this.currentChecked = 0,
    this.newUpdatesCount = 0,
    this.lastChecked,
  });

  FeedUpdateState copyWith({
    bool? isChecking,
    String? statusText,
    int? totalToCheck,
    int? currentChecked,
    int? newUpdatesCount,
    DateTime? lastChecked,
  }) {
    return FeedUpdateState(
      isChecking: isChecking ?? this.isChecking,
      statusText: statusText ?? this.statusText,
      totalToCheck: totalToCheck ?? this.totalToCheck,
      currentChecked: currentChecked ?? this.currentChecked,
      newUpdatesCount: newUpdatesCount ?? this.newUpdatesCount,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

class FeedUpdateNotifier extends Notifier<FeedUpdateState> {
  @override
  FeedUpdateState build() {
    return const FeedUpdateState();
  }

  /// Checks for new chapters across tracked manga.
  /// Semua mode yang memiliki favorit diperiksa sekaligus —
  /// bukan hanya mode aktif — sehingga komik yang sama di beberapa mode
  /// semuanya mendapat pembaruan dalam satu kali pengecekan.
  Future<int> checkForUpdates({String? modeId}) async {
    if (state.isChecking) return 0;

    // Kumpulkan semua mode yang akan dicek:
    // Jika modeId diberikan secara eksplisit, tetap ikutkan mode lain yang
    // memiliki komik favorit agar tidak ada yang terlewat.
    final allModes = LocalStorage.getContentModes();
    final modesToCheck = allModes.where((m) {
      final favs = LocalStorage.getSortedFavorites(modeId: m.id);
      return favs.isNotEmpty;
    }).toList();

    if (modesToCheck.isEmpty) {
      state = state.copyWith(
        isChecking: false,
        statusText: 'Tidak ada manga untuk dipantau',
      );
      return 0;
    }

    // Hitung total manga yang akan dicek di semua mode
    int trackedCount = 0;
    for (final mode in modesToCheck) {
      final favorites = LocalStorage.getSortedFavorites(modeId: mode.id);
      for (final fav in favorites) {
        final slug = fav['slug'] as String?;
        if (slug == null || slug.isEmpty) continue;
        final cats = (fav['categories'] is List)
            ? List<String>.from(fav['categories'] as List)
            : (fav['category'] != null &&
                    fav['category'] != 'Semua kesukaan' &&
                    fav['category'] != 'Semua'
                ? [fav['category'] as String]
                : <String>[]);
        bool shouldTrack = true;
        if (cats.isNotEmpty) {
          shouldTrack = cats.any((c) {
            final meta = LocalStorage.getCategoryDetails(c, modeId: mode.id);
            return meta['checkNewChapters'] != false;
          });
        }
        if (shouldTrack) trackedCount++;
      }
    }

    if (trackedCount == 0) {
      state = state.copyWith(
        isChecking: false,
        statusText: 'Tidak ada manga untuk dipantau',
      );
      return 0;
    }

    state = FeedUpdateState(
      isChecking: true,
      statusText: 'Menyiapkan pembaruan...',
      totalToCheck: trackedCount,
      currentChecked: 0,
      newUpdatesCount: 0,
      lastChecked: state.lastChecked,
    );

    await TrackerNotificationService.requestPermission();

    // Sync config untuk SEMUA mode sekaligus
    await syncTrackedMangaConfig();

    int newUpdatesFound = 0;
    try {
      newUpdatesFound = await TrackerNotificationService.startBackgroundCheck(
        onProgress: (current, total, title) {
          state = state.copyWith(
            currentChecked: current,
            totalToCheck: total,
            statusText: 'Memeriksa ($current/$total): $title',
          );
        },
      );
    } catch (e) {
      debugPrint('[FeedTracker] Error during native check: $e');
    } finally {
      await importPendingUpdates();
    }

    state = state.copyWith(
      isChecking: false,
      statusText: newUpdatesFound > 0
          ? 'Ditemukan $newUpdatesFound pembaruan'
          : 'Semua sudah diperbarui',
      lastChecked: DateTime.now(),
    );

    return newUpdatesFound;
  }

  Future<void> cancelCheck() async {
    await TrackerNotificationService.cancelCheck();
    state = state.copyWith(
      isChecking: false,
      statusText: 'Pemeriksaan dibatalkan',
    );
  }

  Future<void> syncRunningStatus() async {
    final running = await TrackerNotificationService.isCheckRunning();
    if (running && !state.isChecking) {
      state = state.copyWith(
        isChecking: true,
        statusText: 'Memeriksa pembaruan...',
      );
    }
  }

  static Future<int> importPendingUpdates() async {
    int imported = 0;
    try {
      final pending = await TrackerNotificationService.getPendingFeedUpdates();
      if (pending.isNotEmpty) {
        for (final p in pending) {
          final item = FeedItem.fromJson(p);
          if (item.isValid) {
            await LocalStorage.addFeedItem(item);
            if (item.newChapterSlugs.isNotEmpty) {
              await LocalStorage.markChaptersAsUnread(
                item.mangaSlug,
                item.newChapterSlugs,
                source: item.mangaSource,
                modeId: item.modeId,
              );
            }
            imported++;
          }
        }
        await LocalStorage.syncAllFeedItemsReadStatus();
      }

      // Import updated baselines from native check so Flutter LocalStorage stays in sync
      final pendingBaselines = await TrackerNotificationService.getPendingBaselines();
      for (final b in pendingBaselines) {
        final slug = b['slug'] as String?;
        final modeId = b['modeId'] as String?;
        final lastSlug = b['lastChapterSlug'] as String?;
        final total = (b['totalChapters'] as num?)?.toInt() ?? 0;
        if (slug != null && slug.isNotEmpty && lastSlug != null && lastSlug.isNotEmpty) {
          await LocalStorage.saveTrackBaseline(
            slug,
            lastChapterSlug: lastSlug,
            totalChapters: total,
            modeId: modeId,
          );
        }
      }
    } catch (e) {
      debugPrint('[FeedTracker] Gagal mengimpor pembaruan feed: $e');
    }
    final unread = LocalStorage.getTotalUnreadNewChaptersCount();
    await TrackerNotificationService.setBadgeCount(unread);
    return imported;
  }

  /// Synchronizes tracked manga configuration and baselines to native Android
  /// so that Android AlarmManager & Foreground Service can check updates even when Yomika is closed.
  /// If [modeId] is provided, only manga belonging to that specific content mode will be synced.
  /// If [modeId] is null, ALL modes are synced so a single background check covers every library.
  static Future<void> syncTrackedMangaConfig({String? modeId}) async {
    try {
      final allModes = LocalStorage.getContentModes();
      // null → sync semua mode; modeId tertentu → hanya mode itu
      final modesToSync = modeId != null
          ? allModes.where((m) => m.id == modeId).toList()
          : allModes;

      final Map<String, Map<String, dynamic>> tracked = {};

      for (final mode in modesToSync) {
        // Use user's selected favorites sort order so native check strictly follows screen display
        final favorites = LocalStorage.getSortedFavorites(modeId: mode.id);
        final feedItems = LocalStorage.getFeedItems(modeId: mode.id);

        for (final fav in favorites) {
          final slug = fav['slug'] as String?;
          if (slug != null && slug.isNotEmpty) {
            final cats = (fav['categories'] is List)
                ? List<String>.from(fav['categories'] as List)
                : (fav['category'] != null && fav['category'] != 'Semua kesukaan' && fav['category'] != 'Semua'
                    ? [fav['category'] as String]
                    : <String>[]);
            bool shouldTrack = true;
            if (cats.isNotEmpty) {
              shouldTrack = cats.any((c) {
                final meta = LocalStorage.getCategoryDetails(c, modeId: mode.id);
                return meta['checkNewChapters'] != false;
              });
            }
            if (shouldTrack) {
              final baseline = LocalStorage.getTrackBaseline(slug, modeId: mode.id);
              final key = '${mode.id}::$slug';
              final resolvedSource = fav['source'] as String? ?? '';
              final readSlugs = LocalStorage.getReadChapters(slug, source: resolvedSource, modeId: mode.id);
              final histItem = LocalStorage.getHistoryItem(slug, source: resolvedSource, modeId: mode.id);
              final lastReadSlug = histItem?['chapterSlug'] as String? ?? '';
              final existingFeed = feedItems
                  .where((f) => f.mangaSlug == slug)
                  .expand((f) => f.newChapterSlugs)
                  .toList();

              final savedLastSlug = baseline?['lastChapterSlug'] as String? ?? '';
              final savedTotal = (baseline?['totalChapters'] as num?)?.toInt() ?? 0;
              final histPercent = (histItem?['percent'] as num?)?.toDouble() ?? 0.0;
              final histChNum = (histItem?['chapterNumber'] as num?)?.toInt() ?? 0;
              final isCompleted = existingFeed.isEmpty &&
                  histPercent >= 0.999 &&
                  (savedTotal > 0 ? histChNum >= savedTotal : histChNum > 0);

              tracked[key] = {
                'slug': slug,
                'source': resolvedSource,
                'title': fav['title'] ?? slug,
                'cover': fav['cover'] ?? '',
                'lastChapterSlug': savedLastSlug,
                'totalChapters': savedTotal,
                'modeId': mode.id,
                'modeName': mode.name,
                'readChapterSlugs': readSlugs,
                'lastReadSlug': lastReadSlug,
                'feedChapterSlugs': existingFeed,
                'percent': histPercent,
                'isCompleted': isCompleted,
              };
            }
          }
        }
      }

      await TrackerNotificationService.syncTrackerConfig(
        enabled: LocalStorage.isTrackerEnabled(),
        frequencyHours: LocalStorage.getTrackerFrequencyHours(),
        wifiOnly: LocalStorage.isTrackerWifiOnly(),
        items: tracked.values.toList(),
      );
    } catch (e) {
      debugPrint('[FeedTracker] Gagal menyinkronkan konfigurasi pelacak ke Android: $e');
    }
  }
}

final feedUpdateProvider =
    NotifierProvider<FeedUpdateNotifier, FeedUpdateState>(FeedUpdateNotifier.new);

final feedHeaderVisibleProvider =
    NotifierProvider<FeedHeaderVisibleNotifier, bool>(FeedHeaderVisibleNotifier.new);

class FeedHeaderVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => LocalStorage.isFeedHeaderVisible();

  void toggle() {
    final next = !state;
    state = next;
    LocalStorage.setFeedHeaderVisible(next);
  }

  void setVisible(bool visible) {
    state = visible;
    LocalStorage.setFeedHeaderVisible(visible);
  }
}
