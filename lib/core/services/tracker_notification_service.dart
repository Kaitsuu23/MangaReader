import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:workmanager/workmanager.dart';
import '../storage/local_storage.dart';
import '../../features/details/manga_details_screen.dart';

class TrackerNotificationService {
  static const _channel = MethodChannel('org.dhiksn.yomika/notifications');
  static const _deviceChannel = MethodChannel('org.dhiksn.yomika/device');
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _isPluginInitialized = false;

  static const int _badgeNotificationId = 99999;
  static const String _channelUpdatesId = 'tracker_updates';
  static const String _channelUpdatesName = 'Sub-bab baru';
  static const String _channelUpdatesDesc =
      'Anda akan menerima notifikasi tentang pembaruan manga yang Anda baca';

  static Completer<int>? _checkCompleter;
  static void Function(int current, int total, String title)? _onProgressListener;
  static bool _handlerInitialized = false;

  static GlobalKey<NavigatorState>? navigatorKey;

  static void initNavigation(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
    _ensureMethodCallHandler();
    _checkInitialNotification();
  }

  static Future<void> _checkInitialNotification() async {
    try {
      final initial = await _channel.invokeMethod<Map>('getInitialNotification');
      if (initial != null) {
        handleNotificationData(Map<String, dynamic>.from(initial));
      }
    } catch (_) {}
  }

