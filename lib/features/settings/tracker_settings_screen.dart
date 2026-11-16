import 'package:flutter/material.dart';
import '../../core/services/tracker_notification_service.dart';
import '../../core/storage/local_storage.dart';
import '../feed/feed_provider.dart';

class TrackerSettingsScreen extends StatefulWidget {
  const TrackerSettingsScreen({super.key});

  @override
  State<TrackerSettingsScreen> createState() => _TrackerSettingsScreenState();
}

class _TrackerSettingsScreenState extends State<TrackerSettingsScreen>
    with WidgetsBindingObserver {
  bool _areNotificationsEnabled = true;
  bool _isIgnoringBatteryOptimizations = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final notifEnabled = await TrackerNotificationService.hasPermission();
    final batteryIgnored = await TrackerNotificationService.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _areNotificationsEnabled = notifEnabled;
        _isIgnoringBatteryOptimizations = batteryIgnored;
      });
    }
  }
  void _showFrequencyDialog() {
    final current = LocalStorage.getTrackerFrequencyHours();
    final options = [
      {'hours': 1, 'label': 'Setiap 1 jam', 'desc': 'Pengecekan sangat cepat (disarankan)'},
      {'hours': 2, 'label': 'Setiap 2 jam', 'desc': 'Pengecekan berkala'},
      {'hours': 6, 'label': 'Setiap 6 jam', 'desc': 'Hemat baterai'},
      {'hours': 12, 'label': 'Setiap 12 jam (2x sehari)', 'desc': 'Pagi dan malam'},
      {'hours': 24, 'label': 'Setiap 24 jam (1x sehari)', 'desc': 'Hanya sekali sehari'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Frekuensi Pengecekan Bab', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        children: options.map((opt) {
          final isSelected = current == opt['hours'];
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
            title: Text(opt['label'] as String, style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
            subtitle: Text(opt['desc'] as String, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            trailing: isSelected ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20) : null,
            onTap: () async {
              await LocalStorage.setTrackerFrequencyHours(opt['hours'] as int);
              await FeedUpdateNotifier.syncTrackedMangaConfig();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() {});
            },
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTrackerEnabled = LocalStorage.isTrackerEnabled();
    final frequencyHours = LocalStorage.getTrackerFrequencyHours();
    final isWifiOnly = LocalStorage.isTrackerWifiOnly();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Periksa Bab Baru'),
      ),
      body: ListView(
        children: [
          // Sakelar Pelacak Background
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'Otomatisasi Pelacak (Tracker)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.sync_rounded),
            title: const Text('Sakelar Pelacak Background'),
            subtitle: const Text('Otomatis periksa rilis bab baru untuk seluruh komik di Favorit'),
            value: isTrackerEnabled,
            onChanged: (val) async {
              await LocalStorage.setTrackerEnabled(val);
              await FeedUpdateNotifier.syncTrackedMangaConfig();
              setState(() {});
            },
          ),
          ListTile(
            enabled: isTrackerEnabled,
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Frekuensi Pengecekan'),
            subtitle: Text(
              frequencyHours == 1
                  ? 'Setiap 1 jam'
                  : frequencyHours == 2
                      ? 'Setiap 2 jam'
                      : frequencyHours == 6
                          ? 'Setiap 6 jam'
                          : frequencyHours == 12
                              ? 'Setiap 12 jam (2x sehari)'
                              : 'Setiap 24 jam (1x sehari)',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: isTrackerEnabled ? _showFrequencyDialog : null,
          ),

          const Divider(height: 24),

          // Pengaturan Notifikasi
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              'Notifikasi & Jaringan',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            enabled: isTrackerEnabled,
            leading: const Icon(Icons.notifications_none_rounded),
            title: const Text('Pengaturan notifikasi'),
            subtitle: Text(
              _areNotificationsEnabled
                  ? 'Anda akan menerima notifikasi tentang pembaruan manga yang Anda baca'
                  : 'Anda tidak akan menerima notifikasi tetapi bab baru akan disorot dalam daftar',
            ),
            onTap: isTrackerEnabled
                ? () async {
                    await TrackerNotificationService.openNotificationSettings();
                    _checkPermissions();
                  }
                : null,
          ),
          ListTile(
            enabled: isTrackerEnabled,
            leading: const Icon(Icons.battery_charging_full_rounded),
            title: const Text('Pengoptimalan Baterai'),
            subtitle: Text(
              _isIgnoringBatteryOptimizations
                  ? 'Tanpa batasan — Yomika dapat memeriksa bab baru otomatis meski aplikasi ditutup'
                  : 'Dibatasi sistem — Ketuk untuk izinkan aktivitas latar belakang agar pembaruan tidak terbunuh',
            ),
            trailing: _isIgnoringBatteryOptimizations
                ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 20)
                : Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 20),
            onTap: isTrackerEnabled
                ? () async {
                    await TrackerNotificationService.requestIgnoreBatteryOptimizations();
                    await _checkPermissions();
                  }
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_rounded),
            title: const Text('Hanya Menggunakan Wi-Fi'),
            subtitle: const Text('Jangan gunakan kuota data seluler untuk pemeriksaan berkala'),
            value: isWifiOnly,
            onChanged: isTrackerEnabled
                ? (val) async {
                    await LocalStorage.setTrackerWifiOnly(val);
                    await FeedUpdateNotifier.syncTrackedMangaConfig();
                    setState(() {});
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
