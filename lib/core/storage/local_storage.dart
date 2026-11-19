import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../../shared/models/content_mode.dart';
import '../../shared/models/feed_item.dart';
import '../services/sync_service.dart';
import '../services/tracker_notification_service.dart';
import '../../shared/widgets/cached_cover.dart';
import 'cover_cache_manager.dart';

class LocalStorage {
  static late Box _favoritesBox;
  static late Box _historyBox;
  static late Box _settingsBox;
  static late Box _feedBox;
  static late SharedPreferences _prefs;

  static SharedPreferences get prefs => _prefs;

  // Storage key constants (inlined — no longer depends on ApiConstants)
  static const _keyApiBaseUrl    = 'api_base_url';
  static const _keyActiveSource  = 'active_source';
  static const _keyThemeMode     = 'theme_mode';
  static const _keyReaderMode    = 'reader_mode';
  static const _keyReaderCdn     = 'reader_cdn';
  static const _keyShinigamiSrv  = 'shinigami_server';

  static late Directory _cachedCoversDir;
  static Directory get cachedCoversDir => _cachedCoversDir;

  // In-memory performance caches for fast scroll list/grid rendering
  static final Map<String, int> _unreadNewChaptersCountCache = {};
  static final Map<String, double> _historyProgressCache = {};
  static final Map<String, bool> _isFavoriteCache = {};
  static final Map<String, Map<String, dynamic>?> _favoriteEntryCache = {};
  static final Map<String, String?> _customCoverCache = {};

  static void invalidateUnreadCountsCache() {
    _unreadNewChaptersCountCache.clear();
  }

  static void invalidateHistoryProgressCache() {
    _historyProgressCache.clear();
  }

  static void invalidateFavoriteCache() {
    _isFavoriteCache.clear();
    _favoriteEntryCache.clear();
  }

  static void invalidateCustomCoverCache() {
    _customCoverCache.clear();
  }

  static Future<void> init([String? customPath]) async {
    _prefs = await SharedPreferences.getInstance();
    if (customPath != null) {
      Hive.init(customPath);
      _cachedCoversDir = Directory('$customPath/cached_covers');
      if (!_cachedCoversDir.existsSync()) {
        _cachedCoversDir.createSync(recursive: true);
      }
    } else {
      await Hive.initFlutter();
      try {
        final docDir = await getApplicationDocumentsDirectory();
        _cachedCoversDir = Directory('${docDir.path}/cached_covers');
        if (!_cachedCoversDir.existsSync()) {
          _cachedCoversDir.createSync(recursive: true);
        }
      } catch (_) {
        _cachedCoversDir = Directory('${Directory.systemTemp.path}/cached_covers');
        if (!_cachedCoversDir.existsSync()) {
          _cachedCoversDir.createSync(recursive: true);
        }
      }
    }
    _favoritesBox = await Hive.openBox('favorites');
    _historyBox   = await Hive.openBox('history');
    _settingsBox  = await Hive.openBox('settings');
    _feedBox      = await Hive.openBox('feed');

    _favoritesBox.watch().listen((_) => invalidateFavoriteCache());
    _settingsBox.watch().listen((_) => invalidateCustomCoverCache());

    await _migrateContentModes();
  }

  // --- Content Modes (Multiple Library) ---

  static final ValueNotifier<String> contentModeNotifier =
      ValueNotifier<String>(ContentMode.defaultNormalId);

  static ValueListenable<String> listenContentMode() => contentModeNotifier;

  static void notifyContentModeChanged() {
    contentModeNotifier.value = getActiveContentModeId();
  }

  static String _modeKey(String key, [String? modeId]) {
    final m = modeId ?? getActiveContentModeId();
    if (key.startsWith('$m::')) return key;
    return '$m::$key';
  }

  static String _cleanSlug(String slug) {
    return slug.trim().replaceAll(RegExp(r'^/?manga/|/$'), '');
  }

  static String cleanSlug(String slug) => _cleanSlug(slug);
  static double? extractChapterNum(String text) => _extractChapterNum(text);