  static void handleNotificationData(Map<String, dynamic> data) {
    final slug = data['slug'] as String?;
    final source = data['source'] as String?;
    final title = data['title'] as String? ?? '';
    final cover = data['cover'] as String?;
    final modeId = data['modeId'] as String?;

    if (slug == null || slug.isEmpty) return;

    if (modeId != null && modeId.isNotEmpty) {
      final currentMode = LocalStorage.getActiveContentModeId();
      if (currentMode != modeId) {
        LocalStorage.setActiveContentModeId(modeId);
      }
    }

    void navigate() {
      final nav = navigatorKey?.currentState;
      if (nav != null) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => MangaDetailsScreen(
              slug: slug,
              source: source ?? '',
              title: title,
              cover: cover,
              origin: 'feed',
            ),
          ),
        );
      } else {
        Future.delayed(const Duration(milliseconds: 300), navigate);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
  }

  /// Initializes flutter_local_notifications plugin and creates notification channels
  static Future<void> initLocalNotifications() async {
    if (_isPluginInitialized) return;
    try {
      const androidSettings =
          AndroidInitializationSettings('@drawable/ic_stat_book_plus');
      const initSettings = InitializationSettings(android: androidSettings);

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            try {
              final map = jsonDecode(payload) as Map<String, dynamic>;
              handleNotificationData(map);
            } catch (_) {
              handleNotificationData({'slug': payload});
            }
          }
        },
      );

      final androidImpl = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImpl != null) {
        const channel = AndroidNotificationChannel(
          _channelUpdatesId,
          _channelUpdatesName,
          description: _channelUpdatesDesc,
          importance: Importance.defaultImportance,
          showBadge: true,
          enableVibration: true,
        );
        await androidImpl.createNotificationChannel(channel);
      }
      _isPluginInitialized = true;
      try {
        await _localNotifications.cancel(_badgeNotificationId);
      } catch (_) {}
    } catch (_) {
      // Ignored in test environment or non-Android platform
    }
  }

  static void _ensureMethodCallHandler() {
    if (_handlerInitialized) return;
    _handlerInitialized = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onProgress':
          final args = call.arguments as Map?;
          if (args != null) {
            final current = (args['current'] as num?)?.toInt() ?? 0;
            final total = (args['total'] as num?)?.toInt() ?? 0;
            final title = args['title'] as String? ?? '';
            _onProgressListener?.call(current, total, title);
          }
          break;
        case 'onCompleted':
          final args = call.arguments as Map?;
          final count = (args?['newUpdatesCount'] as num?)?.toInt() ?? 0;
          if (_checkCompleter != null && !_checkCompleter!.isCompleted) {
            _checkCompleter!.complete(count);
          }
          break;
        case 'onNotificationTapped':
          final args = call.arguments as Map?;
          if (args != null) {
            handleNotificationData(Map<String, dynamic>.from(args));
          }
          break;
      }
    });
  }

  static Future<int> startBackgroundCheck({
    void Function(int current, int total, String title)? onProgress,
  }) async {
    _ensureMethodCallHandler();
    _onProgressListener = onProgress;
    _checkCompleter = Completer<int>();

    try {
      final success = await _channel.invokeMethod<bool>('startBackgroundCheck');
      if (success != true) {
        return 0;
      }
      return await _checkCompleter!.future;
    } catch (_) {
      return 0;
    } finally {
      _onProgressListener = null;
      _checkCompleter = null;
    }
  }

  static Future<bool> isCheckRunning() async {
    try {
      final res = await _channel.invokeMethod<bool>('isCheckRunning');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> cancelCheck() async {
    try {
      await _channel.invokeMethod('cancelCheck');
      if (_checkCompleter != null && !_checkCompleter!.isCompleted) {
        _checkCompleter!.complete(0);
      }
    } catch (_) {}
  }

  static Future<bool> hasPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('hasPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    try {
      await initLocalNotifications();
      final androidImpl = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission();
      if (granted == true) return true;
    } catch (_) {}
    try {
      final res = await _channel.invokeMethod<bool>('requestPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  static Future<void> startForegroundCheck({
    required int max,
    required int current,
    required String message,
  }) async {
    try {
      await _channel.invokeMethod('startForegroundCheck', {
        'max': max,
        'current': current,
        'message': message,
      });
    } catch (_) {}
  }

  static Future<void> showProgress({
    required int max,
    required int current,
    required String message,
  }) async {
    try {
      await _channel.invokeMethod('showProgress', {
        'max': max,
        'current': current,
        'message': message,
      });
    } catch (_) {}
  }

  static Future<void> cancelProgress() async {
    try {
      await _channel.invokeMethod('cancelProgress');
    } catch (_) {}
  }

  static Future<void> showUpdateNotification({
    required String title,
    required int newChaptersCount,
    required List<String> chapters,
    required String slug,
    required String source,
    String? coverUrl,
    int? timestamp,
    String? modeId,
  }) async {
    if (!LocalStorage.isTrackerNotificationEnabled()) return;
    final effectiveModeId = modeId ?? LocalStorage.getActiveContentModeId();
    final notifId = ('${effectiveModeId}_$slug'.hashCode & 0x7FFFFFFF);
    final summary = '+$newChaptersCount Sub-bab Baru';

    // 1. Show notification via flutter_local_notifications with badge count (+N)
    try {
      await initLocalNotifications();
      final androidDetails = AndroidNotificationDetails(
        _channelUpdatesId,
        _channelUpdatesName,
        channelDescription: _channelUpdatesDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@drawable/ic_stat_book_plus',
        number: newChaptersCount, // Sets launcher badge and notification counter
        channelShowBadge: true,
        subText: '+$newChaptersCount bab baru',
        styleInformation: InboxStyleInformation(
          chapters.take(6).toList(),
          contentTitle: summary,
          summaryText: title,
        ),
      );
      final details = NotificationDetails(android: androidDetails);
      await _localNotifications.show(
        notifId,
        title,
        summary,
        details,
        payload: jsonEncode({
          'action': 'open_manga_detail',
          'slug': slug,
          'source': source,
          'title': title,
          'cover': coverUrl,
          'modeId': effectiveModeId,
        }),
      );
    } catch (_) {}

    // 2. Also invoke native channel for OEM launcher broadcasts
    try {
      await _channel.invokeMethod('showUpdateNotification', {
        'title': title,
        'newChaptersCount': newChaptersCount,
        'chapters': chapters,
        'slug': slug,
        'source': source,
        'coverUrl': coverUrl,
        'timestamp': timestamp,
        'modeId': effectiveModeId,
      });
    } catch (_) {}
  }

  static Future<void> setBadgeCount(int count) async {
    // 1. Update launcher badge via app_badge_plus (Modern ShortcutBadger for Android & iOS)
    try {
      final isSupported = await AppBadgePlus.isSupported();
      if (isSupported) {
        await AppBadgePlus.updateBadge(count > 0 ? count : 0);
      } else if (count <= 0) {
        await AppBadgePlus.updateBadge(0);
      }
    } catch (_) {}

    // 2. Broadcast OEM badge to native launcher (Xiaomi, Samsung, Sony, Huawei, Vivo, Oppo)
    try {
      await _channel.invokeMethod('setBadgeCount', {'count': count});
    } catch (_) {}

    // 3. Batalkan notifikasi ringkasan umpan (_badgeNotificationId) agar tidak muncul di tray
    try {
      await initLocalNotifications();
      await _localNotifications.cancel(_badgeNotificationId);
    } catch (_) {}
  }

  static Future<void> showSummaryNotification({
    required int totalNewManga,
    required int totalNewChapters,
    required List<String> lines,
    List<String>? titles,
  }) async {
    if (!LocalStorage.isTrackerNotificationEnabled()) return;
    final summary = '+$totalNewChapters Sub-bab Baru';

    // 1. Show notification via flutter_local_notifications
    try {
      await initLocalNotifications();
      final androidDetails = AndroidNotificationDetails(
        _channelUpdatesId,
        _channelUpdatesName,
        channelDescription: _channelUpdatesDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@drawable/ic_stat_book_plus',
        number: totalNewChapters, // Sets launcher badge number
        channelShowBadge: true,
        subText: '+$totalNewChapters bab baru',
        styleInformation: InboxStyleInformation(
          lines.take(8).toList(),
          contentTitle: summary,
          summaryText: '+$totalNewChapters bab baru',
        ),
      );
      final details = NotificationDetails(android: androidDetails);
      await _localNotifications.show(
        1002, // Summary notification ID
        summary,
        lines.join(', '),
        details,
      );
    } catch (_) {}

    // 2. Also invoke native channel
    try {
      await _channel.invokeMethod('showSummaryNotification', {
        'totalNewManga': totalNewManga,
        'totalNewChapters': totalNewChapters,
        'lines': lines,
        'titles': titles ?? lines,
      });
    } catch (_) {}
  }

  static const String _workmanagerTaskKey = "org.dhiksn.yomika.tracker_periodic_task";

  static Future<void> syncTrackerConfig({
    required bool enabled,
    required int frequencyHours,
    required bool wifiOnly,
    required List<Map<String, dynamic>> items,
  }) async {
    // 1. Schedule via Flutter Workmanager library
    try {
      if (enabled) {
        await Workmanager().registerPeriodicTask(
          _workmanagerTaskKey,
          "checkNewChaptersTask",
          frequency: Duration(hours: frequencyHours.clamp(1, 48)),
          constraints: Constraints(
            networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
          ),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        );
      } else {
        await Workmanager().cancelByUniqueName(_workmanagerTaskKey);
      }
    } catch (e) {
      debugPrint('[TrackerNotificationService] Workmanager error: $e');
    }

    // 2. Also invoke native Android channel
    try {
      await _channel.invokeMethod('syncTrackerConfig', {
        'enabled': enabled,
        'frequencyHours': frequencyHours,
        'wifiOnly': wifiOnly,
        'items': items,
      });
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getPendingFeedUpdates() async {
    try {
      final res = await _channel.invokeMethod('getPendingFeedUpdates');
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> getPendingBaselines() async {
    try {
      final res = await _channel.invokeMethod('getPendingBaselines');
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final res = await _deviceChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final res = await _deviceChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
