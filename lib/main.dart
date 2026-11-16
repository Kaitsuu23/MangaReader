import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'core/storage/local_storage.dart';
import 'core/services/tracker_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/app_providers.dart';
import 'core/network/app_http_overrides.dart';
import 'core/network/parser_channel.dart';
import 'features/security/security_service.dart';
import 'features/security/app_lock_screen.dart';
import 'features/splash/splash_screen.dart';

const String trackerPeriodicTaskKey = "org.dhiksn.yomika.tracker_periodic_task";
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await LocalStorage.init();
      if (!LocalStorage.isTrackerEnabled()) {
        return true;
      }
      final found = await TrackerNotificationService.startBackgroundCheck();
      debugPrint('[Workmanager] Background check selesai, update: $found');
      return true;
    } catch (e) {
      debugPrint('[Workmanager] Gagal menjalankan tugas: $e');
      return false;
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 250 << 20; // 250 MB
  PaintingBinding.instance.imageCache.maximumSize = 150;
  await LocalStorage.init();
  AppHttpOverrides.install();
  unawaited(ParserChannel.setDohConfig(
    LocalStorage.getDohProvider(),
    customUrl: LocalStorage.getCustomDohUrl(),
  ));
  await TrackerNotificationService.initLocalNotifications();
  TrackerNotificationService.initNavigation(rootNavigatorKey);

  // Initialize Flutter Workmanager
  try {
    await Workmanager().initialize(
      callbackDispatcher,
    );
  } catch (e) {
    debugPrint('[Workmanager] Inisialisasi gagal: $e');
  }

  // Hide Android system gesture navigation bar while preserving the top status bar
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(
    const ProviderScope(
      child: YomikaApp(),
    ),
  );
}

class YomikaApp extends ConsumerStatefulWidget {
  const YomikaApp({super.key});

  @override
  ConsumerState<YomikaApp> createState() => _YomikaAppState();
}

class _YomikaAppState extends ConsumerState<YomikaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SecurityService.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      SecurityService.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      SecurityService.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeModeStr = ref.watch(appThemeModeProvider);

    ThemeMode themeMode;
    ThemeData? darkTheme;

    switch (themeModeStr) {
      case 'light':
        themeMode = ThemeMode.light;
        break;
      case 'dark':
        themeMode = ThemeMode.dark;
        darkTheme = AppTheme.darkTheme;
        break;
      case 'amoled':
        themeMode = ThemeMode.dark;
        darkTheme = AppTheme.amoledTheme;
        break;
      default:
        themeMode = ThemeMode.system;
        darkTheme = AppTheme.darkTheme;
        break;
    }

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Yomika',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: darkTheme ?? AppTheme.darkTheme,
      themeMode: themeMode,
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: SecurityService.isLockedNotifier,
          builder: (context, isLocked, _) {
            return Stack(
              children: [
                ?child,
                if (isLocked) const AppLockScreen(),
              ],
            );
          },
        );
      },
      home: const SplashScreen(),
    );
  }
}