  static Future<void> _migrateContentModes() async {
    // 1. Ensure default modes exist
    if (!_settingsBox.containsKey('content_modes')) {
      final defaultList =
          ContentMode.defaultModes().map((m) => m.toJson()).toList();
      await _settingsBox.put('content_modes', defaultList);
    }

    // 2. Ensure active mode is set
    final activeId = _settingsBox.get('active_content_mode');
    if (activeId == null || activeId.toString().isEmpty) {
      final defaultId = _settingsBox.get(
        'default_content_mode',
        defaultValue: ContentMode.defaultNormalId,
      ) as String;
      await _settingsBox.put('active_content_mode', defaultId);
    }
    contentModeNotifier.value = getActiveContentModeId();

    // 3. Migrate legacy un-prefixed keys to mode 'normal'
    final migrated = _settingsBox.get(
      'content_modes_migrated_v1',
      defaultValue: false,
    ) as bool;
    if (!migrated) {
      final normal = ContentMode.defaultNormalId;

      // Migrate favorites
      final favKeys = List<dynamic>.from(_favoritesBox.keys);
      for (final key in favKeys) {
        final keyStr = key.toString();
        if (!keyStr.contains('::')) {
          final val = _favoritesBox.get(key);
          if (val is Map) {
            final map = Map<String, dynamic>.from(val);
            map['mode_id'] = normal;
            await _favoritesBox.put('$normal::$keyStr', map);
          } else {
            await _favoritesBox.put('$normal::$keyStr', val);
          }
          await _favoritesBox.delete(key);
        }
      }

      // Migrate history
      final histKeys = List<dynamic>.from(_historyBox.keys);
      for (final key in histKeys) {
        final keyStr = key.toString();
        if (!keyStr.contains('::')) {
          final val = _historyBox.get(key);
          if (val is Map) {
            final map = Map<String, dynamic>.from(val);
            map['mode_id'] = normal;
            await _historyBox.put('$normal::$keyStr', map);
          } else {
            await _historyBox.put('$normal::$keyStr', val);
          }
          await _historyBox.delete(key);
        }
      }

      // Migrate settings for categories, sort orders, and sources
      final normalPrefix = '$normal::';
      if (_settingsBox.containsKey('favorite_categories') &&
          !_settingsBox.containsKey('${normalPrefix}favorite_categories')) {
        await _settingsBox.put(
          '${normalPrefix}favorite_categories',
          _settingsBox.get('favorite_categories'),
        );
      }
      if (_settingsBox.containsKey('active_source') &&
          !_settingsBox.containsKey('${normalPrefix}active_source')) {
        await _settingsBox.put(
          '${normalPrefix}active_source',
          _settingsBox.get('active_source'),
        );
      }
      if (_settingsBox.containsKey('pinned_sources') &&
          !_settingsBox.containsKey('${normalPrefix}pinned_sources')) {
        await _settingsBox.put(
          '${normalPrefix}pinned_sources',
          _settingsBox.get('pinned_sources'),
        );
      }
      if (_settingsBox.containsKey('disabled_sources') &&
          !_settingsBox.containsKey('${normalPrefix}disabled_sources')) {
        await _settingsBox.put(
          '${normalPrefix}disabled_sources',
          _settingsBox.get('disabled_sources'),
        );
      }
      if (_settingsBox.containsKey('favorites_sort_order') &&
          !_settingsBox.containsKey('${normalPrefix}favorites_sort_order')) {
        await _settingsBox.put(
          '${normalPrefix}favorites_sort_order',
          _settingsBox.get('favorites_sort_order'),
        );
      }
      if (_settingsBox.containsKey('sync_category_ids') &&
          !_settingsBox.containsKey('${normalPrefix}sync_category_ids')) {
        await _settingsBox.put(
          '${normalPrefix}sync_category_ids',
          _settingsBox.get('sync_category_ids'),
        );
      }
      if (_settingsBox.containsKey('deleted_favorite_tombstones') &&
          !_settingsBox.containsKey('${normalPrefix}deleted_favorite_tombstones')) {
        await _settingsBox.put(
          '${normalPrefix}deleted_favorite_tombstones',
          _settingsBox.get('deleted_favorite_tombstones'),
        );
      }
      if (_settingsBox.containsKey('deleted_history_tombstones') &&
          !_settingsBox.containsKey('${normalPrefix}deleted_history_tombstones')) {
        await _settingsBox.put(
          '${normalPrefix}deleted_history_tombstones',
          _settingsBox.get('deleted_history_tombstones'),
        );
      }
      if (_settingsBox.containsKey('deleted_category_tombstones') &&
          !_settingsBox.containsKey('${normalPrefix}deleted_category_tombstones')) {
        await _settingsBox.put(
          '${normalPrefix}deleted_category_tombstones',
          _settingsBox.get('deleted_category_tombstones'),
        );
      }
      if (_settingsBox.containsKey('history_sort_order') &&
          !_settingsBox.containsKey('${normalPrefix}history_sort_order')) {
        await _settingsBox.put(
          '${normalPrefix}history_sort_order',
          _settingsBox.get('history_sort_order'),
        );
      }
      if (_settingsBox.containsKey('history_grouping_enabled') &&
          !_settingsBox.containsKey('${normalPrefix}history_grouping_enabled')) {
        await _settingsBox.put(
          '${normalPrefix}history_grouping_enabled',
          _settingsBox.get('history_grouping_enabled'),
        );
      }

      // Migrate cat_meta_*
      final settingKeys = List<dynamic>.from(_settingsBox.keys);
      for (final key in settingKeys) {
        final keyStr = key.toString();
        if (keyStr.startsWith('cat_meta_') && !keyStr.contains('::')) {
          await _settingsBox.put('$normalPrefix$keyStr', _settingsBox.get(key));
        }
      }

      await _settingsBox.put('content_modes_migrated_v1', true);
    }

    // Migrate sync account & settings to Mode 1 (Normal) if legacy global keys exist
    if (!_settingsBox.containsKey('content_modes_sync_migrated_v1')) {
      final normal = ContentMode.defaultNormalId;
      final normalPrefix = '$normal::';
      final syncKeys = [
        'sync_server_url',
        'sync_email',
        'sync_token',
        'sync_enabled',
        'sync_favorites_enabled',
        'sync_history_enabled',
        'sync_period_hours',
        'sync_last_time',
        'sync_category_ids',
      ];
      for (final sk in syncKeys) {
        if (_settingsBox.containsKey(sk)) {
          if (!_settingsBox.containsKey('$normalPrefix$sk')) {
            await _settingsBox.put('$normalPrefix$sk', _settingsBox.get(sk));
          }
          await _settingsBox.delete(sk);
        }
      }
      await _settingsBox.put('content_modes_sync_migrated_v1', true);
    }

    // Ensure all sources are enabled in all modes by default (no forced source splitting)
    if (!_settingsBox.containsKey('content_modes_sources_all_enabled_v3')) {
      final raw = _settingsBox.get('content_modes');
      if (raw is List) {
        final currentModes = raw
            .map((e) => ContentMode.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final updated = currentModes.map((m) {
          if (m.id == ContentMode.defaultNormalId || m.id == ContentMode.defaultRestrictedId) {
            return m.copyWith(disabledSources: const [], enabledSources: const []);
          }
          return m;
        }).toList();
        await saveContentModes(updated);
      }
      await _settingsBox.delete('${ContentMode.defaultNormalId}::disabled_sources');
      await _settingsBox.delete('${ContentMode.defaultRestrictedId}::disabled_sources');
      await _settingsBox.put('content_modes_sources_all_enabled_v3', true);
    }

    // Purge any corrupted or baseline entries previously stored as feed items in _feedBox
    final feedKeys = List<dynamic>.from(_feedBox.keys);
    for (final k in feedKeys) {
      final keyStr = k.toString();
      if (keyStr.contains('track_') || keyStr.startsWith('track_')) continue;
      final raw = _feedBox.get(k);
      if (raw is Map) {
        final slug = raw['mangaSlug'] as String?;
        final title = raw['mangaTitle'] as String?;
        final source = raw['mangaSource'] as String?;
        if (slug == null ||
            slug.trim().isEmpty ||
            title == null ||
            title.trim().isEmpty ||
            source == null ||
            source.toLowerCase() == 'unknown') {
          await _feedBox.delete(k);
        }
      } else {
        await _feedBox.delete(k);
      }
    }

    // Ensure custom modes (like Restricted) are NOT logged into the same sync account as Normal mode
    final normalToken = getSyncToken(modeId: ContentMode.defaultNormalId);
    final normalEmail = getSyncEmail(modeId: ContentMode.defaultNormalId);
    if (normalToken != null && normalToken.isNotEmpty) {
      final allModes = getContentModes();
      for (final m in allModes) {
        if (m.id == ContentMode.defaultNormalId) continue;
        final mToken = getSyncToken(modeId: m.id);
        final mEmail = getSyncEmail(modeId: m.id);
        if (mToken == normalToken || (mEmail != null && mEmail == normalEmail)) {
          await setSyncToken(null, modeId: m.id);
          await setSyncEmail(null, modeId: m.id);
          await setSyncEnabled(false, modeId: m.id);
        }
      }
    }

    // Recovery for custom modes (e.g. Restricted) that had their favorites wiped
    final modes = getContentModes();
    final customModes = modes.where((m) => m.id != ContentMode.defaultNormalId).toList();
    for (final cm in customModes) {
      final cmFavs = getFavorites(modeId: cm.id);
      if (cmFavs.isEmpty) {
        final favTombstones = getDeletedFavoriteTombstones(modeId: cm.id);
        if (favTombstones.isNotEmpty) {
          for (final t in favTombstones) {
            final slug = t['slug'] as String? ?? '';
            if (slug.isEmpty) continue;
            final normalFav = getFavorite(slug, modeId: ContentMode.defaultNormalId);
            final normalHist = getHistoryItem(slug, modeId: ContentMode.defaultNormalId);

            final title = (normalFav?['title'] as String?) ?? (t['title'] as String?) ?? slug;
            final cover = (normalFav?['cover'] as String?) ?? (normalHist?['cover'] as String?);
            final source = (normalFav?['source'] as String?) ?? (t['source'] as String?) ?? (normalHist?['source'] as String?) ?? 'shinigami';
            final cat = t['category'] as String? ?? (t['categories'] as List?)?.firstOrNull?.toString() ?? 'Manhwa 18+';
            final cats = (t['categories'] as List?)?.map((e) => e.toString()).toList() ?? (cat.isNotEmpty ? [cat] : <String>[]);

            await saveFavorite(
              slug: slug,
              title: title,
              cover: cover,
              source: source,
              category: cat,
              categories: cats,
              modeId: cm.id,
            );

            final histItem = normalHist ?? getHistoryItem(slug, modeId: cm.id);
            if (histItem != null) {
              await saveHistory(
                slug: slug,
                title: histItem['title'] as String? ?? title,
                cover: histItem['cover'] as String? ?? cover,
                source: histItem['source'] as String? ?? source,
                chapterSlug: histItem['chapterSlug'] as String? ?? '',
                chapterTitle: histItem['chapterTitle'] as String? ?? '',
                page: (histItem['page'] as num?)?.toInt() ?? 1,
                totalPages: (histItem['totalPages'] as num?)?.toInt() ?? 1,
                percent: (histItem['percent'] as num?)?.toDouble(),
                scrollOffset: (histItem['scrollOffset'] as num?)?.toDouble() ?? 0.0,
                pageHeights: histItem['pageHeights'] != null ? Map<int, double>.from(histItem['pageHeights']) : null,
                pageOffsetRatio: (histItem['pageOffsetRatio'] as num?)?.toDouble(),
                modeId: cm.id,
              );
            }
          }
          await clearDeletedFavoriteTombstones(modeId: cm.id);
          await clearDeletedHistoryTombstones(modeId: cm.id);
        }
      }

      // If Normal mode has comics tagged with 'Manhwa 18+', transfer them to Restricted
      final normalFavs = getFavorites(modeId: ContentMode.defaultNormalId);
      for (final f in normalFavs) {
        final cats = (f['categories'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final primaryCat = f['category'] as String?;
        if (cats.contains('Manhwa 18+') || primaryCat == 'Manhwa 18+') {
          final slug = f['slug'] as String? ?? '';
          if (slug.isNotEmpty) {
            await transferManga(
              slug: slug,
              fromModeId: ContentMode.defaultNormalId,
              toModeId: cm.id,
              targetCategory: 'Manhwa 18+',
            );
          }
        }
      }
    }

    // Migrate legacy favorites to source-scoped keys
    final favKeys = List<dynamic>.from(_favoritesBox.keys);
    for (final key in favKeys) {
      final keyStr = key.toString();
      final parts = keyStr.split('::');
      if (parts.length == 2) {
        final mode = parts[0];
        final subKey = parts[1];
        if (subKey.startsWith('bm_') || subKey.startsWith('tombstone_')) continue;
        final raw = _favoritesBox.get(key);
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final src = (map['source'] as String?)?.trim().toLowerCase();
          final s = (map['slug'] as String?)?.trim() ?? subKey;
          if (src != null && src.isNotEmpty && s.isNotEmpty) {
            await _favoritesBox.put('$mode::$src::$s', map);
            await _favoritesBox.delete(key);
          }
        }
      }
    }

    // Migrate legacy history to source-scoped keys
    final histKeys = List<dynamic>.from(_historyBox.keys);
    for (final key in histKeys) {
      final keyStr = key.toString();
      final parts = keyStr.split('::');
      if (parts.length == 2) {
        final mode = parts[0];
        final subKey = parts[1];
        if (subKey.startsWith('read_') || subKey.startsWith('tombstone_')) continue;
        final raw = _historyBox.get(key);
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final src = (map['source'] as String?)?.trim().toLowerCase();
          final s = (map['slug'] as String?)?.trim() ?? subKey;
          if (src != null && src.isNotEmpty && s.isNotEmpty) {
            await _historyBox.put('$mode::$src::$s', map);
            await _historyBox.delete(key);
          }
        }
      }
    }

    // Clean up any manga that exist in custom modes (e.g. Restricted) from Normal mode
    // (caused by previous sync leakage where transferred manga were restored into Normal)
    if (customModes.isNotEmpty) {
      final normal = ContentMode.defaultNormalId;
      for (final cm in customModes) {
        final customFavs = getFavorites(modeId: cm.id);
        for (final fav in customFavs) {
          final slug = fav['slug'] as String? ?? '';
          final source = fav['source'] as String?;
          if (slug.isNotEmpty && isFavorite(slug, source: source, modeId: normal)) {
            await removeFavorite(slug, source: source, recordTombstone: true, modeId: normal);
          }
        }
        final customHist = getHistory(modeId: cm.id);
        for (final h in customHist) {
          final slug = h['slug'] as String? ?? '';
          final source = h['source'] as String?;
          if (slug.isNotEmpty && getHistoryItem(slug, source: source, modeId: normal) != null) {
            await deleteHistoryItem(slug, source: source, recordTombstone: true, modeId: normal);
          }
        }
      }
    }
  }

  static List<ContentMode> getContentModes() {
    final raw = _settingsBox.get('content_modes');
    if (raw is List) {
      return raw
          .map((e) => ContentMode.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return ContentMode.defaultModes();
  }

  static Future<void> saveContentModes(List<ContentMode> modes) async {
    final list = modes.map((m) => m.toJson()).toList();
    await _settingsBox.put('content_modes', list);
  }

  static String getActiveContentModeId() {
    return _settingsBox.get(
      'active_content_mode',
      defaultValue: getDefaultContentModeId(),
    ) as String;
  }

  static Future<void> setActiveContentModeId(String modeId) async {
    await _settingsBox.put('active_content_mode', modeId);
    notifyContentModeChanged();
  }

  static ContentMode getActiveContentMode() {
    final activeId = getActiveContentModeId();
    final modes = getContentModes();
    try {
      return modes.firstWhere((m) => m.id == activeId);
    } catch (_) {
      return modes.isNotEmpty ? modes.first : ContentMode.normal;
    }
  }

  static String getDefaultContentModeId() {
    return _settingsBox.get(
      'default_content_mode',
      defaultValue: ContentMode.defaultNormalId,
    ) as String;
  }

  static Future<void> setDefaultContentModeId(String modeId) async {
    await _settingsBox.put('default_content_mode', modeId);
    final modes = getContentModes();
    final updated =
        modes.map((m) => m.copyWith(isDefault: m.id == modeId)).toList();
    await saveContentModes(updated);
  }

  static Future<ContentMode> createContentMode({
    required String name,
    String description = '',
    List<String>? enabledSources,
    List<String>? disabledSources,
    bool isDefault = false,
  }) async {
    final modes = getContentModes();
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final newMode = ContentMode(
      id: id,
      name: name.trim().isNotEmpty ? name.trim() : 'Library Baru',
      description: description.trim(),
      isDefault: isDefault,
      isDeletable: true,
      enabledSources: enabledSources ?? const [],
      disabledSources: disabledSources ?? const [],
    );

    modes.add(newMode);
    if (isDefault) {
      for (int i = 0; i < modes.length - 1; i++) {
        modes[i] = modes[i].copyWith(isDefault: false);
      }
      await _settingsBox.put('default_content_mode', id);
    }
    await saveContentModes(modes);
    return newMode;
  }

  static Future<void> updateContentMode(
    String id, {
    String? name,
    String? description,
    List<String>? enabledSources,
    List<String>? disabledSources,
    bool? isDefault,
  }) async {
    final modes = getContentModes();
    final idx = modes.indexWhere((m) => m.id == id);
    if (idx == -1) return;

    var mode = modes[idx];
    if (name != null && name.trim().isNotEmpty) {
      mode = mode.copyWith(name: name.trim());
    }
    if (description != null) {
      mode = mode.copyWith(description: description.trim());
    }
    if (enabledSources != null) {
      mode = mode.copyWith(enabledSources: enabledSources);
    }
    if (disabledSources != null) {
      mode = mode.copyWith(disabledSources: disabledSources);
    }
    if (isDefault != null) {
      mode = mode.copyWith(isDefault: isDefault);
      if (isDefault) {
        await setDefaultContentModeId(id);
      }
    }
    modes[idx] = mode;
    await saveContentModes(modes);

    if (disabledSources != null) {
      await setDisabledSources(disabledSources, modeId: id);
    }
  }

  static Future<bool> deleteContentMode(String id) async {
    if (id == ContentMode.defaultNormalId) return false; // Normal cannot be deleted

    final modes = getContentModes();
    modes.removeWhere((m) => m.id == id);
    await saveContentModes(modes);

    if (getActiveContentModeId() == id) {
      await setActiveContentModeId(ContentMode.defaultNormalId);
    }
    if (getDefaultContentModeId() == id) {
      await setDefaultContentModeId(ContentMode.defaultNormalId);
    }

    final prefix = '$id::';
    final favKeys =
        _favoritesBox.keys.where((k) => k.toString().startsWith(prefix)).toList();
    for (final k in favKeys) {
      await _favoritesBox.delete(k);
    }
    final histKeys =
        _historyBox.keys.where((k) => k.toString().startsWith(prefix)).toList();
    for (final k in histKeys) {
      await _historyBox.delete(k);
    }
    final settingKeys =
        _settingsBox.keys.where((k) => k.toString().startsWith(prefix)).toList();
    for (final k in settingKeys) {
      await _settingsBox.delete(k);
    }

    notifyContentModeChanged();
    return true;
  }

  /// Transfers a manga (favorite, reading progress, history, read chapters, bookmarks)
  /// from [fromModeId] to [toModeId] without creating unnecessary duplicates.
  /// If [targetCategory] is provided, sets the comic's category in [toModeId]
  /// and automatically registers it in [toModeId]'s favorite categories.
  static Future<bool> transferManga({
    required String slug,
    String? source,
    required String fromModeId,
    required String toModeId,
    String? targetCategory,
  }) async {
    if (fromModeId == toModeId) return false;
    final clean = _cleanSlug(slug);
    final src = source?.trim().toLowerCase();

    // Record deletion tombstones for fromModeId so cloud sync removes it from fromModeId's account
    final fromFav = getFavorite(slug, source: src, modeId: fromModeId);
    if (fromFav != null) {
      final catList = (fromFav['categories'] as List?)?.map((e) => e.toString()).toList();
      final primaryCat = fromFav['category']?.toString();
      await recordDeletedFavoriteTombstone(
        slug,
        title: fromFav['title'] as String?,
        source: fromFav['source'] as String? ?? source,
        categories: catList,
        category: primaryCat,
        modeId: fromModeId,
      );
    }
    final fromHist = getHistoryItem(slug, source: src, modeId: fromModeId);
    if (fromHist != null) {
      await recordDeletedHistoryTombstone(
        slug,
        title: fromHist['title'] as String?,
        source: fromHist['source'] as String? ?? source,
        modeId: fromModeId,
      );
    }

    // 1. Move Favorite
    final fav = getFavorite(slug, source: src, modeId: fromModeId);
    if (fav != null) {
      final itemSource = (fav['source'] as String? ?? src ?? '').toLowerCase();
      final updated = Map<String, dynamic>.from(fav);
      updated['mode_id'] = toModeId;
      if (targetCategory != null &&
          targetCategory.trim().isNotEmpty &&
          targetCategory.trim() != 'Semua kesukaan' &&
          targetCategory.trim() != 'Semua') {
        final cat = targetCategory.trim();
        updated['category'] = cat;
        updated['categories'] = [cat];
        await addFavoriteCategory(cat, modeId: toModeId);
      } else {
        updated['category'] = null;
        updated['categories'] = <String>[];
      }
      final key = itemSource.isNotEmpty ? '$toModeId::$itemSource::$slug' : '$toModeId::$slug';
      await _favoritesBox.put(key, updated);
      if (itemSource.isNotEmpty) {
        await _favoritesBox.delete('$fromModeId::$itemSource::$slug');
        if (clean.isNotEmpty) {
          await _favoritesBox.delete('$fromModeId::$itemSource::$clean');
          await _favoritesBox.delete('$fromModeId::$itemSource::manga/$clean');
        }
      }
      await _favoritesBox.delete('$fromModeId::$slug');
      if (clean.isNotEmpty) {
        await _favoritesBox.delete('$fromModeId::$clean');
        await _favoritesBox.delete('$fromModeId::manga/$clean');
      }
    }

    // 2. Move Bookmarks
    final bmPrefix = '$fromModeId::bm_${slug}_';
    final bmCleanPrefix =
        clean.isNotEmpty ? '$fromModeId::bm_${clean}_' : null;
    final bmKeys = _favoritesBox.keys.where((k) {
      final s = k.toString();
      return s.startsWith(bmPrefix) ||
          (bmCleanPrefix != null && s.startsWith(bmCleanPrefix));
    }).toList();

    for (final bk in bmKeys) {
      final raw = _favoritesBox.get(bk);
      if (raw is Map) {
        final bMap = Map<String, dynamic>.from(raw);
        bMap['mode_id'] = toModeId;
        final rawSubKey = bk.toString().substring(fromModeId.length + 2);
        await _favoritesBox.put('$toModeId::$rawSubKey', bMap);
      }
      await _favoritesBox.delete(bk);
    }

    // 3. Move Reading History (ensures all progress, page heights, and scroll offsets are moved)
    final hist = getHistoryItem(slug, source: src, modeId: fromModeId);
    if (hist != null) {
      final itemSource = (hist['source'] as String? ?? src ?? '').toLowerCase();
      final updated = Map<String, dynamic>.from(hist);
      updated['mode_id'] = toModeId;
      final key = itemSource.isNotEmpty ? '$toModeId::$itemSource::$slug' : '$toModeId::$slug';
      await _historyBox.put(key, updated);
      if (itemSource.isNotEmpty) {
        await _historyBox.delete('$fromModeId::$itemSource::$slug');
        if (clean.isNotEmpty) {
          await _historyBox.delete('$fromModeId::$itemSource::$clean');
          await _historyBox.delete('$fromModeId::$itemSource::manga/$clean');
        }
      }
      await _historyBox.delete('$fromModeId::$slug');
      if (clean.isNotEmpty) {
        await _historyBox.delete('$fromModeId::$clean');
        await _historyBox.delete('$fromModeId::manga/$clean');
      }
    }

    // 4. Move Read Chapters
    final favOrHistSource = fav?['source'] as String? ?? hist?['source'] as String? ?? source;
    final readList = getReadChapters(slug, source: favOrHistSource, modeId: fromModeId);
    if (readList.isNotEmpty) {
      await markChaptersAsRead(slug, readList, source: favOrHistSource, modeId: toModeId);
      if (favOrHistSource != null && favOrHistSource.isNotEmpty) {
        final sLow = favOrHistSource.toLowerCase();
        await _historyBox.delete('$fromModeId::read_${sLow}_$slug');
        if (clean.isNotEmpty) {
          await _historyBox.delete('$fromModeId::read_${sLow}_$clean');
        }
      }
      await _historyBox.delete('$fromModeId::read_$slug');
      if (clean.isNotEmpty) {
        await _historyBox.delete('$fromModeId::read_$clean');
        await _historyBox.delete('$fromModeId::read_manga/$clean');
      }
    }

    // 5. Update active reader session if it was pointing to this manga
    final activeSession = getActiveReaderSession();
    if (activeSession != null) {
      final sessSlug = activeSession['mangaSlug']?.toString() ?? '';
      if (sessSlug == slug || (clean.isNotEmpty && _cleanSlug(sessSlug) == clean)) {
        activeSession['mode_id'] = toModeId;
        await saveActiveReaderSession(activeSession);
      }
    }

    notifyContentModeChanged();
    return true;
  }

  static Future<int> transferMultipleManga({
    required Iterable<String> slugs,
    required String fromModeId,
    required String toModeId,
    String? targetCategory,
  }) async {
    if (fromModeId == toModeId) return 0;
    int count = 0;
    for (final slug in slugs) {
      final ok = await transferManga(
        slug: slug,
        fromModeId: fromModeId,
        toModeId: toModeId,
        targetCategory: targetCategory,
      );
      if (ok) count++;
    }
    return count;
  }

  /// Membersihkan seluruh data (favorit, kategori, riwayat baca, read chapters, tombstones)
  /// pada suatu mode tertentu. Mode bawaan (Normal) dilindungi agar tidak dapat di-reset melalui metode ini.
  static Future<void> clearModeData(String modeId) async {
    if (modeId == ContentMode.defaultNormalId) return;
    final prefix = '$modeId::';

    final favKeys =
        _favoritesBox.keys.where((k) => k.toString().startsWith(prefix)).toList();
    for (final k in favKeys) {
      await _favoritesBox.delete(k);
    }

    final histKeys =
        _historyBox.keys.where((k) => k.toString().startsWith(prefix)).toList();
    for (final k in histKeys) {
      await _historyBox.delete(k);
    }

    await _settingsBox.delete(_modeKey('favorite_categories', modeId));
    await _settingsBox.delete(_modeKey('deleted_favorite_tombstones', modeId));
    await _settingsBox.delete(_modeKey('deleted_history_tombstones', modeId));
    await _settingsBox.delete(_modeKey('deleted_category_tombstones', modeId));
    await _settingsBox.delete(_modeKey('sync_category_ids', modeId));
    await _settingsBox.delete(_modeKey('sync_token', modeId));
    await _settingsBox.delete(_modeKey('sync_email', modeId));
    await _settingsBox.delete(_modeKey('sync_server_url', modeId));
    await _settingsBox.delete(_modeKey('sync_enabled', modeId));
    await _settingsBox.delete(_modeKey('sync_favorites_enabled', modeId));
    await _settingsBox.delete(_modeKey('sync_history_enabled', modeId));
    await _settingsBox.delete(_modeKey('sync_period_hours', modeId));
    await _settingsBox.delete(_modeKey('sync_last_time', modeId));
    await clearFeed(modeId: modeId);

    notifyContentModeChanged();
  }

  // --- Settings & Preferences ---

  static String getBaseUrl() {
    return _settingsBox.get(_keyApiBaseUrl, defaultValue: '') as String;
  }

  static Future<void> setBaseUrl(String url) async {
    await _settingsBox.put(_keyApiBaseUrl, url);
  }

  static String getActiveSource({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final saved = _settingsBox.get(_modeKey(_keyActiveSource, m)) as String?;
    if (saved != null && saved.isNotEmpty && isSourceEnabled(saved, modeId: m)) {
      return saved;
    }
    final modes = getContentModes();
    final mode = modes.firstWhere(
      (mod) => mod.id == m,
      orElse: () => ContentMode.normal,
    );
    if (mode.enabledSources.isNotEmpty) {
      for (final src in mode.enabledSources) {
        if (!mode.disabledSources.contains(src)) {
          return src;
        }
      }
    }
    return 'softkomik';
  }

  static Future<void> setActiveSource(String source, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey(_keyActiveSource, m), source);
  }

  static String getThemeMode() {
    return _settingsBox.get(_keyThemeMode, defaultValue: 'system') as String;
  }

  static Future<void> setThemeMode(String mode) async {
    await _settingsBox.put(_keyThemeMode, mode);
  }

  static String getReaderMode() {
    return _settingsBox.get(_keyReaderMode, defaultValue: 'webtoon') as String;
  }

  static Future<void> setReaderMode(String mode) async {
    await _settingsBox.put(_keyReaderMode, mode);
  }

  static String getReaderCdn() {
    return _settingsBox.get(_keyReaderCdn, defaultValue: 'cdn1') as String;
  }

  static Future<void> setReaderCdn(String cdn) async {
    await _settingsBox.put(_keyReaderCdn, cdn);
  }

  static int getShinigamiServer() {
    return _settingsBox.get(_keyShinigamiSrv, defaultValue: 1) as int;
  }

  static Future<void> setShinigamiServer(int server) async {
    await _settingsBox.put(_keyShinigamiSrv, server);
  }

  static const _keyTapNavigation = 'reader_tap_navigation';

  static bool isTapNavigationEnabled() {
    return _settingsBox.get(_keyTapNavigation, defaultValue: true) as bool;
  }

  static Future<void> setTapNavigationEnabled(bool enabled) async {
    await _settingsBox.put(_keyTapNavigation, enabled);
  }

  static const _keyChapterToast = 'reader_chapter_toast';

  static bool isReaderChapterToastEnabled() {
    return _settingsBox.get(_keyChapterToast, defaultValue: true) as bool;
  }

  static Future<void> setReaderChapterToastEnabled(bool enabled) async {
    await _settingsBox.put(_keyChapterToast, enabled);
  }

  static const _keyPullGesture = 'reader_pull_gesture';

  static bool isPullGestureEnabled() {
    return _settingsBox.get(_keyPullGesture, defaultValue: true) as bool;
  }

  static Future<void> setPullGestureEnabled(bool enabled) async {
    await _settingsBox.put(_keyPullGesture, enabled);
  }

  // --- List Mode & Grid Size Preferences (SharedPreferences backed) ---

  static const String keyListMode = 'manga_list_mode';
  static const String keyGridColumns = 'manga_grid_columns';
  static const String keyFavoritesListMode = 'favorites_list_mode';
  static const String keyFavoritesGridColumns = 'favorites_grid_columns';
  static const String keySourceListMode = 'source_list_mode';
  static const String keySourceGridColumns = 'source_grid_columns';

  // Global / Fallback
  static String getListMode() {
    return _prefs.getString(keyListMode) ??
        (_settingsBox.get(keyListMode, defaultValue: 'grid') as String);
  }

  static Future<void> setListMode(String mode) async {
    await _prefs.setString(keyListMode, mode);
    await _settingsBox.put(keyListMode, mode);
  }

  static int getGridColumns() {
    return _prefs.getInt(keyGridColumns) ??
        (_settingsBox.get(keyGridColumns, defaultValue: 3) as int);
  }

  static Future<void> setGridColumns(int columns) async {
    await _prefs.setInt(keyGridColumns, columns);
    await _settingsBox.put(keyGridColumns, columns);
  }

  // Favorites Screen Preferences (Opsi daftar disukai)
  static String getFavoritesListMode() {
    return _prefs.getString(keyFavoritesListMode) ??
        (_settingsBox.get(keyFavoritesListMode, defaultValue: getListMode()) as String);
  }

  static Future<void> setFavoritesListMode(String mode) async {
    await _prefs.setString(keyFavoritesListMode, mode);
    await _settingsBox.put(keyFavoritesListMode, mode);
  }

  static int getFavoritesGridColumns() {
    return _prefs.getInt(keyFavoritesGridColumns) ??
        (_settingsBox.get(keyFavoritesGridColumns, defaultValue: getGridColumns()) as int);
  }

  static Future<void> setFavoritesGridColumns(int columns) async {
    await _prefs.setInt(keyFavoritesGridColumns, columns);
    await _settingsBox.put(keyFavoritesGridColumns, columns);
  }

  // Source View Screen Preferences (Opsi daftar di source view)
  static String getSourceListMode() {
    return _prefs.getString(keySourceListMode) ??
        (_settingsBox.get(keySourceListMode, defaultValue: getListMode()) as String);
  }

  static Future<void> setSourceListMode(String mode) async {
    await _prefs.setString(keySourceListMode, mode);
    await _settingsBox.put(keySourceListMode, mode);
  }

  static int getSourceGridColumns() {
    return _prefs.getInt(keySourceGridColumns) ??
        (_settingsBox.get(keySourceGridColumns, defaultValue: getGridColumns()) as int);
  }

  static Future<void> setSourceGridColumns(int columns) async {
    await _prefs.setInt(keySourceGridColumns, columns);
    await _settingsBox.put(keySourceGridColumns, columns);
  }

  // Explore Screen Sources Preferences (Opsi daftar untuk source di explore)
  static const String keyExploreSourceListMode = 'explore_source_list_mode';
  static const String keyExploreSourceGridColumns = 'explore_source_grid_columns';

  static String getExploreSourceListMode() {
    return _prefs.getString(keyExploreSourceListMode) ??
        (_settingsBox.get(keyExploreSourceListMode, defaultValue: 'compact') as String);
  }

  static Future<void> setExploreSourceListMode(String mode) async {
    await _prefs.setString(keyExploreSourceListMode, mode);
    await _settingsBox.put(keyExploreSourceListMode, mode);
  }

  static int getExploreSourceGridColumns() {
    return _prefs.getInt(keyExploreSourceGridColumns) ??
        (_settingsBox.get(keyExploreSourceGridColumns, defaultValue: 4) as int);
  }

  static Future<void> setExploreSourceGridColumns(int columns) async {
    await _prefs.setInt(keyExploreSourceGridColumns, columns);
    await _settingsBox.put(keyExploreSourceGridColumns, columns);
  }

  // --- Chapter Sort Order (SharedPreferences backed) ---
  static const String keyChapterSortAscending = 'chapter_sort_asc';

  static bool getChapterSortAscending() {
    return _prefs.getBool(keyChapterSortAscending) ??
        (_settingsBox.get(keyChapterSortAscending, defaultValue: false) as bool);
  }

  static Future<void> setChapterSortAscending(bool ascending) async {
    await _prefs.setBool(keyChapterSortAscending, ascending);
    await _settingsBox.put(keyChapterSortAscending, ascending);
  }

  // --- Chapter Date Format ---
  static const String keyChapterDateFormat = 'chapter_date_format';

  /// Format tanggal bab di Manga Details:
  /// - 'relative_smart' (Default Kotatsu-Redo: waktu relatif untuk bab baru < 7 hari, tanggal untuk bab lama)
  /// - 'relative' (Selalu waktu relatif: misal 2 jam lalu, 3 hari lalu, 2 bulan lalu)
  /// - 'absolute' (Selalu tanggal kalender: misal 15 Oktober 2024)
  /// - 'hidden' (Sembunyikan tanggal bab)
  static String getChapterDateFormat() {
    return _prefs.getString(keyChapterDateFormat) ??
        (_settingsBox.get(keyChapterDateFormat, defaultValue: 'relative_smart') as String);
  }

  static Future<void> setChapterDateFormat(String format) async {
    await _prefs.setString(keyChapterDateFormat, format);
    await _settingsBox.put(keyChapterDateFormat, format);
  }

  // --- Pinned Sources ---

  static List<String> getPinnedSources({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final list = _settingsBox.get(_modeKey('pinned_sources', m));
    if (list is List) {
      return List<String>.from(list);
    }
    return ['komiku', 'shinigami'];
  }

  static Future<void> togglePinSource(String sourceId, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    final pinned = getPinnedSources(modeId: m);
    if (pinned.contains(sourceId)) {
      pinned.remove(sourceId);
    } else {
      pinned.add(sourceId);
    }
    await _settingsBox.put(_modeKey('pinned_sources', m), pinned);
  }

  static bool isSourcePinned(String sourceId, {String? modeId}) {
    return getPinnedSources(modeId: modeId).contains(sourceId);
  }

  // --- Favorites / Library ---

  static ValueListenable<Box> listenFavorites() => _favoritesBox.listenable();

  static List<Map<String, dynamic>> getFavorites({String? category, String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final prefix = '$m::';
    final list = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (var key in _favoritesBox.keys) {
      final keyStr = key.toString();
      if (!keyStr.startsWith(prefix)) continue;
      final subKey = keyStr.substring(prefix.length);
      if (subKey.startsWith('bm_') || subKey.startsWith('tombstone_')) continue;

      final raw = _favoritesBox.get(key);
      if (raw is Map) {
        final item = Map<String, dynamic>.from(raw);
        final itemSource = (item['source'] as String? ?? '').toLowerCase();
        final itemSlug = _cleanSlug(item['slug'] as String? ?? '');
        final dedupeKey = '$itemSource::$itemSlug';
        if (dedupeKey.isNotEmpty && !seen.add(dedupeKey)) {
          continue;
        }

        if (category == null ||
            category == 'Semua' ||
            category == 'Semua kesukaan') {
          list.add(item);
        } else {
          final itemCategories = (item['categories'] is List)
              ? List<String>.from(item['categories'] as List)
              : (item['category'] != null ? [item['category'] as String] : <String>[]);
          if (itemCategories.contains(category) || item['category'] == category) {
            list.add(item);
          }
        }
      }
    }
    // Sort by addedAt descending
    list.sort((a, b) {
      final tA = a['addedAt'] as int? ?? 0;
      final tB = b['addedAt'] as int? ?? 0;
      return tB.compareTo(tA);
    });
    return list;
  }

  /// Returns favorites sorted according to the user's saved sort order (matching FavoritesScreen)
  static List<Map<String, dynamic>> getSortedFavorites({String? category, String? modeId}) {
    final list = getFavorites(category: category, modeId: modeId);
    final sort = getFavoritesSort(modeId: modeId);
    switch (sort) {
      case 'added_asc':
        list.sort((a, b) {
          final tA = a['addedAt'] as int? ?? 0;
          final tB = b['addedAt'] as int? ?? 0;
          return tA.compareTo(tB);
        });
        break;
      case 'title_asc':
        list.sort((a, b) {
          final tA = (a['title'] as String? ?? '').toLowerCase();
          final tB = (b['title'] as String? ?? '').toLowerCase();
          return tA.compareTo(tB);
        });
        break;
      case 'title_desc':
        list.sort((a, b) {
          final tA = (a['title'] as String? ?? '').toLowerCase();
          final tB = (b['title'] as String? ?? '').toLowerCase();
          return tB.compareTo(tA);
        });
        break;
      case 'added_desc':
      default:
        list.sort((a, b) {
          final tA = a['addedAt'] as int? ?? 0;
          final tB = b['addedAt'] as int? ?? 0;
          return tB.compareTo(tA);
        });
        break;
    }
    return list;
  }

  static bool isFavorite(String slug, {String? source, String? modeId}) {
    if (slug.isEmpty) return false;
    final m = modeId ?? getActiveContentModeId();
    final cacheKey = '$m::${source?.toLowerCase() ?? ""}::$slug';
    final cached = _isFavoriteCache[cacheKey];
    if (cached != null) return cached;

    final entry = getFavorite(slug, source: source, modeId: m);
    final res = entry != null;
    _isFavoriteCache[cacheKey] = res;
    return res;
  }

  static Map<String, dynamic>? getFavorite(String slug, {String? source, String? modeId}) {
    if (slug.isEmpty) return null;
    final m = modeId ?? getActiveContentModeId();
    final cacheKey = '$m::${source?.toLowerCase() ?? ""}::$slug';
    if (_favoriteEntryCache.containsKey(cacheKey)) {
      return _favoriteEntryCache[cacheKey];
    }

    final clean = _cleanSlug(slug);
    final src = (source != null && source.trim().isNotEmpty) ? source.trim().toLowerCase() : null;

    Map<String, dynamic>? foundEntry;

    // 1. If source is specified, check source-scoped keys first
    if (src != null) {
      var raw = _favoritesBox.get('$m::$src::$slug');
      if (raw == null && clean.isNotEmpty) {
        raw = _favoritesBox.get('$m::$src::$clean') ??
            _favoritesBox.get('$m::$src::manga/$clean');
      }
      if (raw is Map) {
        foundEntry = Map<String, dynamic>.from(raw);
        _favoriteEntryCache[cacheKey] = foundEntry;
        _isFavoriteCache[cacheKey] = true;
        return foundEntry;
      }

      // Check all keys matching this source if direct lookup didn't match
      final prefix = '$m::$src::';
      for (final key in _favoritesBox.keys) {
        final keyStr = key.toString();
        if (!keyStr.startsWith(prefix)) continue;
        final subKey = keyStr.substring(prefix.length);
        if (subKey.startsWith('bm_') || subKey.startsWith('tombstone_')) continue;
        if (subKey == slug || (clean.isNotEmpty && _cleanSlug(subKey) == clean)) {
          final entry = _favoritesBox.get(key);
          if (entry is Map) {
            foundEntry = Map<String, dynamic>.from(entry);
            _favoriteEntryCache[cacheKey] = foundEntry;
            _isFavoriteCache[cacheKey] = true;
            return foundEntry;
          }
        }
      }
    }

    // 2. Check legacy un-scoped keys ($m::$slug, $m::$clean)
    var legacyRaw = _favoritesBox.get('$m::$slug');
    if (legacyRaw == null && clean.isNotEmpty) {
      legacyRaw = _favoritesBox.get('$m::$clean') ??
          _favoritesBox.get('$m::manga/$clean');
    }
    if (legacyRaw is Map) {
      final map = Map<String, dynamic>.from(legacyRaw);
      // If caller specified a source, legacy entry must match that source!
      if (src == null || (map['source'] as String?)?.toLowerCase() == src) {
        foundEntry = map;
        _favoriteEntryCache[cacheKey] = foundEntry;
        _isFavoriteCache[cacheKey] = true;
        return foundEntry;
      }
    }

    // 3. If source was NOT specified, look for any source-scoped key matching this slug
    if (src == null) {
      final prefix = '$m::';
      for (final key in _favoritesBox.keys) {
        final keyStr = key.toString();
        if (!keyStr.startsWith(prefix)) continue;
        final subKey = keyStr.substring(prefix.length);
        if (subKey.startsWith('bm_') || subKey.startsWith('tombstone_')) continue;
        final parts = subKey.split('::');
        if (parts.length >= 2) {
          final keySlug = parts.sublist(1).join('::');
          if (keySlug == slug || (clean.isNotEmpty && _cleanSlug(keySlug) == clean)) {
            final raw = _favoritesBox.get(key);
            if (raw is Map) {
              foundEntry = Map<String, dynamic>.from(raw);
              _favoriteEntryCache[cacheKey] = foundEntry;
              _isFavoriteCache[cacheKey] = true;
              return foundEntry;
            }
          }
        }
      }
    }

    // 4. Fallback: if caller specified a source but no exact match was found,
    // check if this slug exists in favorites under the same source title/name or un-scoped
    if (src != null) {
      final fallback = getFavorite(slug, source: null, modeId: m);
      if (fallback != null) {
        final itemSrc = (fallback['source'] as String?)?.trim().toLowerCase();
        if (itemSrc == null || itemSrc.isEmpty || itemSrc == src) {
          foundEntry = fallback;
          _favoriteEntryCache[cacheKey] = foundEntry;
          _isFavoriteCache[cacheKey] = true;
          return foundEntry;
        }
      }
    }

    _favoriteEntryCache[cacheKey] = null;
    _isFavoriteCache[cacheKey] = false;
    return null;
  }

  static String? getFavoriteCategory(String slug, {String? source, String? modeId}) {
    final raw = getFavorite(slug, source: source, modeId: modeId);
    if (raw != null) {
      if (raw['category'] != null) {
        return raw['category'] as String?;
      }
      if (raw['categories'] is List && (raw['categories'] as List).isNotEmpty) {
        return (raw['categories'] as List).first as String?;
      }
    }
    return null;
  }

  static List<String> getFavoriteCategoriesForSlug(String slug, {String? source, String? modeId}) {
    final raw = getFavorite(slug, source: source, modeId: modeId);
    if (raw != null) {
      if (raw['categories'] is List) {
        return List<String>.from(raw['categories'] as List);
      }
      if (raw['category'] != null) {
        final c = raw['category'] as String;
        if (c.isNotEmpty && c != 'Semua' && c != 'Semua kesukaan') {
          return [c];
        }
      }
    }
    return [];
  }

  static Future<void> saveFavorite({
    required String slug,
    required String title,
    required String? cover,
    required String source,
    String? category,
    List<String>? categories,
    String? type,
    String? latestChapter,
    int? addedAt,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final src = source.trim().toLowerCase();
    final catList = categories ?? (category != null && category != 'Semua' && category != 'Semua kesukaan' ? [category] : <String>[]);
    final primaryCat = catList.isNotEmpty
        ? catList.first
        : (category != null && category != 'Semua' && category != 'Semua kesukaan' ? category : '');

    // Preserve existing addedAt if explicitly passed or already favorite
    int resolvedAddedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;
    final existing = getFavorite(slug, source: src, modeId: m);
    if (addedAt == null && existing != null && existing['addedAt'] is int) {
      resolvedAddedAt = existing['addedAt'] as int;
    }

    String? resolvedCover = (cover != null && cover.trim().isNotEmpty) ? cover.trim() : null;
    if (resolvedCover == null && existing != null) {
      final exCover = existing['cover'] as String?;
      if (exCover != null && exCover.trim().isNotEmpty) {
        resolvedCover = exCover.trim();
      }
    }

    String resolvedTitle = title.trim();
    if ((resolvedTitle.isEmpty || resolvedTitle == slug) && existing != null) {
      final exTitle = existing['title'] as String?;
      if (exTitle != null && exTitle.trim().isNotEmpty && exTitle.trim() != slug) {
        resolvedTitle = exTitle.trim();
      }
    }

    final key = src.isNotEmpty ? '$m::$src::$slug' : '$m::$slug';
    await _favoritesBox.put(key, {
      'mode_id': m,
      'slug': slug,
      'title': resolvedTitle.isNotEmpty ? resolvedTitle : title,
      'cover': resolvedCover,
      'source': source.trim(),
      'category': primaryCat,
      'categories': catList,
      'type': type ?? existing?['type'],
      'latestChapter': latestChapter ?? existing?['latestChapter'],
      'addedAt': resolvedAddedAt,
    });

    await removeDeletedFavoriteTombstone(slug, source: source, modeId: m);

    // Cleanup legacy un-scoped key if it belonged to this source
    final clean = _cleanSlug(slug);
    for (final legacyKey in ['$m::$slug', if (clean.isNotEmpty) '$m::$clean']) {
      if (_favoritesBox.containsKey(legacyKey)) {
        final oldVal = _favoritesBox.get(legacyKey);
        if (oldVal is Map && (oldVal['source'] as String?)?.toLowerCase() == src) {
          await _favoritesBox.delete(legacyKey);
        }
      }
    }

    if (resolvedCover != null && resolvedCover.isNotEmpty) {
      ensureCoverCached(slug: slug, coverUrl: resolvedCover, source: source);
    }
  }

  /// Updates metadata (title, cover, type, latestChapter) of an existing favorite item without modifying categories
  static Future<void> updateFavoriteMetadata({
    required String slug,
    String? source,
    String? title,
    String? cover,
    String? type,
    String? latestChapter,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final clean = _cleanSlug(slug);
    final src = source?.trim().toLowerCase();

    String? key;
    if (src != null && src.isNotEmpty) {
      if (_favoritesBox.containsKey('$m::$src::$slug')) {
        key = '$m::$src::$slug';
      } else if (clean.isNotEmpty && _favoritesBox.containsKey('$m::$src::$clean')) {
        key = '$m::$src::$clean';
      }
    }

    if (key == null) {
      if (_favoritesBox.containsKey('$m::$slug')) {
        final val = _favoritesBox.get('$m::$slug');
        if (src == null || (val is Map && (val['source'] as String?)?.toLowerCase() == src)) {
          key = '$m::$slug';
        }
      } else if (clean.isNotEmpty && _favoritesBox.containsKey('$m::$clean')) {
        final val = _favoritesBox.get('$m::$clean');
        if (src == null || (val is Map && (val['source'] as String?)?.toLowerCase() == src)) {
          key = '$m::$clean';
        }
      }
    }

    if (key == null) {
      final prefix = '$m::';
      for (final k in _favoritesBox.keys) {
        final kStr = k.toString();
        if (!kStr.startsWith(prefix)) continue;
        final subKey = kStr.substring(prefix.length);
        if (subKey.startsWith('bm_') || subKey.startsWith('tombstone_')) continue;
        final parts = subKey.split('::');
        final keySlug = parts.length >= 2 ? parts.sublist(1).join('::') : subKey;
        final keySource = parts.length >= 2 ? parts[0] : null;
        if (src != null && keySource != null && keySource != src) continue;
        if (keySlug == slug || (clean.isNotEmpty && _cleanSlug(keySlug) == clean)) {
          key = kStr;
          break;
        }
      }
    }

    if (key == null) return;
    final raw = _favoritesBox.get(key);
    if (raw is Map) {
      final item = Map<String, dynamic>.from(raw);
      bool changed = false;
      if (title != null && title.trim().isNotEmpty && title.trim() != slug && item['title'] != title.trim()) {
        item['title'] = title.trim();
        changed = true;
      }
      if (cover != null && cover.trim().isNotEmpty && item['cover'] != cover.trim()) {
        item['cover'] = cover.trim();
        changed = true;
      }
      if (type != null && type.trim().isNotEmpty && item['type'] != type.trim()) {
        item['type'] = type.trim();
        changed = true;
      }
      if (latestChapter != null && latestChapter.trim().isNotEmpty && item['latestChapter'] != latestChapter.trim()) {
        item['latestChapter'] = latestChapter.trim();
        changed = true;
      }
      if (changed) {
        await _favoritesBox.put(key, item);
      }
    }

    if (cover != null && cover.trim().isNotEmpty) {
      ensureCoverCached(slug: slug, coverUrl: cover.trim(), source: source);
    }
  }

  static Future<void> removeFavorite(
    String slug, {
    String? source,
    bool recordTombstone = true,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final src = source?.trim().toLowerCase();
    final item = getFavorite(slug, source: src, modeId: m);
    if (recordTombstone) {
      if (item != null) {
        final catList = (item['categories'] as List?)?.map((e) => e.toString()).toList();
        final primaryCat = item['category']?.toString();
        await recordDeletedFavoriteTombstone(
          slug,
          title: item['title'] as String?,
          source: item['source'] as String? ?? source,
          categories: catList,
          category: primaryCat,
          modeId: m,
        );
      } else {
        await recordDeletedFavoriteTombstone(slug, source: source, modeId: m);
      }
    }

    final clean = _cleanSlug(slug);
    if (src != null && src.isNotEmpty) {
      await _favoritesBox.delete('$m::$src::$slug');
      if (clean.isNotEmpty) {
        await _favoritesBox.delete('$m::$src::$clean');
        await _favoritesBox.delete('$m::$src::manga/$clean');
        await _favoritesBox.delete('$m::$src::/manga/$clean');
      }
      // Also delete legacy un-scoped key if it matches this source
      final oldRaw = _favoritesBox.get('$m::$slug');
      if (oldRaw is Map && (oldRaw['source'] as String?)?.toLowerCase() == src) {
        await _favoritesBox.delete('$m::$slug');
      }
      if (clean.isNotEmpty) {
        final cleanRaw = _favoritesBox.get('$m::$clean');
        if (cleanRaw is Map && (cleanRaw['source'] as String?)?.toLowerCase() == src) {
          await _favoritesBox.delete('$m::$clean');
        }
      }
    } else {
      await _favoritesBox.delete('$m::$slug');
      if (clean.isNotEmpty) {
        await _favoritesBox.delete('$m::$clean');
        await _favoritesBox.delete('$m::manga/$clean');
        await _favoritesBox.delete('$m::/manga/$clean');
      }
      // Delete any source-scoped key for this slug
      final prefix = '$m::';
      final toDelete = <dynamic>[];
      for (final k in _favoritesBox.keys) {
        final kStr = k.toString();
        if (!kStr.startsWith(prefix)) continue;
        final sub = kStr.substring(prefix.length);
        if (sub.endsWith('::$slug') || (clean.isNotEmpty && sub.endsWith('::$clean'))) {
          toDelete.add(k);
        }
      }
      for (final k in toDelete) {
        await _favoritesBox.delete(k);
      }
    }
  }

  static Future<void> clearFavoritesDirect({String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    final prefix = '$m::';
    final keys = _favoritesBox.keys.where((k) {
      final s = k.toString();
      return s.startsWith(prefix) && !s.substring(prefix.length).startsWith('bm_');
    }).toList();
    for (final k in keys) {
      await _favoritesBox.delete(k);
    }
  }

  static Future<void> clearFavorites({String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    final all = getFavorites(modeId: m);
    for (final f in all) {
      final slug = f['slug'] as String? ?? '';
      if (slug.isNotEmpty) {
        final catList = (f['categories'] as List?)?.map((e) => e.toString()).toList();
        final primaryCat = f['category']?.toString();
        await recordDeletedFavoriteTombstone(
          slug,
          title: f['title'] as String?,
          source: f['source'] as String?,
          categories: catList,
          category: primaryCat,
          modeId: m,
        );
      }
    }
    await clearFavoritesDirect(modeId: m);
  }

  // --- Favorite Categories & Sort ---

  static const List<String> defaultFavoriteCategories = [];

  static List<String> getFavoriteCategories({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final raw = _settingsBox.get(_modeKey('favorite_categories', m));
    if (raw is List) {
      final list = raw
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty && s != 'Semua' && s != 'Semua kesukaan')
          .toList();
      return list;
    }
    return <String>[];
  }

  static Future<void> saveFavoriteCategories(List<String> categories, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('favorite_categories', m), categories);
  }

  static Future<void> addFavoriteCategory(String name, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    final list = getFavoriteCategories(modeId: m);
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        list.contains(trimmed) ||
        trimmed == 'Semua' ||
        trimmed == 'Semua kesukaan') {
      return;
    }
    list.add(trimmed);
    await saveFavoriteCategories(list, modeId: m);
  }

  static Future<void> renameFavoriteCategory(String oldName, String newName, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    final trimmed = newName.trim();
    if (trimmed.isEmpty ||
        oldName == trimmed ||
        trimmed == 'Semua' ||
        trimmed == 'Semua kesukaan') {
      return;
    }
    final list = getFavoriteCategories(modeId: m);
    final idx = list.indexOf(oldName);
    if (idx != -1) {
      list[idx] = trimmed;
      await saveFavoriteCategories(list, modeId: m);
    }
    // Copy category settings/meta
    final meta = getCategoryDetails(oldName, modeId: m);
    await saveCategoryDetails(trimmed,
      sort: meta['sort'] as String?,
      checkNewChapters: meta['checkNewChapters'] as bool?,
      showOnShelf: meta['showOnShelf'] as bool?,
      modeId: m,
    );
    await _settingsBox.delete(_modeKey('cat_meta_$oldName', m));

    final prefix = '$m::';
    for (var key in _favoritesBox.keys) {
      if (!key.toString().startsWith(prefix)) continue;
      final raw = _favoritesBox.get(key);
      if (raw is Map) {
        final item = Map<String, dynamic>.from(raw);
        bool changed = false;
        if (item['category'] == oldName) {
          item['category'] = trimmed;
          changed = true;
        }
        if (item['categories'] is List) {
          final cats = List<String>.from(item['categories'] as List);
          final cIdx = cats.indexOf(oldName);
          if (cIdx != -1) {
            cats[cIdx] = trimmed;
            item['categories'] = cats;
            changed = true;
          }
        }
        if (changed) {
          await _favoritesBox.put(key, item);
        }
      }
    }
  }

  static Future<void> reorderFavoriteCategories(int oldIndex, int newIndex, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    final list = getFavoriteCategories(modeId: m);
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex < 0) newIndex = 0;
    if (newIndex >= list.length) newIndex = list.length - 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    await saveFavoriteCategories(list, modeId: m);
  }

  static Future<void> deleteFavoriteCategory(String name, {String? modeId, bool recordTombstone = true}) async {
    final m = modeId ?? getActiveContentModeId();
    final list = getFavoriteCategories(modeId: m);
    list.remove(name);
    await saveFavoriteCategories(list, modeId: m);
    await _settingsBox.delete(_modeKey('cat_meta_$name', m));

    // Simpan tombstone kategori yang dihapus untuk sinkronisasi server
    if (recordTombstone) {
      final syncCatIds = getSyncCategoryIds(modeId: m);
      final catId = syncCatIds[name];
      await recordDeletedCategoryTombstone(name, categoryId: catId, modeId: m);
      if (syncCatIds.containsKey(name)) {
        syncCatIds.remove(name);
        await saveSyncCategoryIds(syncCatIds, modeId: m);
      }
    }

    final prefix = '$m::';
    for (var key in _favoritesBox.keys) {
      if (!key.toString().startsWith(prefix)) continue;
      final raw = _favoritesBox.get(key);
      if (raw is Map) {
        final item = Map<String, dynamic>.from(raw);
        bool changed = false;

        List<String> cats = [];
        if (item['categories'] is List) {
          cats = List<String>.from(item['categories'] as List);
          if (cats.remove(name)) {
            item['categories'] = cats;
            changed = true;
          }
        }

        if (item['category'] == name) {
          item['category'] = cats.isNotEmpty ? cats.first : null;
          changed = true;
        }

        if (changed) {
          await _favoritesBox.put(key, item);
        }
      }
    }
    notifyContentModeChanged();
  }

  static Map<String, dynamic> getCategoryDetails(String name, {String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final raw = _settingsBox.get(_modeKey('cat_meta_$name', m));
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {
      'sort': 'Ditambahkan',
      'checkNewChapters': true,
      'showOnShelf': true,
    };
  }

  static Future<void> saveCategoryDetails(String name, {
    String? sort,
    bool? checkNewChapters,
    bool? showOnShelf,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final current = getCategoryDetails(name, modeId: m);
    if (sort != null) current['sort'] = sort;
    if (checkNewChapters != null) current['checkNewChapters'] = checkNewChapters;
    if (showOnShelf != null) current['showOnShelf'] = showOnShelf;
    await _settingsBox.put(_modeKey('cat_meta_$name', m), current);
  }

  static bool isAllFavoritesVisible({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('all_favorites_visible', m), defaultValue: true) as bool;
  }

  static Future<void> setAllFavoritesVisible(bool visible, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('all_favorites_visible', m), visible);
  }

  static Future<void> updateFavoriteCategory(
    String slug,
    String newCategory, {
    String? source,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final clean = _cleanSlug(slug);
    final src = source?.trim().toLowerCase();

    String? key;
    if (src != null && src.isNotEmpty) {
      if (_favoritesBox.containsKey('$m::$src::$slug')) {
        key = '$m::$src::$slug';
      } else if (clean.isNotEmpty && _favoritesBox.containsKey('$m::$src::$clean')) {
        key = '$m::$src::$clean';
      }
    }
    if (key == null) {
      if (_favoritesBox.containsKey('$m::$slug')) {
        final val = _favoritesBox.get('$m::$slug');
        if (src == null || (val is Map && (val['source'] as String?)?.toLowerCase() == src)) {
          key = '$m::$slug';
        }
      } else if (clean.isNotEmpty && _favoritesBox.containsKey('$m::$clean')) {
        final val = _favoritesBox.get('$m::$clean');
        if (src == null || (val is Map && (val['source'] as String?)?.toLowerCase() == src)) {
          key = '$m::$clean';
        }
      }
    }

    if (key == null) {
      final prefix = '$m::';
      for (final k in _favoritesBox.keys) {
        final kStr = k.toString();
        if (!kStr.startsWith(prefix)) continue;
        final subKey = kStr.substring(prefix.length);
        if (subKey.startsWith('bm_') || subKey.startsWith('tombstone_')) continue;
        final parts = subKey.split('::');
        final keySlug = parts.length >= 2 ? parts.sublist(1).join('::') : subKey;
        final keySource = parts.length >= 2 ? parts[0] : null;
        if (src != null && keySource != null && keySource != src) continue;
        if (keySlug == slug || (clean.isNotEmpty && _cleanSlug(keySlug) == clean)) {
          key = kStr;
          break;
        }
      }
    }
    if (key == null) return;
    final raw = _favoritesBox.get(key);
    if (raw is Map) {
      final item = Map<String, dynamic>.from(raw);
      item['category'] = newCategory;
      if (newCategory == 'Semua kesukaan' || newCategory == 'Semua') {
        item['categories'] = <String>[];
      } else {
        item['categories'] = [newCategory];
      }
      await _favoritesBox.put(key, item);
    }
  }

  static Future<void> updateFavoriteCategories(
    String slug,
    List<String> categories, {
    String? source,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final clean = _cleanSlug(slug);
    final src = source?.trim().toLowerCase();

    String? key;
    if (src != null && src.isNotEmpty) {
      if (_favoritesBox.containsKey('$m::$src::$slug')) {
        key = '$m::$src::$slug';
      } else if (clean.isNotEmpty && _favoritesBox.containsKey('$m::$src::$clean')) {
        key = '$m::$src::$clean';
      }
    }
    if (key == null) {
      if (_favoritesBox.containsKey('$m::$slug')) {
        final val = _favoritesBox.get('$m::$slug');
        if (src == null || (val is Map && (val['source'] as String?)?.toLowerCase() == src)) {
          key = '$m::$slug';
        }
      } else if (clean.isNotEmpty && _favoritesBox.containsKey('$m::$clean')) {
        final val = _favoritesBox.get('$m::$clean');
        if (src == null || (val is Map && (val['source'] as String?)?.toLowerCase() == src)) {
          key = '$m::$clean';
        }
      }
    }

    if (key == null) {
      final prefix = '$m::';
      for (final k in _favoritesBox.keys) {
        final kStr = k.toString();
        if (!kStr.startsWith(prefix)) continue;
        final subKey = kStr.substring(prefix.length);
        if (subKey.startsWith('bm_') || subKey.startsWith('tombstone_')) continue;
        final parts = subKey.split('::');
        final keySlug = parts.length >= 2 ? parts.sublist(1).join('::') : subKey;
        final keySource = parts.length >= 2 ? parts[0] : null;
        if (src != null && keySource != null && keySource != src) continue;
        if (keySlug == slug || (clean.isNotEmpty && _cleanSlug(keySlug) == clean)) {
          key = kStr;
          break;
        }
      }
    }
    if (key == null) return;
    final raw = _favoritesBox.get(key);
    if (raw is Map) {
      final item = Map<String, dynamic>.from(raw);
      item['categories'] = categories;
      item['category'] = categories.isNotEmpty ? categories.first : '';
      await _favoritesBox.put(key, item);
    }
  }

  static String getFavoritesSort({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('favorites_sort_order', m), defaultValue: 'added_desc') as String;
  }

  static Future<void> setFavoritesSort(String sort, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('favorites_sort_order', m), sort);
  }

  static String getHistorySort({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('history_sort_order', m), defaultValue: 'last_read') as String;
  }

  static Future<void> setHistorySort(String sort, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('history_sort_order', m), sort);
  }

  static bool isHistoryGroupingEnabled({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('history_grouping_enabled', m), defaultValue: true) as bool;
  }

  static Future<void> setHistoryGroupingEnabled(bool enabled, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('history_grouping_enabled', m), enabled);
  }

  // --- Bookmarks ---
  static bool isBookmarked(String slug, String chapter, {String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final cleanSlug = chapter.trim();
    return _favoritesBox.containsKey('$m::bm_${slug}_$cleanSlug');
  }

  static Future<bool> toggleBookmark({
    required String slug,
    required String mangaTitle,
    required String chapterSlug,
    required String chapterTitle,
    required int page,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final cleanSlug = chapterSlug.trim();
    final key = '$m::bm_${slug}_$cleanSlug';
    if (_favoritesBox.containsKey(key)) {
      await _favoritesBox.delete(key);
      return false;
    } else {
      await _favoritesBox.put(key, {
        'mode_id': m,
        'slug': slug,
        'mangaTitle': mangaTitle,
        'chapterSlug': cleanSlug,
        'chapterTitle': chapterTitle,
        'page': page,
        'date': DateTime.now().toIso8601String(),
      });
      return true;
    }
  }

  static List<Map<String, dynamic>> getAllBookmarks({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final prefix = '$m::bm_';
    final list = <Map<String, dynamic>>[];
    for (final key in _favoritesBox.keys) {
      if (key.toString().startsWith(prefix)) {
        final val = _favoritesBox.get(key);
        if (val is Map) {
          list.add(Map<String, dynamic>.from(val));
        }
      }
    }
    return list;
  }

  static Future<void> saveBookmark({
    required String slug,
    required String mangaTitle,
    required String chapterSlug,
    required String chapterTitle,
    required int page,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final cleanSlug = chapterSlug.trim();
    final key = '$m::bm_${slug}_$cleanSlug';
    await _favoritesBox.put(key, {
      'mode_id': m,
      'slug': slug,
      'mangaTitle': mangaTitle,
      'chapterSlug': cleanSlug,
      'chapterTitle': chapterTitle,
      'page': page,
      'date': DateTime.now().toIso8601String(),
    });
  }

  // --- Reading History ---

  static ValueListenable<Box> listenHistory() => _historyBox.listenable();

  static List<Map<String, dynamic>> getHistory({String? sortOrder, String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final prefix = '$m::';
    final sort = sortOrder ?? getHistorySort(modeId: m);
    final list = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (var key in _historyBox.keys) {
      final keyStr = key.toString();
      if (!keyStr.startsWith(prefix)) continue;
      final subKey = keyStr.substring(prefix.length);
      if (subKey.startsWith('read_') || subKey.startsWith('tombstone_')) continue;
      final raw = _historyBox.get(key);
      if (raw is Map) {
        final item = Map<String, dynamic>.from(raw);
        final itemSource = (item['source'] as String? ?? '').toLowerCase();
        final itemSlug = _cleanSlug(item['slug'] as String? ?? '');
        final dedupeKey = '$itemSource::$itemSlug';
        if (dedupeKey.isNotEmpty && !seen.add(dedupeKey)) {
          continue;
        }
        list.add(item);
      }
    }
    list.sort((a, b) {
      switch (sort) {
        case 'long_ago_read':
          final tA = a['updatedAt'] as int? ?? 0;
          final tB = b['updatedAt'] as int? ?? 0;
          return tA.compareTo(tB);
        case 'newest':
          final tA = a['createdAt'] as int? ?? a['updatedAt'] as int? ?? 0;
          final tB = b['createdAt'] as int? ?? b['updatedAt'] as int? ?? 0;
          return tB.compareTo(tA);
        case 'oldest':
          final tA = a['createdAt'] as int? ?? a['updatedAt'] as int? ?? 0;
          final tB = b['createdAt'] as int? ?? b['updatedAt'] as int? ?? 0;
          return tA.compareTo(tB);
        case 'progress':
          final pA = (a['percent'] as num?)?.toDouble() ?? 0.0;
          final pB = (b['percent'] as num?)?.toDouble() ?? 0.0;
          return pB.compareTo(pA);
        case 'unread':
          final pA = (a['percent'] as num?)?.toDouble() ?? 0.0;
          final pB = (b['percent'] as num?)?.toDouble() ?? 0.0;
          return pA.compareTo(pB);
        case 'title_asc':
          final titleA = (a['title'] as String? ?? '').toLowerCase();
          final titleB = (b['title'] as String? ?? '').toLowerCase();
          return titleA.compareTo(titleB);
        case 'title_desc':
          final titleA = (a['title'] as String? ?? '').toLowerCase();
          final titleB = (b['title'] as String? ?? '').toLowerCase();
          return titleB.compareTo(titleA);
        case 'last_read':
        default:
          final tA = a['updatedAt'] as int? ?? 0;
          final tB = b['updatedAt'] as int? ?? 0;
          return tB.compareTo(tA);
      }
    });
    return list;
  }

  static List<String> getReadChapters(String mangaSlug, {String? source, String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final clean = _cleanSlug(mangaSlug);
    final src = source?.trim().toLowerCase();
    final result = <String>{};

    if (src != null && src.isNotEmpty) {
      final raw1 = _historyBox.get('$m::read_${src}_$mangaSlug');
      if (raw1 is List) {
        result.addAll(raw1.map((e) => e.toString()));
      }
      if (clean.isNotEmpty && clean != mangaSlug) {
        final raw2 = _historyBox.get('$m::read_${src}_$clean');
        if (raw2 is List) {
          result.addAll(raw2.map((e) => e.toString()));
        }
      }
    }

    final rawLegacy1 = _historyBox.get('$m::read_$mangaSlug');
    if (rawLegacy1 is List) {
      result.addAll(rawLegacy1.map((e) => e.toString()));
    }
    if (clean.isNotEmpty && clean != mangaSlug) {
      final rawLegacy2 = _historyBox.get('$m::read_$clean');
      if (rawLegacy2 is List) {
        result.addAll(rawLegacy2.map((e) => e.toString()));
      }
    }

    if (result.isEmpty && (src == null || src.isEmpty)) {
      final prefix = '$m::read_';
      for (final key in _historyBox.keys) {
        final keyStr = key.toString();
        if (!keyStr.startsWith(prefix)) continue;
        final sub = keyStr.substring(prefix.length);
        if (sub == mangaSlug ||
            (clean.isNotEmpty && sub == clean) ||
            sub.endsWith('_$mangaSlug') ||
            (clean.isNotEmpty && sub.endsWith('_$clean'))) {
          final raw = _historyBox.get(key);
          if (raw is List) {
            result.addAll(raw.map((e) => e.toString()));
          }
        }
      }
    }
    return result.toList();
  }

  static Future<void> markChapterAsRead(String mangaSlug, String chapterSlug, {String? source, String? modeId}) async {
    await markChaptersAsRead(mangaSlug, [chapterSlug], source: source, modeId: modeId);
  }

  static Future<void> markChaptersAsRead(
    String mangaSlug,
    Iterable<String> chapterSlugs, {
    String? source,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final cleanManga = _cleanSlug(mangaSlug);
    final src = source?.trim().toLowerCase();
    final current = getReadChapters(mangaSlug, source: src, modeId: m).toSet();
    for (final s in chapterSlugs) {
      final clean = s.trim();
      if (clean.isNotEmpty) {
        current.add(clean);
        final cleanTrimmed = clean.replaceAll(RegExp(r'^/+|/+$'), '');
        if (cleanTrimmed.isNotEmpty) {
          current.add(cleanTrimmed);
        }
      }
    }
    if (src != null && src.isNotEmpty) {
      await _historyBox.put('$m::read_${src}_$mangaSlug', current.toList());
      if (cleanManga.isNotEmpty && cleanManga != mangaSlug) {
        await _historyBox.put('$m::read_${src}_$cleanManga', current.toList());
      }
    } else {
      await _historyBox.put('$m::read_$mangaSlug', current.toList());
      if (cleanManga.isNotEmpty && cleanManga != mangaSlug) {
        await _historyBox.put('$m::read_$cleanManga', current.toList());
      }
    }
    await syncFeedItemsReadStatus(slug: mangaSlug, source: src, modeId: m);
  }

  static Future<void> markChaptersAsUnread(
    String mangaSlug,
    Iterable<String> chapterSlugs, {
    String? source,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final cleanManga = _cleanSlug(mangaSlug);
    final src = source?.trim().toLowerCase();
    final current = getReadChapters(mangaSlug, source: src, modeId: m).toSet();
    for (final s in chapterSlugs) {
      final clean = s.trim();
      if (clean.isNotEmpty) {
        current.remove(clean);
        final cleanTrimmed = clean.replaceAll(RegExp(r'^/+|/+$'), '');
        if (cleanTrimmed.isNotEmpty) {
          current.remove(cleanTrimmed);
        }
      }
    }
    if (src != null && src.isNotEmpty) {
      await _historyBox.put('$m::read_${src}_$mangaSlug', current.toList());
      if (cleanManga.isNotEmpty && cleanManga != mangaSlug) {
        await _historyBox.put('$m::read_${src}_$cleanManga', current.toList());
      }
    } else {
      await _historyBox.put('$m::read_$mangaSlug', current.toList());
      if (cleanManga.isNotEmpty && cleanManga != mangaSlug) {
        await _historyBox.put('$m::read_$cleanManga', current.toList());
      }
    }
    await syncFeedItemsReadStatus(slug: mangaSlug, source: src, modeId: m);
  }

  /// Sets read chapters up to a given point: adds [readSlugs] and removes [unreadSlugs].
  static Future<void> setReadChaptersUpTo({
    required String mangaSlug,
    required Iterable<String> readSlugs,
    required Iterable<String> unreadSlugs,
    String? source,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final cleanManga = _cleanSlug(mangaSlug);
    final src = source?.trim().toLowerCase();
    final current = getReadChapters(mangaSlug, source: src, modeId: m).toSet();
    for (final s in readSlugs) {
      final clean = s.trim();
      if (clean.isNotEmpty) {
        current.add(clean);
        final cleanTrimmed = clean.replaceAll(RegExp(r'^/+|/+$'), '');
        if (cleanTrimmed.isNotEmpty) {
          current.add(cleanTrimmed);
        }
      }
    }
    for (final s in unreadSlugs) {
      final clean = s.trim();
      if (clean.isNotEmpty) {
        current.remove(clean);
        final cleanTrimmed = clean.replaceAll(RegExp(r'^/+|/+$'), '');
        if (cleanTrimmed.isNotEmpty) {
          current.remove(cleanTrimmed);
        }
      }
    }
    if (src != null && src.isNotEmpty) {
      await _historyBox.put('$m::read_${src}_$mangaSlug', current.toList());
      if (cleanManga.isNotEmpty && cleanManga != mangaSlug) {
        await _historyBox.put('$m::read_${src}_$cleanManga', current.toList());
      }
    } else {
      await _historyBox.put('$m::read_$mangaSlug', current.toList());
      if (cleanManga.isNotEmpty && cleanManga != mangaSlug) {
        await _historyBox.put('$m::read_$cleanManga', current.toList());
      }
    }
    await syncFeedItemsReadStatus(slug: mangaSlug, source: src, modeId: m);
  }

  static Future<void> clearReadChapters(
    String mangaSlug, {
    String? source,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final cleanManga = _cleanSlug(mangaSlug);
    final src = source?.trim().toLowerCase();

    if (src != null && src.isNotEmpty) {
      await _historyBox.delete('$m::read_${src}_$mangaSlug');
      if (cleanManga.isNotEmpty) {
        await _historyBox.delete('$m::read_${src}_$cleanManga');
        await _historyBox.delete('$m::read_${src}_manga/$cleanManga');
        await _historyBox.delete('$m::read_${src}_/manga/$cleanManga');
      }
    }

    await _historyBox.delete('$m::read_$mangaSlug');
    if (cleanManga.isNotEmpty) {
      await _historyBox.delete('$m::read_$cleanManga');
      await _historyBox.delete('$m::read_manga/$cleanManga');
      await _historyBox.delete('$m::read_/manga/$cleanManga');
    }

    final prefix = '$m::read_';
    final toDelete = <dynamic>[];
    for (final k in _historyBox.keys) {
      final kStr = k.toString();
      if (!kStr.startsWith(prefix)) continue;
      final sub = kStr.substring(prefix.length);
      if (src != null && src.isNotEmpty && !sub.startsWith('${src}_')) continue;
      if (sub.endsWith('_$mangaSlug') || (cleanManga.isNotEmpty && sub.endsWith('_$cleanManga'))) {
        toDelete.add(k);
      }
    }
    for (final k in toDelete) {
      await _historyBox.delete(k);
    }
    await syncFeedItemsReadStatus(slug: mangaSlug, source: src, modeId: m);
  }

  static Map<String, dynamic>? getHistoryItem(String slug, {String? source, String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final clean = _cleanSlug(slug);
    final src = (source != null && source.trim().isNotEmpty) ? source.trim().toLowerCase() : null;

    final candidates = <Map<String, dynamic>>[];
    void checkKey(String k) {
      final raw = _historyBox.get(k);
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        if (src == null || (map['source'] as String?)?.toLowerCase() == src) {
          candidates.add(map);
        }
      }
    }

    if (src != null) {
      checkKey('$m::$src::$slug');
      if (clean.isNotEmpty && clean != slug) {
        checkKey('$m::$src::$clean');
        checkKey('$m::$src::manga/$clean');
      } else if (clean.isNotEmpty) {
        checkKey('$m::$src::manga/$clean');
      }
    }

    // Check legacy un-scoped key with source match
    checkKey('$m::$slug');
    if (clean.isNotEmpty && clean != slug) {
      checkKey('$m::$clean');
      checkKey('$m::manga/$clean');
    } else if (clean.isNotEmpty) {
      checkKey('$m::manga/$clean');
    }

    if (candidates.isEmpty && clean.isNotEmpty) {
      final prefix = '$m::';
      for (final key in _historyBox.keys) {
        final keyStr = key.toString();
        if (!keyStr.startsWith(prefix)) continue;
        final subKey = keyStr.substring(prefix.length);
        if (subKey.startsWith('read_') || subKey.startsWith('tombstone_')) continue;

        final parts = subKey.split('::');
        final keySource = parts.length >= 2 ? parts[0] : null;
        final keySlug = parts.length >= 2 ? parts.sublist(1).join('::') : subKey;

        if (src != null && keySource != null && keySource.toLowerCase() != src) {
          continue;
        }

        if (keySlug == slug || _cleanSlug(keySlug) == clean) {
          final raw = _historyBox.get(key);
          if (raw is Map) {
            final map = Map<String, dynamic>.from(raw);
            if (src == null || (map['source'] as String?)?.toLowerCase() == src) {
              candidates.add(map);
            }
          }
        }
      }
    }

    // Fallback: if caller specified a source but no candidates matched, check without strict source restriction
    if (candidates.isEmpty && src != null) {
      final fallback = getHistoryItem(slug, source: null, modeId: m);
      if (fallback != null) {
        final itemSrc = (fallback['source'] as String?)?.trim().toLowerCase();
        if (itemSrc == null || itemSrc.isEmpty || itemSrc == src) {
          candidates.add(fallback);
        }
      }
    }

    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;

    // Prioritize the entry with the freshest reading progress (updatedAt descending)
    candidates.sort((a, b) {
      final tA = a['updatedAt'] as int? ?? a['createdAt'] as int? ?? 0;
      final tB = b['updatedAt'] as int? ?? b['createdAt'] as int? ?? 0;
      return tB.compareTo(tA);
    });

    return candidates.first;
  }

  /// Calculates reading progress (0.0 to 1.0) for a given manga slug based on reading history.
  ///
  /// [actualTotalChapters] — jumlah chapter aktual yang diketahui dari source saat ini.
  /// [latestChapter] — string judul/nomor bab terbaru dari item (misal "Chapter 28").
  /// Jika lebih besar dari totalChapters yang tersimpan di history, berarti ada chapter baru
  /// yang belum dibaca, sehingga progress dikembalikan sebagai nilai < 1.0 meski percent = 1.0.
  static double getHistoryProgress(
    String slug, {
    String? source,
    String? modeId,
    int? actualTotalChapters,
    String? latestChapter,
  }) {
    if (slug.isEmpty) return 0.0;
    final m = modeId ?? getActiveContentModeId();
    final clean = _cleanSlug(slug);
    final src = (source != null && source.isNotEmpty) ? source.toLowerCase().trim() : null;
    final cacheKey = src != null ? '$m::$src::$clean' : '$m::$clean';

    final hasCustomArgs = actualTotalChapters != null || (latestChapter != null && latestChapter.trim().isNotEmpty);
    // Jangan pakai cache kalau caller memberikan actualTotalChapters / latestChapter khusus
    final cached = !hasCustomArgs ? _historyProgressCache[cacheKey] : null;
    if (cached != null) return cached;

    final item = getHistoryItem(slug, source: source, modeId: modeId);
    if (item == null) {
      if (!hasCustomArgs) _historyProgressCache[cacheKey] = 0.0;
      return 0.0;
    }

    final savedTotal = (item['totalChapters'] as num?)?.toInt() ?? 0;
    final chNum = (item['chapterNumber'] as num?)?.toInt() ?? 0;

    // Resolusi total chapter aktual: dari parameter, latestChapter, atau favorit
    int? effectiveTotal = actualTotalChapters;
    if (effectiveTotal == null && latestChapter != null && latestChapter.trim().isNotEmpty) {
      final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(latestChapter);
      if (match != null) {
        final parsed = double.tryParse(match.group(1) ?? '');
        if (parsed != null && parsed > 0 && parsed < 100000) {
          effectiveTotal = parsed.toInt();
        }
      }
    }
    if (effectiveTotal == null) {
      final fav = getFavorite(clean, source: src, modeId: m);
      final favLatest = fav?['latestChapter'] as String?;
      if (favLatest != null && favLatest.trim().isNotEmpty) {
        final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(favLatest);
        if (match != null) {
          final parsed = double.tryParse(match.group(1) ?? '');
          if (parsed != null && parsed > 0 && parsed < 100000) {
            effectiveTotal = parsed.toInt();
          }
        }
      }
    }

    final percentVal = (item['percent'] as num?)?.toDouble();
    if (percentVal != null && percentVal > 0) {
      var p = percentVal.clamp(0.0, 1.0);

      // Sumber 1: effectiveTotal > savedTotal (ada chapter baru sejak terakhir dibaca)
      if (effectiveTotal != null && savedTotal > 0 && effectiveTotal > savedTotal) {
        final newCount = effectiveTotal - savedTotal;
        final raw = (chNum > 0 ? chNum : savedTotal) / effectiveTotal;
        final adjusted = newCount >= 3
            ? raw.clamp(0.0, 0.97)
            : newCount >= 2
                ? raw.clamp(0.0, 0.98)
                : raw.clamp(0.0, 0.99);
        return adjusted; // caller-dependent, do not cache
      }

      // Sumber 2: feed item unread — chapter baru sudah masuk feed tapi history masih 1.0
      // (terjadi setelah sync restore sebelum detail screen dibuka)
      if (savedTotal > 0) {
        final unread = getMangaUnreadNewChaptersCount(clean, source: src, modeId: m);
        if (unread > 0) {
          final curCh = chNum > 0 ? chNum : savedTotal;
          final raw = curCh / (savedTotal + unread);
          final adjusted = unread >= 3
              ? raw.clamp(0.0, 0.97)
              : unread >= 2
                  ? raw.clamp(0.0, 0.98)
                  : raw.clamp(0.0, 0.99);
          if (!hasCustomArgs) _historyProgressCache[cacheKey] = adjusted;
          return adjusted;
        }
      }

      // Sumber 3: totalChs dan chNum dari history (atau effectiveTotal)
      final totalChs = (effectiveTotal != null && effectiveTotal > savedTotal)
          ? effectiveTotal
          : savedTotal;
      if (totalChs > 0 && chNum > 0) {
        final remaining = totalChs - chNum;
        if (remaining > 0) {
          // Masih ada bab yang belum dibaca, tidak mungkin 100% (>= 0.999)
          if (p >= 0.999) {
            final raw = chNum / totalChs;
            p = remaining >= 3
                ? raw.clamp(0.0, 0.97)
                : remaining >= 2
                    ? raw.clamp(0.0, 0.98)
                    : raw.clamp(0.0, 0.99);
          } else {
            p = remaining >= 3
                ? p.clamp(0.0, 0.97)
                : remaining >= 2
                    ? p.clamp(0.0, 0.98)
                    : p.clamp(0.0, 0.99);
          }
        }
      }
      if (!hasCustomArgs) _historyProgressCache[cacheKey] = p;
      return p;
    }

    final page = (item['page'] as num?)?.toInt() ?? 1;
    final totalPages = (item['totalPages'] as num?)?.toInt() ?? 1;
    final totalChs = (effectiveTotal != null && effectiveTotal > savedTotal)
        ? effectiveTotal
        : savedTotal;
    if (totalChs > 0 && chNum > 0) {
      final pageFrac = totalPages > 0 ? (page / totalPages).clamp(0.0, 1.0) : 0.0;
      final raw = ((chNum - 1 + pageFrac) / totalChs).clamp(0.01, 1.0);
      final remaining = totalChs - chNum;
      final p = remaining > 0
          ? (remaining >= 3
              ? raw.clamp(0.01, 0.97)
              : remaining >= 2
                  ? raw.clamp(0.01, 0.98)
                  : raw.clamp(0.01, 0.99))
          : raw;
      if (!hasCustomArgs) _historyProgressCache[cacheKey] = p;
      return p;
    }

    if (totalPages > 0) {
      final p = (page / totalPages).clamp(0.01, 1.0);
      if (!hasCustomArgs) _historyProgressCache[cacheKey] = p;
      return p;
    }
    if (!hasCustomArgs) _historyProgressCache[cacheKey] = 0.01;
    return 0.01;
  }

  static Future<void> saveHistory({
    required String slug,
    required String title,
    required String? cover,
    required String source,
    required String chapterSlug,
    required String chapterTitle,
    required int page,
    required int totalPages,
    double pageOffset = 0,
    double scrollOffset = 0,
    double? percent,
    int? totalChapters,
    num? chapterNumber,
    Map<int, double>? pageHeights,
    double? pageOffsetRatio,
    int? updatedAt,
    int? createdAt,
    String? modeId,
  }) async {
    _historyProgressCache.clear();
    final m = modeId ?? getActiveContentModeId();
    final src = source.trim().toLowerCase();
    String resolvedChapterSlug = chapterSlug.trim();
    if (resolvedChapterSlug.isEmpty && chapterTitle.isNotEmpty) {
      final match = RegExp(r'Chapter\s+([0-9.]+)', caseSensitive: false).firstMatch(chapterTitle);
      if (match != null) {
        resolvedChapterSlug = match.group(1)!;
      }
    }

    if (resolvedChapterSlug.isNotEmpty) {
      await markChaptersAsRead(slug, [resolvedChapterSlug], source: src, modeId: m);
    }

    final existing = getHistoryItem(slug, source: src, modeId: m);
    String? resolvedCover = (cover != null && cover.trim().isNotEmpty) ? cover.trim() : null;
    if (resolvedCover == null && existing != null) {
      final exCover = existing['cover'] as String?;
      if (exCover != null && exCover.trim().isNotEmpty) {
        resolvedCover = exCover.trim();
      }
    }

    String resolvedTitle = title.trim();
    if ((resolvedTitle.isEmpty || resolvedTitle == slug) && existing != null) {
      final exTitle = existing['title'] as String?;
      if (exTitle != null && exTitle.trim().isNotEmpty && exTitle.trim() != slug) {
        resolvedTitle = exTitle.trim();
      }
    }

    // Preserve existing reading offsets if incoming are empty/zero for the same chapter
    int resolvedPage = page;
    int resolvedTotalPages = totalPages;
    double resolvedPageOffset = pageOffset;
    double resolvedScrollOffset = scrollOffset;
    double? resolvedPageOffsetRatio = pageOffsetRatio;
    Map? resolvedPageHeights = pageHeights != null && pageHeights.isNotEmpty
        ? pageHeights.map((k, v) => MapEntry(k.toString(), v))
        : null;

    if (existing != null && existing['chapterSlug'] == resolvedChapterSlug) {
      final existingPage = (existing['page'] as num?)?.toInt() ?? 1;
      final isRealReadPosition = resolvedScrollOffset > 0 || resolvedPageOffset > 0 || resolvedPageOffsetRatio != null;
      if (!isRealReadPosition && (resolvedPage == existingPage || (resolvedPage <= 1 && existingPage > 1))) {
        if (resolvedPage <= 1 && existingPage > 1) {
          resolvedPage = existingPage;
        }
        if (resolvedPageOffset <= 0 && existing['pageOffset'] != null && (existing['pageOffset'] as num) > 0) {
          resolvedPageOffset = (existing['pageOffset'] as num).toDouble();
        }
        if (resolvedScrollOffset <= 0 && existing['scrollOffset'] != null && (existing['scrollOffset'] as num) > 0) {
          resolvedScrollOffset = (existing['scrollOffset'] as num).toDouble();
        }
        if (resolvedPageOffsetRatio == null && existing['pageOffsetRatio'] != null) {
          resolvedPageOffsetRatio = (existing['pageOffsetRatio'] as num).toDouble();
        }
        if (resolvedPageHeights == null && existing['pageHeights'] is Map) {
          resolvedPageHeights = Map.from(existing['pageHeights'] as Map);
        }
      }
      if (resolvedTotalPages <= 1 && existing['totalPages'] != null && (existing['totalPages'] as num) > 1) {
        resolvedTotalPages = (existing['totalPages'] as num).toInt();
      }
    }

    final histData = <String, dynamic>{
      'mode_id': m,
      'slug': slug,
      'title': resolvedTitle.isNotEmpty ? resolvedTitle : title,
      'cover': resolvedCover,
      'source': source.trim(),
      'chapterSlug': resolvedChapterSlug,
      'chapterTitle': chapterTitle,
      'page': resolvedPage,
      'totalPages': resolvedTotalPages,
      'pageOffset': resolvedPageOffset,
      'scrollOffset': resolvedScrollOffset,
      'createdAt': createdAt ?? (existing != null ? (existing['createdAt'] as num?)?.toInt() : null) ?? (existing != null ? (existing['updatedAt'] as num?)?.toInt() : null) ?? DateTime.now().millisecondsSinceEpoch,
      'updatedAt': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    };
    double? resolvedPercent = percent;
    if (resolvedPercent != null && totalChapters != null && chapterNumber != null) {
      final remaining = totalChapters - chapterNumber;
      if (remaining > 0) {
        if (resolvedPercent >= 0.999) {
          resolvedPercent = (chapterNumber / totalChapters);
        }
        if (remaining >= 2) {
          resolvedPercent = resolvedPercent.clamp(0.0, remaining >= 3 ? 0.97 : 0.98);
        } else {
          resolvedPercent = resolvedPercent.clamp(0.0, 0.99);
        }
      }
    }
    if (resolvedPercent != null) histData['percent'] = resolvedPercent;
    if (totalChapters != null) histData['totalChapters'] = totalChapters;
    if (chapterNumber != null) histData['chapterNumber'] = chapterNumber;
    if (resolvedPageHeights != null && resolvedPageHeights.isNotEmpty) {
      histData['pageHeights'] = resolvedPageHeights;
    }
    if (resolvedPageOffsetRatio != null) {
      histData['pageOffsetRatio'] = resolvedPageOffsetRatio;
    }

    final key = src.isNotEmpty ? '$m::$src::$slug' : '$m::$slug';
    await _historyBox.put(key, histData);

    await removeDeletedHistoryTombstone(slug, source: source, modeId: m);

    // Clean up legacy un-scoped key if it belonged to this source
    final clean = _cleanSlug(slug);
    for (final legacyKey in ['$m::$slug', if (clean.isNotEmpty) '$m::$clean']) {
      if (_historyBox.containsKey(legacyKey)) {
        final oldVal = _historyBox.get(legacyKey);
        if (oldVal is Map && (oldVal['source'] as String?)?.toLowerCase() == src) {
          await _historyBox.delete(legacyKey);
        }
      }
    }

    if (resolvedCover != null && resolvedCover.isNotEmpty) {
      ensureCoverCached(slug: slug, coverUrl: resolvedCover, source: source);
    }
  }

  /// Updates metadata (title, cover, percent, totalChapters, chapterNumber, chapterSlug, chapterTitle) of an existing reading history item
  static Future<void> updateHistoryMetadata({
    required String slug,
    String? source,
    String? title,
    String? cover,
    double? percent,
    int? totalChapters,
    num? chapterNumber,
    String? chapterSlug,
    String? chapterTitle,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final clean = _cleanSlug(slug);
    final src = source?.trim().toLowerCase();

    String? key;
    if (src != null && src.isNotEmpty) {
      if (_historyBox.containsKey('$m::$src::$slug')) {
        key = '$m::$src::$slug';
      } else if (clean.isNotEmpty && _historyBox.containsKey('$m::$src::$clean')) {
        key = '$m::$src::$clean';
      }
    }
    if (key == null) {
      if (_historyBox.containsKey('$m::$slug')) {
        final val = _historyBox.get('$m::$slug');
        if (src == null || (val is Map && (val['source'] as String?)?.toLowerCase() == src)) {
          key = '$m::$slug';
        }
      } else if (clean.isNotEmpty && _historyBox.containsKey('$m::$clean')) {
        final val = _historyBox.get('$m::$clean');
        if (src == null || (val is Map && (val['source'] as String?)?.toLowerCase() == src)) {
          key = '$m::$clean';
        }
      }
    }

    if (key == null) {
      final prefix = '$m::';
      for (final k in _historyBox.keys) {
        final kStr = k.toString();
        if (!kStr.startsWith(prefix)) continue;
        final subKey = kStr.substring(prefix.length);
        if (subKey.startsWith('read_') || subKey.startsWith('tombstone_')) continue;
        final parts = subKey.split('::');
        final keySlug = parts.length >= 2 ? parts.sublist(1).join('::') : subKey;
        final keySource = parts.length >= 2 ? parts[0] : null;
        if (src != null && keySource != null && keySource != src) continue;
        if (keySlug == slug || (clean.isNotEmpty && _cleanSlug(keySlug) == clean)) {
          key = kStr;
          break;
        }
      }
    }
    if (key == null) return;
    final raw = _historyBox.get(key);
    if (raw is Map) {
      final item = Map<String, dynamic>.from(raw);
      bool changed = false;
      if (title != null && title.trim().isNotEmpty && title.trim() != slug && item['title'] != title.trim()) {
        item['title'] = title.trim();
        changed = true;
      }
      if (cover != null && cover.trim().isNotEmpty && item['cover'] != cover.trim()) {
        item['cover'] = cover.trim();
        changed = true;
      }
      if (percent != null) {
        var p = percent;
        final totalChs = totalChapters ?? (item['totalChapters'] as num?)?.toInt() ?? 0;
        final chNum = (item['chapterNumber'] as num?)?.toInt() ?? 0;
        if (totalChs > 0 && chNum > 0) {
          final remaining = totalChs - chNum;
          if (remaining > 0) {
            if (p >= 0.999) {
              p = (chNum / totalChs);
            }
            if (remaining >= 2) {
              p = p.clamp(0.0, remaining >= 3 ? 0.97 : 0.98);
            } else {
              p = p.clamp(0.0, 0.99);
            }
          }
        }
        if ((item['percent'] as num?)?.toDouble() != p) {
          item['percent'] = p;
          changed = true;
        }
      }
      if (totalChapters != null && (item['totalChapters'] as num?)?.toInt() != totalChapters) {
        item['totalChapters'] = totalChapters;
        changed = true;
      }
      if (chapterNumber != null && chapterNumber > 0 && (item['chapterNumber'] as num?)?.toInt() != chapterNumber) {
        item['chapterNumber'] = chapterNumber;
        changed = true;
      }
      if (chapterSlug != null && chapterSlug.trim().isNotEmpty && item['chapterSlug'] != chapterSlug.trim()) {
        item['chapterSlug'] = chapterSlug.trim();
        changed = true;
      }
      if (chapterTitle != null && chapterTitle.trim().isNotEmpty && item['chapterTitle'] != chapterTitle.trim()) {
        item['chapterTitle'] = chapterTitle.trim();
        changed = true;
      }
      if (changed) {
        await _historyBox.put(key, item);
        _historyProgressCache.clear();
      }
    }

    if (cover != null && cover.trim().isNotEmpty) {
      ensureCoverCached(slug: slug, coverUrl: cover.trim(), source: source);
    }
  }

  // --- Active Reader Session (State Restoration persis seperti Kotatsu) ---
  static const _keyActiveReaderSession = 'active_reader_session';

  static Map<String, dynamic>? getActiveReaderSession() {
    final raw = _settingsBox.get(_keyActiveReaderSession);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  static Future<void> saveActiveReaderSession(Map<String, dynamic> session) async {
    await _settingsBox.put(_keyActiveReaderSession, session);
  }

  static Future<void> clearActiveReaderSession() async {
    await _settingsBox.delete(_keyActiveReaderSession);
  }

  static Future<void> clearHistoryDirect({String? modeId}) async {
    _historyProgressCache.clear();
    final m = modeId ?? getActiveContentModeId();
    final prefix = '$m::';
    final keys = _historyBox.keys.where((k) {
      final s = k.toString();
      return s.startsWith(prefix) && !s.substring(prefix.length).startsWith('tombstone_');
    }).toList();
    for (final k in keys) {
      await _historyBox.delete(k);
    }
  }

  static Future<void> clearHistory({String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    final all = getHistory(modeId: m);
    for (final h in all) {
      final slug = h['slug'] as String? ?? '';
      if (slug.isNotEmpty) {
        await recordDeletedHistoryTombstone(
          slug,
          title: h['title'] as String?,
          source: h['source'] as String?,
          modeId: m,
        );
      }
    }
    await clearHistoryDirect(modeId: m);
  }

  static Future<void> deleteHistoryItem(
    String slug, {
    String? source,
    bool recordTombstone = true,
    String? modeId,
  }) async {
    _historyProgressCache.clear();
    final m = modeId ?? getActiveContentModeId();
    final src = source?.trim().toLowerCase();
    final item = getHistoryItem(slug, source: src, modeId: m);
    if (recordTombstone) {
      if (item != null) {
        await recordDeletedHistoryTombstone(
          slug,
          title: item['title'] as String?,
          source: item['source'] as String? ?? source,
          modeId: m,
        );
      } else {
        await recordDeletedHistoryTombstone(slug, source: source, modeId: m);
      }
    }

    final clean = _cleanSlug(slug);
    if (src != null && src.isNotEmpty) {
      await _historyBox.delete('$m::$src::$slug');
      if (clean.isNotEmpty) {
        await _historyBox.delete('$m::$src::$clean');
        await _historyBox.delete('$m::$src::manga/$clean');
        await _historyBox.delete('$m::$src::/manga/$clean');
      }
      // Also delete legacy un-scoped key if it matches this source
      final oldRaw = _historyBox.get('$m::$slug');
      if (oldRaw is Map && (oldRaw['source'] as String?)?.toLowerCase() == src) {
        await _historyBox.delete('$m::$slug');
      }
      if (clean.isNotEmpty) {
        final cleanRaw = _historyBox.get('$m::$clean');
        if (cleanRaw is Map && (cleanRaw['source'] as String?)?.toLowerCase() == src) {
          await _historyBox.delete('$m::$clean');
        }
      }
    } else {
      await _historyBox.delete('$m::$slug');
      if (clean.isNotEmpty) {
        await _historyBox.delete('$m::$clean');
        await _historyBox.delete('$m::manga/$clean');
        await _historyBox.delete('$m::/manga/$clean');
      }
      // Delete any source-scoped key for this slug
      final prefix = '$m::';
      final toDelete = <dynamic>[];
      for (final k in _historyBox.keys) {
        final kStr = k.toString();
        if (!kStr.startsWith(prefix)) continue;
        final sub = kStr.substring(prefix.length);
        if (sub.endsWith('::$slug') || (clean.isNotEmpty && sub.endsWith('::$clean'))) {
          toDelete.add(k);
        }
      }
      for (final k in toDelete) {
        await _historyBox.delete(k);
      }
    }

    await clearReadChapters(slug, source: src, modeId: m);
  }

  // --- Deletion Tombstones for Sync Server ---

  static List<Map<String, dynamic>> getDeletedHistoryTombstones({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final raw = _settingsBox.get(_modeKey('deleted_history_tombstones', m));
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<void> recordDeletedHistoryTombstone(
    String slug, {
    String? title,
    String? source,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final list = getDeletedHistoryTombstones(modeId: m);
    final src = source?.trim().toLowerCase();
    list.removeWhere((e) => e['slug'] == slug && (src == null || (e['source'] as String?)?.toLowerCase() == src));
    list.add({
      'slug': slug,
      'title': title ?? slug,
      'source': source ?? 'shinigami',
      'deletedAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (list.length > 200) list.removeRange(0, list.length - 200);
    await _settingsBox.put(_modeKey('deleted_history_tombstones', m), list);
  }

  static Future<void> clearDeletedHistoryTombstones({String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.delete(_modeKey('deleted_history_tombstones', m));
  }

  static Future<void> removeDeletedHistoryTombstone(
    String slug, {
    String? source,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final list = getDeletedHistoryTombstones(modeId: m);
    final src = source?.trim().toLowerCase();
    final clean = _cleanSlug(slug);
    list.removeWhere((e) {
      final s = e['slug'] as String? ?? '';
      final matchSlug = s == slug || (clean.isNotEmpty && _cleanSlug(s) == clean);
      final matchSrc = src == null || (e['source'] as String?)?.toLowerCase() == src;
      return matchSlug && matchSrc;
    });
    await _settingsBox.put(_modeKey('deleted_history_tombstones', m), list);
  }

  static List<Map<String, dynamic>> getDeletedFavoriteTombstones({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final raw = _settingsBox.get(_modeKey('deleted_favorite_tombstones', m));
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<void> recordDeletedFavoriteTombstone(
    String slug, {
    String? title,
    String? source,
    List<String>? categories,
    String? category,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final list = getDeletedFavoriteTombstones(modeId: m);
    final src = source?.trim().toLowerCase();
    list.removeWhere((e) => e['slug'] == slug && (src == null || (e['source'] as String?)?.toLowerCase() == src));
    list.add({
      'slug': slug,
      'title': title ?? slug,
      'source': source ?? 'shinigami',
      'categories': categories ?? (category != null ? [category] : []),
      'category': category,
      'deletedAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (list.length > 200) list.removeRange(0, list.length - 200);
    await _settingsBox.put(_modeKey('deleted_favorite_tombstones', m), list);
  }

  static Future<void> clearDeletedFavoriteTombstones({String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.delete(_modeKey('deleted_favorite_tombstones', m));
  }

  static Future<void> removeDeletedFavoriteTombstone(
    String slug, {
    String? source,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final list = getDeletedFavoriteTombstones(modeId: m);
    final src = source?.trim().toLowerCase();
    final clean = _cleanSlug(slug);
    list.removeWhere((e) {
      final s = e['slug'] as String? ?? '';
      final matchSlug = s == slug || (clean.isNotEmpty && _cleanSlug(s) == clean);
      final matchSrc = src == null || (e['source'] as String?)?.toLowerCase() == src;
      return matchSlug && matchSrc;
    });
    await _settingsBox.put(_modeKey('deleted_favorite_tombstones', m), list);
  }

  static List<Map<String, dynamic>> getDeletedCategoryTombstones({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final raw = _settingsBox.get(_modeKey('deleted_category_tombstones', m));
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Future<void> recordDeletedCategoryTombstone(
    String name, {
    int? categoryId,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final list = getDeletedCategoryTombstones(modeId: m);
    list.removeWhere((e) => e['name'] == name);
    final entry = <String, dynamic>{
      'name': name,
      'deletedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (categoryId != null) {
      entry['categoryId'] = categoryId;
    }
    list.add(entry);
    if (list.length > 50) list.removeRange(0, list.length - 50);
    await _settingsBox.put(_modeKey('deleted_category_tombstones', m), list);
  }

  static Future<void> removeDeletedCategoryTombstone(String name, {int? categoryId, String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    final list = getDeletedCategoryTombstones(modeId: m);
    list.removeWhere((e) => e['name'] == name || (categoryId != null && e['categoryId'] == categoryId));
    await _settingsBox.put(_modeKey('deleted_category_tombstones', m), list);
  }

  static Future<void> clearDeletedCategoryTombstones({String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.delete(_modeKey('deleted_category_tombstones', m));
  }

  // --- Feed (Umpan) / Tracker ---

  static ValueListenable<Box> listenFeed() => _feedBox.listenable();

  static bool _isFeedItem(dynamic key, dynamic raw) {
    final keyStr = key.toString();
    if (keyStr.contains('track_') || keyStr.startsWith('track_')) return false;
    if (raw is! Map) return false;
    final slug = raw['mangaSlug'] as String?;
    if (slug == null || slug.trim().isEmpty) return false;
    final title = raw['mangaTitle'] as String?;
    if (title == null || title.trim().isEmpty) return false;
    // Baselines have lastChapterSlug but no valid mangaSlug/mangaTitle
    if (raw.containsKey('lastChapterSlug') && !raw.containsKey('mangaSlug')) return false;
    final source = raw['mangaSource'] as String?;
    if (source != null && source.toLowerCase() == 'unknown') return false;
    return true;
  }

  static List<FeedItem> getFeedItems({String? modeId}) {
    final targetMode = modeId ?? getActiveContentModeId();
    final list = <FeedItem>[];
    final seenKeys = <String>{};
    final toDeleteKeys = <dynamic>[];

    for (var key in _feedBox.keys) {
      final raw = _feedBox.get(key);
      if (!_isFeedItem(key, raw)) continue;
      try {
        var item = FeedItem.fromJson(Map<String, dynamic>.from(raw as Map));
        if (!item.isValid) continue;
        final itemMode = item.modeId ?? ContentMode.defaultNormalId;
        if (targetMode == 'all' || itemMode == targetMode) {
          final resolved = resolveMigratedFeedItem(item, modeId: itemMode);
          if (resolved != null) {
            item = resolved;
            _feedBox.put(key, item.toJson());
          }

          // Deduplicate items for the same manga + source + mode + chapter(s)
          final normSlug = item.mangaSlug.trim().replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
          final normSrc = item.mangaSource.trim().toLowerCase();
          final chKey = item.newChapterSlugs.isNotEmpty
              ? item.newChapterSlugs.map((s) => s.trim().replaceAll(RegExp(r'^/+|/+$'), '').split('/').last.toLowerCase()).join(',')
              : item.newChapters.map((c) => c.trim().toLowerCase()).join(',');
          final dedupKey = '$itemMode::$normSrc::$normSlug::$chKey';

          if (!seenKeys.add(dedupKey)) {
            // Found a duplicate entry in _feedBox, discard it and mark for cleanup
            toDeleteKeys.add(key);
            continue;
          }

          list.add(item);
        }
      } catch (_) {}
    }

    for (final k in toDeleteKeys) {
      _feedBox.delete(k);
    }

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static Future<void> addFeedItem(FeedItem item) async {
    if (!item.isValid) return;

    // ── Deduplication ──────────────────────────────────────────────────────────
    // Prevent duplicate feed entries for the same manga + source + mode when
    // background check and manual check both fire around the same time.
    // Two items are considered duplicates when they share the same manga identity
    // AND their chapter slug sets overlap (at least one chapter in common).
    final itemMode = item.modeId ?? ContentMode.defaultNormalId;
    String normalizeSlug(String s) =>
        s.trim().replaceAll(RegExp(r'^/+|/+$'), '').split('/').last.trim().toLowerCase();
    final itemSlugs = item.newChapterSlugs.map(normalizeSlug).toSet();
    final itemChapters = item.newChapters.map((e) => e.trim().toLowerCase()).toSet();

    for (final key in _feedBox.keys.toList()) {
      final raw = _feedBox.get(key);
      if (!_isFeedItem(key, raw)) continue;
      try {
        final existing = FeedItem.fromJson(Map<String, dynamic>.from(raw as Map));
        if (!existing.isValid) continue;
        final existingMode = existing.modeId ?? ContentMode.defaultNormalId;

        // Must match manga identity
        if (existing.mangaSlug.trim() != item.mangaSlug.trim() ||
            existing.mangaSource.trim() != item.mangaSource.trim() ||
            existingMode != itemMode) {
          continue;
        }

        // Check if chapter slugs overlap
        final existingSlugs = existing.newChapterSlugs.map(normalizeSlug).toSet();
        final existingChapters = existing.newChapters.map((e) => e.trim().toLowerCase()).toSet();

        final slugOverlap = itemSlugs.isNotEmpty && existingSlugs.isNotEmpty &&
            itemSlugs.intersection(existingSlugs).isNotEmpty;
        final chapterOverlap = !slugOverlap &&
            itemChapters.isNotEmpty && existingChapters.isNotEmpty &&
            itemChapters.intersection(existingChapters).isNotEmpty;

        if (slugOverlap || chapterOverlap) {
          // Duplicate detected — skip saving this item
          debugPrint('[FeedTracker] Skipped duplicate feed entry for ${item.mangaSlug} (${item.mangaSource})');
          return;
        }
      } catch (_) {}
    }
    // ──────────────────────────────────────────────────────────────────────────

    // Ensure newly detected chapters are not marked as read in readChapters
    final toUnread = <String>[
      ...item.newChapterSlugs,
      ...item.newChapters,
    ];
    for (final title in item.newChapters) {
      final num = _extractChapterNum(title);
      if (num != null) {
        final numStr = num % 1 == 0 ? num.toInt().toString() : num.toString();
        toUnread.add(numStr);
        toUnread.add('chapter-$numStr');
        toUnread.add('chapter_$numStr');
        toUnread.add('ch-$numStr');
        toUnread.add('bab-$numStr');
      }
    }
    for (final slug in item.newChapterSlugs) {
      final num = _extractChapterNum(slug);
      if (num != null) {
        final numStr = num % 1 == 0 ? num.toInt().toString() : num.toString();
        toUnread.add(numStr);
        toUnread.add('chapter-$numStr');
        toUnread.add('chapter_$numStr');
        toUnread.add('ch-$numStr');
        toUnread.add('bab-$numStr');
      }
    }
    await markChaptersAsUnread(item.mangaSlug, toUnread, source: item.mangaSource, modeId: item.modeId);

    // If manga was previously completed (percent >= 0.99), only update percent if totalChapters is known and new chapters arrived
    final hist = getHistoryItem(item.mangaSlug, source: item.mangaSource, modeId: item.modeId);
    if (hist != null) {
      final pct = (hist['percent'] as num?)?.toDouble() ?? 0.0;
      if (pct >= 0.99) {
        final prevTotal = (hist['totalChapters'] as num?)?.toInt() ?? 0;
        final newCount = item.newChaptersCount > 0 ? item.newChaptersCount : item.newChapterSlugs.length;
        if (prevTotal > 0 && newCount > 0) {
          final newTotal = prevTotal + newCount;
          final raw = prevTotal / newTotal;
          final updatedPct = newCount >= 2
              ? raw.clamp(0.0, newCount >= 3 ? 0.97 : 0.98)
              : raw.clamp(0.0, 0.99);
          await updateHistoryMetadata(
            slug: item.mangaSlug,
            source: item.mangaSource,
            percent: updatedPct,
            totalChapters: newTotal,
            chapterNumber: prevTotal,
            modeId: item.modeId,
          );
        } else {
          await updateHistoryMetadata(
            slug: item.mangaSlug,
            source: item.mangaSource,
            percent: 0.98,
            modeId: item.modeId,
          );
        }
      }
    }

    await _feedBox.put(item.id, item.toJson());

    // Update launcher app icon badge
    final totalUnread = getTotalUnreadNewChaptersCount(modeId: item.modeId);
    await TrackerNotificationService.setBadgeCount(totalUnread);
  }

  static Future<void> markFeedItemAsRead(String id) async {
    final raw = _feedBox.get(id);
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      map['isNew'] = false;
      map['dismissed'] = true;
      await _feedBox.put(id, map);
      final totalUnread = getTotalUnreadNewChaptersCount();
      await TrackerNotificationService.setBadgeCount(totalUnread);
    }
  }

  static Future<void> markAllFeedItemsAsRead({String? modeId}) async {
    final targetMode = modeId ?? getActiveContentModeId();
    for (var key in _feedBox.keys) {
      final raw = _feedBox.get(key);
      if (!_isFeedItem(key, raw)) continue;
      if (raw is Map && raw['isNew'] == true) {
        final itemMode = raw['modeId'] as String? ?? ContentMode.defaultNormalId;
        if (targetMode == 'all' || itemMode == targetMode) {
          final map = Map<String, dynamic>.from(raw);
          map['isNew'] = false;
          map['dismissed'] = true;
          await _feedBox.put(key, map);
        }
      }
    }
    final totalUnread = getTotalUnreadNewChaptersCount();
    await TrackerNotificationService.setBadgeCount(totalUnread);
  }

  static Future<FeedItem?> removeFeedItem(String id) async {
    final raw = _feedBox.get(id);
    if (raw is Map) {
      final item = FeedItem.fromJson(Map<String, dynamic>.from(raw));
      await _feedBox.delete(id);
      final totalUnread = getTotalUnreadNewChaptersCount();
      await TrackerNotificationService.setBadgeCount(totalUnread);
      return item;
    }
    await _feedBox.delete(id);
    final totalUnread = getTotalUnreadNewChaptersCount();
    await TrackerNotificationService.setBadgeCount(totalUnread);
    return null;
  }

  static Future<void> restoreFeedItem(FeedItem item) async {
    if (!item.isValid) return;
    await _feedBox.put(item.id, item.toJson());
    final totalUnread = getTotalUnreadNewChaptersCount();
    await TrackerNotificationService.setBadgeCount(totalUnread);
  }

  static Future<void> clearFeed({String? modeId}) async {
    final targetMode = modeId ?? getActiveContentModeId();
    final keysToDelete = <dynamic>[];
    for (var key in _feedBox.keys) {
      final raw = _feedBox.get(key);
      // Only delete actual feed items, NEVER delete track baselines!
      if (!_isFeedItem(key, raw)) continue;
      if (raw is Map) {
        final itemMode = raw['modeId'] as String? ?? ContentMode.defaultNormalId;
        if (targetMode == 'all' || itemMode == targetMode) {
          keysToDelete.add(key);
        }
      }
    }
    for (var k in keysToDelete) {
      await _feedBox.delete(k);
    }
    final totalUnread = getTotalUnreadNewChaptersCount();
    await TrackerNotificationService.setBadgeCount(totalUnread);
  }

  static double? _extractChapterNum(String text) {
    if (text.trim().isEmpty) return null;
    final prefMatch = RegExp(r'(?:chapter|ch|bab|episode|ep)[-_\s.]*([0-9]+(?:\.[0-9]+)?)', caseSensitive: false).firstMatch(text);
    if (prefMatch != null) {
      return double.tryParse(prefMatch.group(1)!);
    }
    final endMatch = RegExp(r'[-_/]([0-9]+(?:\.[0-9]+)?)/?$', caseSensitive: false).firstMatch(text);
    if (endMatch != null) {
      return double.tryParse(endMatch.group(1)!);
    }
    final anyMatch = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(text);
    if (anyMatch != null) {
      return double.tryParse(anyMatch.group(1)!);
    }
    return null;
  }

  static bool isChapterReadMatch({
    required String title,
    required String slug,
    required Set<String> readChapters,
    Map<String, dynamic>? history,
  }) => _isChapterReadMatch(
    title: title,
    slug: slug,
    readChapters: readChapters,
    history: history,
  );

  static bool _isChapterReadMatch({
    required String title,
    required String slug,
    required Set<String> readChapters,
    Map<String, dynamic>? history,
    // Jika true, hanya cocokkan berdasarkan slug/title eksplisit di readChapters —
    // tidak menggunakan numeric fuzzy matching atau history matching.
    // Gunakan ini saat mengecek status chapter dari feed agar chapter baru
    // tidak ter-anggap sudah dibaca hanya karena cocok secara numerik.
    bool strictMode = false,
  }) {
    final cleanSlug = slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final cleanTitle = title.trim();

    if (slug.isNotEmpty) {
      if (readChapters.contains(slug) ||
          readChapters.contains(cleanSlug) ||
          readChapters.contains(SyncService.hashSlug(slug).toString()) ||
          readChapters.contains(SyncService.hashSlug(cleanSlug).toString())) {
        return true;
      }
    }
    if (cleanTitle.isNotEmpty) {
      if (readChapters.contains(cleanTitle) ||
          readChapters.contains(SyncService.hashSlug(cleanTitle).toString())) {
        return true;
      }
    }

    // Di strict mode (feed checking), tidak lakukan numeric matching atau history matching
    // agar chapter baru tidak salah ter-mark sebagai sudah dibaca.
    if (strictMode) return false;

    final chNum = _extractChapterNum(cleanTitle.isNotEmpty ? cleanTitle : cleanSlug);
    if (chNum != null) {
      final numStr = chNum % 1 == 0 ? chNum.toInt().toString() : chNum.toString();

      if (readChapters.contains(numStr) ||
          readChapters.contains('chapter-$numStr') ||
          readChapters.contains('chapter_$numStr') ||
          readChapters.contains('ch-$numStr') ||
          readChapters.contains('bab-$numStr')) {
        return true;
      }

      for (final r in readChapters) {
        final rNum = _extractChapterNum(r);
        if (rNum != null && rNum == chNum) {
          return true;
        }
      }
    }

    // Match history if history recorded reading this exact chapter
    if (history != null) {
      final hSlug = (history['chapterSlug']?.toString() ?? '').trim().replaceAll(RegExp(r'^/+|/+$'), '');
      final hTitle = (history['chapterTitle']?.toString() ?? '').trim();

      final isExactMatch = (cleanSlug.isNotEmpty && hSlug.isNotEmpty && (cleanSlug == hSlug || SyncService.hashSlug(cleanSlug).toString() == hSlug)) ||
          (cleanTitle.isNotEmpty && hTitle.isNotEmpty && cleanTitle.toLowerCase() == hTitle.toLowerCase()) ||
          (hSlug.isNotEmpty && SyncService.hashSlug(slug).toString() == hSlug);

      if (isExactMatch) {
        return true;
      }
    }

    return false;
  }

  static bool isFeedItemUnread(FeedItem item) {
    if (!item.isNew) return false;
    return getUnreadNewChaptersCount(item) > 0;
  }

  static int getUnreadNewChaptersCount(FeedItem item, {bool ignoreIsNew = false}) {
    if (!ignoreIsNew && !item.isNew) return 0;

    final readChapters = getReadChapters(item.mangaSlug, source: item.mangaSource, modeId: item.modeId).toSet();

    final chaptersToCheck = item.newChapters.isNotEmpty ? item.newChapters : item.newChapterSlugs;
    if (chaptersToCheck.isEmpty) {
      return item.isNew ? item.newChaptersCount : 0;
    }

    int unreadCount = 0;
    for (int i = 0; i < chaptersToCheck.length; i++) {
      final title = i < item.newChapters.length ? item.newChapters[i] : '';
      final slug = i < item.newChapterSlugs.length ? item.newChapterSlugs[i] : '';

      // Gunakan strictMode=true: chapter baru di feed hanya dianggap sudah dibaca
      // jika slugnya secara eksplisit ada di readChapters — tidak pakai numeric
      // fuzzy matching atau history matching agar chapter baru tidak salah ter-mark read.
      bool isRead = _isChapterReadMatch(
        title: title,
        slug: slug,
        readChapters: readChapters,
        strictMode: true,
      );

      // Healing protection: jika chapter ini ter-mark read di readChapters akibat bug sinkronisasi sebelumnya,
      // tetapi historyItem mencatat bahwa bab terakhir yang dibaca pengguna di reader lebih kecil dari bab ini,
      // maka bab ini sejatinya belum pernah dibaca oleh user!
      if (isRead) {
        final hist = getHistoryItem(item.mangaSlug, source: item.mangaSource, modeId: item.modeId);
        if (hist != null) {
          final chNum = _extractChapterNum(title.isNotEmpty ? title : slug);
          final histNum = (hist['chapterNumber'] as num?)?.toDouble() ??
              _extractChapterNum(hist['chapterTitle']?.toString() ?? '') ??
              _extractChapterNum(hist['chapterSlug']?.toString() ?? '');
          if (chNum != null && histNum != null && chNum > histNum) {
            isRead = false;
          }
        }
      }

      if (!isRead) {
        unreadCount++;
      }
    }

    return unreadCount;
  }

  /// Returns the number of unread new chapters for a specific manga (for the badge on cards).
  static int getMangaUnreadNewChaptersCount(
    String slug, {
    String? source,
    String? modeId,
  }) {
    if (slug.isEmpty) return 0;
    final m = modeId ?? getActiveContentModeId();
    final clean = _cleanSlug(slug);
    final src = (source != null && source.isNotEmpty) ? source.toLowerCase().trim() : null;
    final cacheKey = src != null ? '$m::$src::$clean' : '$m::$clean';

    final cached = _unreadNewChaptersCountCache[cacheKey];
    if (cached != null) return cached;

    int totalUnread = 0;
    final countedSlugs = <String>{};

    for (var key in _feedBox.keys) {
      final raw = _feedBox.get(key);
      if (!_isFeedItem(key, raw)) continue;
      if (raw is Map) {
        final itemSlug = raw['mangaSlug'] as String?;
        if (itemSlug == null) continue;
        if (_cleanSlug(itemSlug) != clean) continue;

        final itemSource = raw['mangaSource'] as String?;
        if (source != null &&
            itemSource != null &&
            source.isNotEmpty &&
            itemSource.isNotEmpty &&
            source.toLowerCase() != itemSource.toLowerCase()) {
          continue;
        }

        final itemMode = raw['modeId'] as String? ?? ContentMode.defaultNormalId;
        if (m != 'all' && itemMode != m) continue;

        try {
          final item = FeedItem.fromJson(Map<String, dynamic>.from(raw));
          if (!isFeedItemUnread(item)) continue;

          final readChapters = getReadChapters(item.mangaSlug, source: item.mangaSource, modeId: item.modeId).toSet();
          final chaptersToCheck = item.newChapters.isNotEmpty ? item.newChapters : item.newChapterSlugs;

          if (chaptersToCheck.isEmpty && item.isNew) {
            totalUnread += item.newChaptersCount;
            continue;
          }

          for (int i = 0; i < chaptersToCheck.length; i++) {
            final title = i < item.newChapters.length ? item.newChapters[i] : '';
            final chSlug = i < item.newChapterSlugs.length ? item.newChapterSlugs[i] : '';
            final trackKey = chSlug.isNotEmpty ? chSlug : title;

            if (countedSlugs.contains(trackKey)) continue;

            final isRead = _isChapterReadMatch(
              title: title,
              slug: chSlug,
              readChapters: readChapters,
              strictMode: true,
            );

            if (!isRead) {
              countedSlugs.add(trackKey);
              totalUnread++;
            }
          }
        } catch (_) {}
      }
    }
    _unreadNewChaptersCountCache[cacheKey] = totalUnread;
    return totalUnread;
  }

  static Future<void> syncFeedItemsReadStatus({
    required String slug,
    String? source,
    String? modeId,
  }) async {
    _unreadNewChaptersCountCache.clear();
    final m = modeId ?? getActiveContentModeId();
    final clean = _cleanSlug(slug);
    final src = source?.trim().toLowerCase();

    final keys = List<dynamic>.from(_feedBox.keys);
    for (final key in keys) {
      final raw = _feedBox.get(key);
      if (!_isFeedItem(key, raw)) continue;
      if (raw is Map) {
        final itemSlug = (raw['mangaSlug'] as String?)?.trim() ?? '';
        final itemClean = _cleanSlug(itemSlug);
        final itemSrc = (raw['mangaSource'] as String?)?.trim().toLowerCase();
        final itemMode = (raw['modeId'] as String?) ?? ContentMode.defaultNormalId;

        if (m != 'all' && itemMode != m) continue;
        if (src != null && src.isNotEmpty && itemSrc != null && itemSrc.isNotEmpty && itemSrc != src) continue;

        if (itemSlug == slug || (clean.isNotEmpty && (itemClean == clean || itemSlug == clean))) {
          try {
            final item = FeedItem.fromJson(Map<String, dynamic>.from(raw));
            final isDismissed = raw['dismissed'] == true;
            final unread = getUnreadNewChaptersCount(item, ignoreIsNew: true);
            if (unread <= 0 && item.isNew) {
              final updated = item.copyWith(isNew: false);
              await _feedBox.put(key, updated.toJson());
            } else if (unread > 0 && !item.isNew && !isDismissed) {
              final updated = item.copyWith(isNew: true);
              await _feedBox.put(key, updated.toJson());
            }
          } catch (_) {}
        }
      }
    }
  }

  static Future<void> syncAllFeedItemsReadStatus({String? modeId}) async {
    final targetMode = modeId ?? getActiveContentModeId();
    final keys = List<dynamic>.from(_feedBox.keys);
    for (final key in keys) {
      final raw = _feedBox.get(key);
      if (!_isFeedItem(key, raw)) continue;
      if (raw is Map) {
        final itemMode = (raw['modeId'] as String?) ?? ContentMode.defaultNormalId;
        if (targetMode == 'all' || itemMode == targetMode) {
          try {
            final item = FeedItem.fromJson(Map<String, dynamic>.from(raw));
            final isDismissed = raw['dismissed'] == true;
            final unread = getUnreadNewChaptersCount(item, ignoreIsNew: true);
            if (unread <= 0 && item.isNew) {
              final updated = item.copyWith(isNew: false);
              await _feedBox.put(key, updated.toJson());
            } else if (unread > 0 && !item.isNew && !isDismissed) {
              final updated = item.copyWith(isNew: true);
              await _feedBox.put(key, updated.toJson());
            }
          } catch (_) {}
        }
      }
    }
  }

  static Future<void> markFeedItemsReadForManga(
    String mangaSlug, {
    String? source,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final clean = _cleanSlug(mangaSlug);
    final src = source?.trim().toLowerCase();

    final keys = List<dynamic>.from(_feedBox.keys);
    for (final key in keys) {
      final raw = _feedBox.get(key);
      if (!_isFeedItem(key, raw)) continue;
      if (raw is Map) {
        final itemSlug = (raw['mangaSlug'] as String?)?.trim() ?? '';
        final itemClean = _cleanSlug(itemSlug);
        final itemSrc = (raw['mangaSource'] as String?)?.trim().toLowerCase();
        final itemMode = (raw['modeId'] as String?) ?? ContentMode.defaultNormalId;

        if (m != 'all' && itemMode != m) continue;
        if (src != null && src.isNotEmpty && itemSrc != null && itemSrc.isNotEmpty && itemSrc != src) continue;

        if (itemSlug == mangaSlug || (clean.isNotEmpty && (itemClean == clean || itemSlug == clean))) {
          if (raw['isNew'] == true) {
            final map = Map<String, dynamic>.from(raw);
            map['isNew'] = false;
            map['dismissed'] = true;
            await _feedBox.put(key, map);
          }
        }
      }
    }
  }

  /// Returns the count of unread manga items in the feed.
  static int getUnreadFeedCount({String? modeId}) {
    final targetMode = modeId ?? getActiveContentModeId();
    int count = 0;
    for (var key in _feedBox.keys) {
      final raw = _feedBox.get(key);
      if (!_isFeedItem(key, raw)) continue;
      if (raw is Map && raw['isNew'] == true) {
        final itemMode = raw['modeId'] as String? ?? ContentMode.defaultNormalId;
        if (targetMode == 'all' || itemMode == targetMode) {
          try {
            final item = FeedItem.fromJson(Map<String, dynamic>.from(raw));
            if (isFeedItemUnread(item)) {
              count++;
            }
          } catch (_) {
            count++;
          }
        }
      }
    }
    return count;
  }

  /// Returns the total count of unread new chapters in the feed for the notification and tab badge.
  static int getTotalUnreadNewChaptersCount({String? modeId}) {
    final targetMode = modeId ?? getActiveContentModeId();
    int count = 0;
    for (var key in _feedBox.keys) {
      final raw = _feedBox.get(key);
      if (!_isFeedItem(key, raw)) continue;
      if (raw is Map && raw['isNew'] == true) {
        final itemMode = raw['modeId'] as String? ?? ContentMode.defaultNormalId;
        if (targetMode == 'all' || itemMode == targetMode) {
          try {
            final item = FeedItem.fromJson(Map<String, dynamic>.from(raw));
            final unreadCh = getUnreadNewChaptersCount(item);
            if (unreadCh > 0) {
              count += unreadCh;
            } else if (isFeedItemUnread(item)) {
              count += item.newChaptersCount > 0 ? item.newChaptersCount : 1;
            }
          } catch (_) {
            count++;
          }
        }
      }
    }
    return count;
  }

  /// Alias returning count of unread manga items in feed.
  static int getUnreadFeedItemsCount({String? modeId}) => getUnreadFeedCount(modeId: modeId);

  static bool isFeedHeaderVisible() {
    return _settingsBox.get('feed_header_visible', defaultValue: true) as bool;
  }

  static Future<void> setFeedHeaderVisible(bool visible) async {
    await _settingsBox.put('feed_header_visible', visible);
  }

  // --- Tracking Baselines ---

  static Map<String, dynamic>? getTrackBaseline(String slug, {String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final modeSpecific = _feedBox.get('$m::track_$slug');
    if (modeSpecific is Map) {
      return Map<String, dynamic>.from(modeSpecific);
    }
    final raw = _feedBox.get('track_$slug');
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  static Future<void> saveTrackBaseline(
    String slug, {
    required String lastChapterSlug,
    required int totalChapters,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final data = {
      'lastChapterSlug': lastChapterSlug,
      'totalChapters': totalChapters,
      'lastCheckedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _feedBox.put('$m::track_$slug', data);
    await _feedBox.put('track_$slug', data);
  }

  static String _normalizeTitle(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[\W_]+', unicode: true), '');
  }

  /// Memeriksa apakah suatu feed item berasal dari manga yang telah dimigrasi
  /// ke source atau slug baru (misalnya jika source lama error lalu diganti di menu alternatif).
  static FeedItem? resolveMigratedFeedItem(FeedItem item, {String? modeId}) {
    final m = modeId ?? item.modeId ?? getActiveContentModeId();
    // Jika komik ini masih ada di favorit atau riwayat dengan slug dan source yang sama, tidak perlu dimigrasi
    final fav = getFavorite(item.mangaSlug, source: item.mangaSource, modeId: m);
    final hist = getHistoryItem(item.mangaSlug, source: item.mangaSource, modeId: m);
    if (fav != null || hist != null) {
      return null;
    }

    final cleanItemSlug = _cleanSlug(item.mangaSlug);
    final normItemTitle = _normalizeTitle(item.mangaTitle);

    Map<String, dynamic>? match;
    // 1. Cek di favorit apakah ada judul yang cocok atau slug yang sama dengan source berbeda
    final favs = getFavorites(modeId: m);
    for (final f in favs) {
      final fTitle = f['title'] as String? ?? '';
      final fSlug = f['slug'] as String? ?? '';
      final normFTitle = _normalizeTitle(fTitle);
      if (normItemTitle.isNotEmpty && (normFTitle == normItemTitle ||
          (normFTitle.length >= 4 && normItemTitle.length >= 4 &&
              (normFTitle.contains(normItemTitle) || normItemTitle.contains(normFTitle))))) {
        match = f;
        break;
      }
      if (cleanItemSlug.isNotEmpty && _cleanSlug(fSlug) == cleanItemSlug) {
        match = f;
        break;
      }
    }

    // 2. Jika tidak ditemukan di favorit, cek di riwayat
    if (match == null) {
      final hists = getHistory(modeId: m);
      for (final h in hists) {
        final hTitle = h['title'] as String? ?? '';
        final hSlug = h['slug'] as String? ?? '';
        final normHTitle = _normalizeTitle(hTitle);
        if (normItemTitle.isNotEmpty && (normHTitle == normItemTitle ||
            (normHTitle.length >= 4 && normItemTitle.length >= 4 &&
                (normHTitle.contains(normItemTitle) || normItemTitle.contains(normHTitle))))) {
          match = h;
          break;
        }
        if (cleanItemSlug.isNotEmpty && _cleanSlug(hSlug) == cleanItemSlug) {
          match = h;
          break;
        }
      }
    }

    if (match != null) {
      final newSlug = match['slug'] as String? ?? item.mangaSlug;
      final newSource = match['source'] as String? ?? item.mangaSource;
      final newTitle = match['title'] as String? ?? item.mangaTitle;
      final newCover = match['cover'] as String? ?? item.mangaCover;

      if (newSlug != item.mangaSlug || newSource.toLowerCase() != item.mangaSource.toLowerCase()) {
        return item.copyWith(
          mangaSlug: newSlug,
          mangaSource: newSource,
          mangaTitle: newTitle,
          mangaCover: newCover,
        );
      }
    }

    return null;
  }

  /// Memigrasikan semua item umpan (feed) dan tracking baseline dari manga lama ke manga baru.
  static Future<void> migrateFeedAndTrackBaseline({
    required String oldSlug,
    required String oldSource,
    required String newSlug,
    required String newSource,
    required String newTitle,
    String? newCover,
    String? modeId,
  }) async {
    final m = modeId ?? getActiveContentModeId();
    final cleanOld = _cleanSlug(oldSlug);
    final srcOld = oldSource.trim().toLowerCase();
    final srcNew = newSource.trim().toLowerCase();

    // 1. Migrasi Feed Items di _feedBox
    final feedKeys = List<dynamic>.from(_feedBox.keys);
    for (final key in feedKeys) {
      final raw = _feedBox.get(key);
      if (!_isFeedItem(key, raw)) continue;
      if (raw is Map) {
        final itemSlug = (raw['mangaSlug'] as String?)?.trim() ?? '';
        final itemClean = _cleanSlug(itemSlug);
        final itemSrc = (raw['mangaSource'] as String?)?.trim().toLowerCase();

        final slugMatches = (itemSlug == oldSlug ||
            (cleanOld.isNotEmpty && (itemClean == cleanOld || itemSlug == cleanOld)));
        final sourceMatches = (srcOld.isEmpty || itemSrc == null || itemSrc.isEmpty || itemSrc == srcOld);

        if (slugMatches && sourceMatches) {
          try {
            final oldItem = FeedItem.fromJson(Map<String, dynamic>.from(raw));
            final oldKeyStr = key.toString();
            final newId = oldKeyStr.contains(oldSlug)
                ? oldKeyStr.replaceAll(oldSlug, newSlug)
                : '${newSlug}_${oldItem.createdAt}';

            final updatedItem = oldItem.copyWith(
              id: newId,
              mangaSlug: newSlug,
              mangaSource: srcNew.isNotEmpty ? srcNew : oldItem.mangaSource,
              mangaTitle: newTitle,
              mangaCover: newCover ?? oldItem.mangaCover,
            );

            await _feedBox.delete(key);
            await _feedBox.put(newId, updatedItem.toJson());
          } catch (_) {}
        }
      }
    }

    // 2. Migrasi Tracking Baseline
    final baselineKeys = List<dynamic>.from(_feedBox.keys);
    for (final k in baselineKeys) {
      final kStr = k.toString();
      if (kStr == 'track_$oldSlug' || kStr.endsWith('::track_$oldSlug')) {
        final val = _feedBox.get(k);
        final newKey = kStr.replaceFirst('track_$oldSlug', 'track_$newSlug');
        if (_feedBox.get(newKey) == null && val != null) {
          await _feedBox.put(newKey, val);
        }
        await _feedBox.delete(k);
      }
    }

    // 3. Sinkronkan status baca feed item untuk slug & source baru
    await syncFeedItemsReadStatus(
      slug: newSlug,
      source: srcNew,
      modeId: m,
    );

    // 4. Perbarui total unread & badge notification
    final totalUnread = getTotalUnreadNewChaptersCount(modeId: m);
    await TrackerNotificationService.setBadgeCount(totalUnread);
  }

  // =========================================================================
  // --- KOTATSU-REDO SETTINGS & PREFERENCES ---
  // =========================================================================

  // --- Settings & Appearance ---

  static ValueListenable<Box> listenSettings({List<String>? keys}) =>
      _settingsBox.listenable(keys: keys);

  // --- 1. Appearance Settings ---
  static bool isFloatingNavEnabled() =>
      _settingsBox.get('floating_nav_enabled', defaultValue: true) as bool;
  static Future<void> setFloatingNavEnabled(bool enabled) async =>
      await _settingsBox.put('floating_nav_enabled', enabled);

  static bool isShowNavLabels() =>
      _settingsBox.get('show_nav_labels', defaultValue: true) as bool;
  static Future<void> setShowNavLabels(bool show) async =>
      await _settingsBox.put('show_nav_labels', show);

  static bool isAppLockEnabled() =>
      _settingsBox.get('app_lock_enabled', defaultValue: false) as bool;
  static Future<void> setAppLockEnabled(bool enabled) async =>
      await _settingsBox.put('app_lock_enabled', enabled);

  static String? getAppLockPin() =>
      _settingsBox.get('app_lock_pin') as String?;
  static Future<void> setAppLockPin(String? pin) async {
    if (pin == null || pin.isEmpty) {
      await _settingsBox.delete('app_lock_pin');
      await _settingsBox.put('app_lock_enabled', false);
    } else {
      await _settingsBox.put('app_lock_pin', pin);
      await _settingsBox.put('app_lock_enabled', true);
    }
  }

  // --- 2. Sources Settings ---
  static bool isHandleLinksEnabled() =>
      _settingsBox.get('handle_links_enabled', defaultValue: true) as bool;
  static Future<void> setHandleLinksEnabled(bool enabled) async =>
      await _settingsBox.put('handle_links_enabled', enabled);

  static List<String> getDisabledSources({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final customList = _settingsBox.get(_modeKey('disabled_sources', m));
    if (customList is List) {
      return List<String>.from(customList);
    }
    // Fallback to mode definition disabledSources
    final modes = getContentModes();
    final mode = modes.firstWhere(
      (mod) => mod.id == m,
      orElse: () => ContentMode.normal,
    );
    return List<String>.from(mode.disabledSources);
  }

  static bool isSourceEnabled(String sourceId, {String? modeId}) =>
      !getDisabledSources(modeId: modeId).contains(sourceId);

  static Future<void> setSourceEnabled(String sourceId, bool enabled, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    final list = getDisabledSources(modeId: m);
    if (enabled) {
      list.remove(sourceId);
    } else {
      if (!list.contains(sourceId)) list.add(sourceId);
    }
    await _settingsBox.put(_modeKey('disabled_sources', m), list);
  }

  static Future<void> setDisabledSources(List<String> list, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('disabled_sources', m), list);
  }

  // --- 3. Reader Settings ---
  static String getReaderOrientation() =>
      _settingsBox.get('reader_orientation', defaultValue: 'system') as String;
  static Future<void> setReaderOrientation(String orientation) async =>
      await _settingsBox.put('reader_orientation', orientation);

  static bool isDualPageInLandscape() =>
      _settingsBox.get('dual_page_landscape', defaultValue: true) as bool;
  static Future<void> setDualPageInLandscape(bool enabled) async =>
      await _settingsBox.put('dual_page_landscape', enabled);

  static bool isShiftFirstPageCover() =>
      _settingsBox.get('dual_page_shift_first', defaultValue: true) as bool;
  static Future<void> setShiftFirstPageCover(bool enabled) async =>
      await _settingsBox.put('dual_page_shift_first', enabled);

  static bool isKeepScreenOn() =>
      _settingsBox.get('keep_screen_on', defaultValue: true) as bool;
  static Future<void> setKeepScreenOn(bool keep) async =>
      await _settingsBox.put('keep_screen_on', keep);

  // --- 4. Network & Storage Settings ---
  static String getDohProvider() =>
      _settingsBox.get('doh_provider', defaultValue: 'cloudflare') as String;
  static Future<void> setDohProvider(String provider) async =>
      await _settingsBox.put('doh_provider', provider);

  static String getCustomDohUrl() =>
      _settingsBox.get('custom_doh_url', defaultValue: '') as String;
  static Future<void> setCustomDohUrl(String url) async =>
      await _settingsBox.put('custom_doh_url', url.trim());

  // --- Custom Covers ---
  static String _coverKey(String slug, {String? source}) {
    final clean = _cleanSlug(slug).toLowerCase();
    final src = source?.trim().toLowerCase() ?? '';
    return 'custom_cover:${src.isNotEmpty ? "$src:" : ""}$clean';
  }

  static String? getCustomCover(String slug, {String? source}) {
    if (slug.isEmpty) return null;
    final cacheKey = '$source::$slug';
    if (_customCoverCache.containsKey(cacheKey)) {
      return _customCoverCache[cacheKey];
    }
    final key = _coverKey(slug, source: source);
    var path = _settingsBox.get(key) as String?;
    if ((path == null || path.isEmpty) && source != null && source.isNotEmpty) {
      path = _settingsBox.get(_coverKey(slug)) as String?;
    }
    String? validPath;
    if (path != null && path.isNotEmpty) {
      try {
        if (File(path).existsSync()) {
          validPath = path;
        } else {
          _settingsBox.delete(key);
        }
      } catch (_) {}
    }
    _customCoverCache[cacheKey] = validPath;
    return validPath;
  }

  static Future<void> setCustomCover(String slug, String filePath, {String? source}) async {
    _customCoverCache.clear();
    final key = _coverKey(slug, source: source);
    final oldPath = _settingsBox.get(key) as String?;
    if (oldPath != null && oldPath.isNotEmpty && oldPath != filePath) {
      try {
        final oldFile = File(oldPath);
        if (oldFile.existsSync()) oldFile.deleteSync();
      } catch (_) {}
    }
    await _settingsBox.put(key, filePath);
  }

  static Future<void> removeCustomCover(String slug, {String? source}) async {
    _customCoverCache.clear();
    final key = _coverKey(slug, source: source);
    final oldPath = _settingsBox.get(key) as String?;
    if (oldPath != null && oldPath.isNotEmpty) {
      try {
        final oldFile = File(oldPath);
        if (oldFile.existsSync()) oldFile.deleteSync();
      } catch (_) {}
    }
    await _settingsBox.delete(key);
    if (source != null && source.isNotEmpty) {
      await _settingsBox.delete(_coverKey(slug));
    }
  }

  static bool hasCustomCover(String slug, {String? source}) =>
      getCustomCover(slug, source: source) != null;

  // --- Persistent Downloaded Covers Cache ---
  static String _cleanCoverFileName(String slug, {String? source}) {
    final cleanSlug = _cleanSlug(slug).toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final src = (source != null && source.trim().isNotEmpty)
        ? '${source.trim().toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')}_'
        : '';
    return '$src$cleanSlug';
  }

  static String? getSavedCoverPath(String slug, {String? source}) {
    if (slug.isEmpty) return null;
    final baseName = _cleanCoverFileName(slug, source: source);
    final extensions = ['.jpg', '.webp', '.png', '.jpeg'];
    for (final ext in extensions) {
      final file = File('${_cachedCoversDir.path}/$baseName$ext');
      if (file.existsSync() && file.lengthSync() > 100) {
        return file.path;
      }
    }
    // Also try without source if source was provided
    if (source != null && source.isNotEmpty) {
      final slugOnly = _cleanCoverFileName(slug);
      for (final ext in extensions) {
        final file = File('${_cachedCoversDir.path}/$slugOnly$ext');
        if (file.existsSync() && file.lengthSync() > 100) {
          return file.path;
        }
      }
    }
    return null;
  }

  static bool hasSavedCover(String slug, {String? source}) =>
      getSavedCoverPath(slug, source: source) != null;

  static Future<File?> savePersistentCover(
    String slug,
    List<int> bytes, {
    String? source,
    String ext = 'jpg',
  }) async {
    if (slug.isEmpty || bytes.isEmpty) return null;
    try {
      final baseName = _cleanCoverFileName(slug, source: source);
      final safeExt = ext.startsWith('.') ? ext : '.$ext';
      final targetFile = File('${_cachedCoversDir.path}/$baseName$safeExt');
      await targetFile.writeAsBytes(bytes, flush: true);
      return targetFile;
    } catch (e) {
      debugPrint('[LocalStorage] Error saving persistent cover: $e');
      return null;
    }
  }

  static Future<void> ensureCoverCached({
    required String slug,
    required String? coverUrl,
    String? source,
  }) async {
    if (slug.isEmpty || coverUrl == null || coverUrl.trim().isEmpty) return;
    if (hasSavedCover(slug, source: source)) return;

    // 1. Periksa apakah sudah ada di CacheManager memory/disk cache
    try {
      final fileInfo = await MangaCoverCacheManager.instance.getFileFromCache(coverUrl);
      if (fileInfo != null && fileInfo.file.existsSync() && fileInfo.file.lengthSync() > 100) {
        final bytes = await fileInfo.file.readAsBytes();
        await savePersistentCover(slug, bytes, source: source);
        return;
      }
    } catch (_) {}

    // 2. Jika belum ada, download di background dan simpan permanen
    Future.microtask(() async {
      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: refererFor(coverUrl, source: source),
        ));

        Response<List<int>> resp;
        try {
          resp = await dio.get<List<int>>(
            coverUrl,
            options: Options(responseType: ResponseType.bytes),
          );
        } catch (_) {
          // Fallback ke WordPress Photon CDN jika URL asli diblokir ISP / Cloudflare
          final clean = coverUrl.replaceFirst(RegExp(r'-\d+x\d+(?=\.[a-zA-Z0-9]+$)'), '');
          final noScheme = clean.replaceFirst(RegExp(r'^https?://'), '');
          final photonUrl = 'https://i0.wp.com/$noScheme';
          resp = await dio.get<List<int>>(
            photonUrl,
            options: Options(responseType: ResponseType.bytes),
          );
        }

        if (resp.statusCode == 200 && resp.data != null && resp.data!.isNotEmpty) {
          await savePersistentCover(slug, resp.data!, source: source);
        }
      } catch (e) {
        debugPrint('[LocalStorage.ensureCoverCached] Error caching cover for $slug: $e');
      }
    });
  }

  static String getImageProxy() =>
      _settingsBox.get('image_proxy', defaultValue: 'default') as String;
  static Future<void> setImageProxy(String proxy) async =>
      await _settingsBox.put('image_proxy', proxy);

  static bool isSslBypassEnabled() =>
      _settingsBox.get('ssl_bypass_enabled', defaultValue: false) as bool;
  static Future<void> setSslBypassEnabled(bool bypass) async =>
      await _settingsBox.put('ssl_bypass_enabled', bypass);

  static bool isManualProxyEnabled() =>
      _settingsBox.get('manual_proxy_enabled', defaultValue: false) as bool;
  static String getManualProxyHost() =>
      _settingsBox.get('manual_proxy_host', defaultValue: '') as String;
  static int getManualProxyPort() =>
      _settingsBox.get('manual_proxy_port', defaultValue: 8080) as int;
  static String getManualProxyType() =>
      _settingsBox.get('manual_proxy_type', defaultValue: 'HTTP') as String;

  static Future<void> setManualProxy({
    required bool enabled,
    required String host,
    required int port,
    required String type,
  }) async {
    await _settingsBox.put('manual_proxy_enabled', enabled);
    await _settingsBox.put('manual_proxy_host', host);
    await _settingsBox.put('manual_proxy_port', port);
    await _settingsBox.put('manual_proxy_type', type);
  }

  // --- Manga Auto Translator Settings ---
  static bool isAutoTranslateEnabled() =>
      _settingsBox.get('auto_translate_enabled', defaultValue: false) as bool;
  static Future<void> setAutoTranslateEnabled(bool enabled) async =>
      await _settingsBox.put('auto_translate_enabled', enabled);

  static String getTranslatorSourceLang() =>
      _settingsBox.get('translator_source_lang', defaultValue: 'auto') as String;
  static Future<void> setTranslatorSourceLang(String lang) async =>
      await _settingsBox.put('translator_source_lang', lang);

  static String getTranslatorTargetLang() =>
      _settingsBox.get('translator_target_lang', defaultValue: 'id') as String;
  static Future<void> setTranslatorTargetLang(String lang) async =>
      await _settingsBox.put('translator_target_lang', lang);

  static String getTranslatorMode() =>
      _settingsBox.get('translator_mode', defaultValue: 'translated') as String;
  static Future<void> setTranslatorMode(String mode) async =>
      await _settingsBox.put('translator_mode', mode);

  static String getTranslatorEngine() =>
      _settingsBox.get('translator_engine', defaultValue: 'groq') as String;
  static Future<void> setTranslatorEngine(String engine) async =>
      await _settingsBox.put('translator_engine', engine);

  static const String defaultGroqApiKey = '';

  static String getGroqApiKey() =>
      _settingsBox.get('groq_api_key', defaultValue: defaultGroqApiKey) as String;
  static Future<void> setGroqApiKey(String key) async =>
      await _settingsBox.put('groq_api_key', key);

  static String getGroqModel() =>
      _settingsBox.get('groq_model', defaultValue: 'openai/gpt-oss-120b') as String;
  static Future<void> setGroqModel(String model) async =>
      await _settingsBox.put('groq_model', model);

  static bool isTranslatorBubbleInpaintEnabled() =>
      _settingsBox.get('translator_bubble_inpaint', defaultValue: true) as bool;
  static Future<void> setTranslatorBubbleInpaintEnabled(bool enabled) async =>
      await _settingsBox.put('translator_bubble_inpaint', enabled);

  // --- 5. Tracker & Notification Settings ---

  /// true  = belum pernah buka app (fresh install), false = sudah selesai onboarding
  static bool isFirstLaunch() =>
      _settingsBox.get('first_launch_done', defaultValue: false) == false;
  static Future<void> setFirstLaunchDone() async =>
      await _settingsBox.put('first_launch_done', true);

  static bool isTrackerEnabled() =>
      _settingsBox.get('tracker_enabled', defaultValue: true) as bool;
  static Future<void> setTrackerEnabled(bool enabled) async =>
      await _settingsBox.put('tracker_enabled', enabled);

  // --- 6. Security & App Lock Settings ---
  static bool isBiometricEnabled() =>
      _settingsBox.get('biometric_enabled', defaultValue: true) as bool;
  static Future<void> setBiometricEnabled(bool enabled) async =>
      await _settingsBox.put('biometric_enabled', enabled);

  static int getAppLockTimeout() =>
      _settingsBox.get('app_lock_timeout', defaultValue: 0) as int;
  static Future<void> setAppLockTimeout(int minutes) async =>
      await _settingsBox.put('app_lock_timeout', minutes);

  static String getInAppPin() =>
      _settingsBox.get('app_lock_pin', defaultValue: '') as String;
  static Future<void> setInAppPin(String pin) async =>
      await _settingsBox.put('app_lock_pin', pin);

  static bool isIncognitoRecentApps() =>
      _settingsBox.get('incognito_recent_apps', defaultValue: false) as bool;
  static Future<void> setIncognitoRecentApps(bool enabled) async =>
      await _settingsBox.put('incognito_recent_apps', enabled);

  static int getTrackerFrequencyHours() =>
      _settingsBox.get('tracker_frequency_hours', defaultValue: 1) as int;
  static Future<void> setTrackerFrequencyHours(int hours) async =>
      await _settingsBox.put('tracker_frequency_hours', hours);

  static bool isTrackerNotificationEnabled() =>
      _settingsBox.get('tracker_notification_enabled', defaultValue: true) as bool;
  static Future<void> setTrackerNotificationEnabled(bool enabled) async =>
      await _settingsBox.put('tracker_notification_enabled', enabled);

  static bool isTrackerWifiOnly() =>
      _settingsBox.get('tracker_wifi_only', defaultValue: false) as bool;
  static Future<void> setTrackerWifiOnly(bool wifiOnly) async =>
      await _settingsBox.put('tracker_wifi_only', wifiOnly);

  // --- 6. Backup & Restore Data Engine ---
  static Map<String, dynamic> exportBackupData({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final favs = getFavorites(modeId: m);
    final hist = getHistory(modeId: m);
    final categories = getFavoriteCategories(modeId: m);
    final bookmarks = getAllBookmarks(modeId: m);
    final settingsMap = <String, dynamic>{};
    for (final key in _settingsBox.keys) {
      final val = _settingsBox.get(key);
      if (val is String || val is int || val is double || val is bool || val is List) {
        settingsMap[key.toString()] = val;
      }
    }
    return {
      'version': 1,
      'app': 'Kotatsu-Redo',
      'exportedAt': DateTime.now().toIso8601String(),
      'mode_id': m,
      'favorites': favs,
      'history': hist,
      'categories': categories,
      'bookmarks': bookmarks,
      'settings': settingsMap,
    };
  }

  static Future<Map<String, int>> importBackupData(Map<String, dynamic> data, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    int favsCount = 0;
    int histCount = 0;

    // Restore categories
    if (data['categories'] is List) {
      final cats = (data['categories'] as List)
          .whereType<String>()
          .toList();
      if (cats.isNotEmpty) {
        for (final c in cats) {
          await addFavoriteCategory(c, modeId: m);
        }
      }
    }

    // Restore favorites
    if (data['favorites'] is List) {
      for (final raw in data['favorites'] as List) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final slug = item['slug'] as String?;
        final title = item['title'] as String?;
        if (slug != null && title != null) {
          final cat = item['category'] as String? ?? 'Semua kesukaan';
          await saveFavorite(
            slug: slug,
            title: title,
            cover: item['cover'] as String?,
            source: item['source'] as String? ?? 'shinigami',
            category: cat,
            categories: (cat != 'Semua' && cat != 'Semua kesukaan') ? [cat] : <String>[],
            type: item['type'] as String?,
            latestChapter: item['latestChapter'] as String?,
            modeId: m,
          );
          favsCount++;
        }
      }
    }

    // Restore history
    if (data['history'] is List) {
      for (final raw in data['history'] as List) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final slug = item['slug'] as String?;
        final title = item['title'] as String?;
        final chapterSlug = item['chapterSlug'] as String?;
        if (slug != null && title != null && chapterSlug != null) {
          await saveHistory(
            slug: slug,
            title: title,
            cover: item['cover'] as String?,
            chapterSlug: chapterSlug,
            chapterTitle: item['chapterTitle'] as String? ?? chapterSlug,
            page: (item['page'] as num?)?.toInt() ?? 1,
            totalPages: (item['totalPages'] as num?)?.toInt() ?? 1,
            source: item['source'] as String? ?? 'shinigami',
            pageOffset: (item['pageOffset'] as num?)?.toDouble() ?? 0,
            scrollOffset: (item['scrollOffset'] as num?)?.toDouble() ?? 0,
            percent: (item['percent'] as num?)?.toDouble() ?? 0.0,
            totalChapters: (item['totalChapters'] as num?)?.toInt() ?? 1,
            modeId: m,
          );
          histCount++;
        }
      }
    }

    // Restore bookmarks if provided
    if (data['bookmarks'] is List) {
      for (final raw in data['bookmarks'] as List) {
        if (raw is! Map) continue;
        final bm = Map<String, dynamic>.from(raw);
        final slug = bm['slug'] as String?;
        final mTitle = bm['mangaTitle'] as String? ?? slug ?? '';
        final chSlug = bm['chapterSlug'] as String?;
        final chTitle = bm['chapterTitle'] as String? ?? chSlug ?? '';
        final page = (bm['page'] as num?)?.toInt() ?? 1;
        if (slug != null && chSlug != null) {
          await saveBookmark(
            slug: slug,
            mangaTitle: mTitle,
            chapterSlug: chSlug,
            chapterTitle: chTitle,
            page: page,
            modeId: m,
          );
        }
      }
    }

    // Restore select settings if provided
    if (data['settings'] is Map) {
      final settings = Map<String, dynamic>.from(data['settings'] as Map);
      for (final entry in settings.entries) {
        if (entry.key == 'app_password' || entry.key == 'proxy_password') continue;
        await _settingsBox.put(entry.key, entry.value);
      }
    }

    notifyContentModeChanged();
    return {'favorites': favsCount, 'history': histCount};
  }

  static Future<void> putSettingRaw(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  static String? getLastBackupTime() =>
      _settingsBox.get('last_backup_time') as String?;

  static Future<void> setLastBackupTime(DateTime time) async =>
      await _settingsBox.put('last_backup_time', time.toIso8601String());

  static String getAutoBackupFrequency() =>
      _settingsBox.get('auto_backup_frequency', defaultValue: 'off') as String;

  static Future<void> setAutoBackupFrequency(String freq) async =>
      await _settingsBox.put('auto_backup_frequency', freq);

  static Future<void> clearAllLocalData() async {
    await _favoritesBox.clear();
    await _historyBox.clear();
    await _feedBox.clear();
    await clearReadingStats();
  }

  // --- Layanan & Sinkronisasi (Services & Sync) ---

  static const String defaultSyncServerUrl = 'https://sync.kotatsuredo.app';

  static String getSyncServerUrl({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('sync_server_url', m), defaultValue: defaultSyncServerUrl) as String;
  }

  static Future<void> setSyncServerUrl(String url, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('sync_server_url', m), url.trim());
  }

  static String? getSyncEmail({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('sync_email', m)) as String?;
  }

  static Future<void> setSyncEmail(String? email, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    if (email == null || email.isEmpty) {
      await _settingsBox.delete(_modeKey('sync_email', m));
    } else {
      await _settingsBox.put(_modeKey('sync_email', m), email.trim());
    }
  }

  static String? getSyncToken({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('sync_token', m)) as String?;
  }

  static bool isSyncLoggedIn({String? modeId}) {
    final token = getSyncToken(modeId: modeId);
    return token != null && token.isNotEmpty;
  }

  static Future<void> setSyncToken(String? token, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    if (token == null || token.isEmpty) {
      await _settingsBox.delete(_modeKey('sync_token', m));
    } else {
      await _settingsBox.put(_modeKey('sync_token', m), token.trim());
    }
  }

  static bool isSyncEnabled({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final token = getSyncToken(modeId: m);
    return _settingsBox.get(_modeKey('sync_enabled', m), defaultValue: token != null) as bool;
  }

  static Future<void> setSyncEnabled(bool enabled, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('sync_enabled', m), enabled);
  }

  static bool isSyncFavoritesEnabled({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('sync_favorites_enabled', m), defaultValue: true) as bool;
  }

  static Future<void> setSyncFavoritesEnabled(bool enabled, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('sync_favorites_enabled', m), enabled);
  }

  static bool isSyncHistoryEnabled({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('sync_history_enabled', m), defaultValue: true) as bool;
  }

  static Future<void> setSyncHistoryEnabled(bool enabled, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('sync_history_enabled', m), enabled);
  }

  static int getSyncPeriodHours({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('sync_period_hours', m), defaultValue: 6) as int;
  }

  static Future<void> setSyncPeriodHours(int hours, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('sync_period_hours', m), hours);
  }

  static int getLastSyncTime({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    return _settingsBox.get(_modeKey('sync_last_time', m), defaultValue: 0) as int;
  }

  static Future<void> setLastSyncTime(int timestamp, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('sync_last_time', m), timestamp);
  }

  static Map<String, int> getSyncCategoryIds({String? modeId}) {
    final m = modeId ?? getActiveContentModeId();
    final raw = _settingsBox.get(_modeKey('sync_category_ids', m));
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }
    return {};
  }

  static Future<void> saveSyncCategoryIds(Map<String, int> map, {String? modeId}) async {
    final m = modeId ?? getActiveContentModeId();
    await _settingsBox.put(_modeKey('sync_category_ids', m), map);
  }

  static bool isSuggestionsEnabled() {
    return _settingsBox.get('service_suggestions_enabled', defaultValue: true) as bool;
  }

  static Future<void> setSuggestionsEnabled(bool enabled) async {
    await _settingsBox.put('service_suggestions_enabled', enabled);
  }

  static bool isRelatedMangaEnabled() {
    return _settingsBox.get('service_related_manga_enabled', defaultValue: true) as bool;
  }

  static Future<void> setRelatedMangaEnabled(bool enabled) async {
    await _settingsBox.put('service_related_manga_enabled', enabled);
  }

  static bool isReadingStatsEnabled() {
    return _settingsBox.get('service_stats_enabled', defaultValue: true) as bool;
  }

  static Future<void> setReadingStatsEnabled(bool enabled) async {
    await _settingsBox.put('service_stats_enabled', enabled);
  }

  // --- Statistik Membaca (Reading Statistics) ---

  static Future<void> recordReadingStats({
    required String slug,
    required String title,
    required int seconds,
    required int pages,
    bool chapterCompleted = false,
  }) async {
    if (!isReadingStatsEnabled()) return;
    if (seconds <= 0 && pages <= 0) return;

    final currentTotalSeconds = (_settingsBox.get('stats_total_seconds', defaultValue: 0) as num).toInt();
    final currentTotalPages = (_settingsBox.get('stats_total_pages', defaultValue: 0) as num).toInt();
    final currentTotalChapters = (_settingsBox.get('stats_total_chapters', defaultValue: 0) as num).toInt();

    await _settingsBox.put('stats_total_seconds', currentTotalSeconds + seconds);
    await _settingsBox.put('stats_total_pages', currentTotalPages + pages);
    if (chapterCompleted) {
      await _settingsBox.put('stats_total_chapters', currentTotalChapters + 1);
    }

    // Catat statistik per manga
    final rawManga = _settingsBox.get('stats_manga_map');
    Map<String, dynamic> mangaMap = {};
    if (rawManga is Map) {
      mangaMap = Map<String, dynamic>.from(rawManga);
    }
    final existing = mangaMap[slug] is Map ? Map<String, dynamic>.from(mangaMap[slug] as Map) : <String, dynamic>{};
    mangaMap[slug] = {
      'title': title,
      'seconds': ((existing['seconds'] as num?)?.toInt() ?? 0) + seconds,
      'pages': ((existing['pages'] as num?)?.toInt() ?? 0) + pages,
      'chapters': ((existing['chapters'] as num?)?.toInt() ?? 0) + (chapterCompleted ? 1 : 0),
    };
    await _settingsBox.put('stats_manga_map', mangaMap);
  }

  static Map<String, dynamic> getReadingStatsSummary() {
    final totalSeconds = (_settingsBox.get('stats_total_seconds', defaultValue: 0) as num).toInt();
    final totalPages = (_settingsBox.get('stats_total_pages', defaultValue: 0) as num).toInt();
    final totalChapters = (_settingsBox.get('stats_total_chapters', defaultValue: 0) as num).toInt();
    final rawManga = _settingsBox.get('stats_manga_map');
    Map<String, dynamic> mangaMap = {};
    if (rawManga is Map) {
      mangaMap = Map<String, dynamic>.from(rawManga);
    }
    return {
      'totalSeconds': totalSeconds,
      'totalPages': totalPages,
      'totalChapters': totalChapters,
      'mangaMap': mangaMap,
    };
  }

  static double getAverageSecondsPerPage() {
    final totalSeconds = (_settingsBox.get('stats_total_seconds', defaultValue: 0) as num).toInt();
    final totalPages = (_settingsBox.get('stats_total_pages', defaultValue: 0) as num).toInt();
    if (totalPages > 0 && totalSeconds > 0) {
      final avg = totalSeconds / totalPages;
      if (avg >= 3.0 && avg <= 60.0) {
        return avg;
      }
    }
    return 10.0; // Default 10 detik/halaman persis seperti Kotatsu Redo ReadingTimeUseCase
  }

  static Future<void> clearReadingStats() async {
    await _settingsBox.delete('stats_total_seconds');
    await _settingsBox.delete('stats_total_pages');
    await _settingsBox.delete('stats_total_chapters');
    await _settingsBox.delete('stats_manga_map');
  }

  static bool isReadingTimeEstimationEnabled() {
    return _settingsBox.get('service_reading_time_enabled', defaultValue: true) as bool;
  }

  static Future<void> setReadingTimeEstimationEnabled(bool enabled) async {
    await _settingsBox.put('service_reading_time_enabled', enabled);
  }

  static bool isDiscordRpcEnabled() {
    return _settingsBox.get('service_discord_rpc_enabled', defaultValue: false) as bool;
  }

  static Future<void> setDiscordRpcEnabled(bool enabled) async {
    await _settingsBox.put('service_discord_rpc_enabled', enabled);
  }

  static String? getTrackerUsername(String service) {
    return _settingsBox.get('tracker_account_$service') as String?;
  }

  static Future<void> setTrackerUsername(String service, String? username) async {
    if (username == null || username.isEmpty) {
      await _settingsBox.delete('tracker_account_$service');
    } else {
      await _settingsBox.put('tracker_account_$service', username.trim());
    }
  }

  // --- Riwayat Pencarian (Search History) ---

  static List<String> getRecentSearches() {
    final raw = _settingsBox.get('recent_searches');
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  static Future<void> addRecentSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final current = getRecentSearches().where((s) => s.toLowerCase() != trimmed.toLowerCase()).toList();
    current.insert(0, trimmed);
    if (current.length > 20) {
      current.removeRange(20, current.length);
    }
    await _settingsBox.put('recent_searches', current);
  }

  static Future<void> removeRecentSearch(String query) async {
    final current = getRecentSearches().where((s) => s != query).toList();
    await _settingsBox.put('recent_searches', current);
  }

  static Future<void> clearRecentSearches() async {
    await _settingsBox.delete('recent_searches');
  }

  // --- Cache Genre Manga ---

  static List<String>? getCachedMangaGenres(String source, String slug) {
    final key = 'manga_genres_${source}_$slug';
    final raw = _settingsBox.get(key);
    if (raw is List) {
      return List<String>.from(raw);
    }
    return null;
  }

  static Future<void> saveCachedMangaGenres(String source, String slug, List<String> genres) async {
    final key = 'manga_genres_${source}_$slug';
    await _settingsBox.put(key, genres);
  }
}
