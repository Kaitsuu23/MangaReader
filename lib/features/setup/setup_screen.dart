import 'package:flutter/material.dart';
import '../../core/services/tracker_notification_service.dart';
import '../../core/storage/local_storage.dart';
import '../../features/main/main_screen.dart';
import '../../features/settings/sync_auth_screen.dart';

/// Layar setup pertama kali — muncul sekali saat fresh install.
/// Menawarkan shortcut: login akun sinkronisasi, izin notifikasi, dan battery optimization.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  // Status masing-masing item — dikosongkan true/false setelah dicek
  bool? _notifGranted;
  bool? _batteryIgnored;
  bool _syncLoggedIn = false;

  // Mencegah double-tap tombol "Mulai"
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Di-refresh saat user kembali dari Settings atau dari auth screen
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final notif = await TrackerNotificationService.hasPermission();
    final battery = await TrackerNotificationService.isIgnoringBatteryOptimizations();
    final loggedIn = LocalStorage.isSyncLoggedIn();
    if (mounted) {
      setState(() {
        _notifGranted = notif;
        _batteryIgnored = battery;
        _syncLoggedIn = loggedIn;
      });
    }
  }

  // ── Aksi per item ────────────────────────────────────────────────────────

  Future<void> _handleNotification() async {
    if (_notifGranted == true) {
      await TrackerNotificationService.openNotificationSettings();
    } else {
      await TrackerNotificationService.requestPermission();
    }
    await _refreshStatus();
  }

  Future<void> _handleBattery() async {
    if (_batteryIgnored == true) return;
    await TrackerNotificationService.requestIgnoreBatteryOptimizations();
    await _refreshStatus();
  }

  Future<void> _handleSync() async {
    if (_syncLoggedIn) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SyncAuthScreen()),
    );
    if (result == true) await _refreshStatus();
  }

  // ── Navigasi ke MainScreen ───────────────────────────────────────────────

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await LocalStorage.setFirstLaunchDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ikon + judul
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/icon.png',
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selamat datang di Yomika',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Siapkan beberapa hal sebelum mulai',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // ── Kartu Akun Sinkronisasi ────────────────────────────
                    _SetupCard(
                      icon: Icons.sync_rounded,
                      iconColor: cs.primary,
                      iconBg: cs.primaryContainer,
                      title: 'Akun Sinkronisasi',
                      subtitle: _syncLoggedIn
                          ? 'Terhubung — data komik tersinkron otomatis'
                          : 'Simpan progress baca & favorit ke cloud agar tidak hilang',
                      statusIcon: _syncLoggedIn
                          ? Icons.check_circle_rounded
                          : Icons.arrow_forward_ios_rounded,
                      statusColor: _syncLoggedIn ? Colors.green : cs.onSurfaceVariant,
                      statusSize: _syncLoggedIn ? 22 : 16,
                      badgeLabel: _syncLoggedIn ? null : 'Opsional',
                      onTap: _syncLoggedIn ? null : _handleSync,
                      enabled: !_syncLoggedIn,
                    ),

                    const SizedBox(height: 12),

                    // ── Kartu Notifikasi ────────────────────────────────────
                    _SetupCard(
                      icon: Icons.notifications_active_rounded,
                      iconColor: cs.secondary,
                      iconBg: cs.secondaryContainer,
                      title: 'Notifikasi Bab Baru',
                      subtitle: _notifGranted == null
                          ? 'Memeriksa izin...'
                          : _notifGranted!
                              ? 'Izin diberikan — Anda akan diberitahu saat bab baru terbit'
                              : 'Izinkan Yomika mengirim notifikasi saat bab baru tersedia',
                      statusIcon: _notifGranted == null
                          ? Icons.hourglass_empty_rounded
                          : _notifGranted!
                              ? Icons.check_circle_rounded
                              : Icons.arrow_forward_ios_rounded,
                      statusColor: _notifGranted == null
                          ? cs.onSurfaceVariant
                          : _notifGranted!
                              ? Colors.green
                              : cs.onSurfaceVariant,
                      statusSize: _notifGranted == true ? 22 : 16,
                      badgeLabel: 'Disarankan',
                      badgeColor: cs.secondary,
                      onTap: _handleNotification,
                      enabled: true,
                    ),

                    const SizedBox(height: 12),

                    // ── Kartu Baterai ───────────────────────────────────────
                    _SetupCard(
                      icon: Icons.battery_charging_full_rounded,
                      iconColor: const Color(0xFF4CAF50),
                      iconBg: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                      title: 'Optimasi Baterai',
                      subtitle: _batteryIgnored == null
                          ? 'Memeriksa izin...'
                          : _batteryIgnored!
                              ? 'Tanpa batasan — pelacak berjalan lancar di latar belakang'
                              : 'Izinkan aktivitas latar belakang agar pengecekan bab baru tidak terhenti',
                      statusIcon: _batteryIgnored == null
                          ? Icons.hourglass_empty_rounded
                          : _batteryIgnored!
                              ? Icons.check_circle_rounded
                              : Icons.warning_amber_rounded,
                      statusColor: _batteryIgnored == null
                          ? cs.onSurfaceVariant
                          : _batteryIgnored!
                              ? Colors.green
                              : cs.error,
                      statusSize: 22,
                      badgeLabel: 'Disarankan',
                      badgeColor: const Color(0xFF4CAF50),
                      onTap: _batteryIgnored == true ? null : _handleBattery,
                      enabled: _batteryIgnored != true,
                    ),

                    const SizedBox(height: 24),

                    // Note kecil di bawah kartu
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Semua pengaturan ini bisa diubah kapan saja dari menu Pengaturan.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Footer — Tombol Mulai ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: FilledButton(
                onPressed: _finishing ? null : _finish,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _finishing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Mulai Membaca',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Komponen kartu setup ───────────────────────────────────────────────────────

class _SetupCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final IconData statusIcon;
  final Color statusColor;
  final double statusSize;
  final String? badgeLabel;
  final Color? badgeColor;
  final VoidCallback? onTap;
  final bool enabled;

  const _SetupCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.statusIcon,
    required this.statusColor,
    required this.statusSize,
    this.badgeLabel,
    this.badgeColor,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Ikon kiri
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),

              // Teks tengah
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: enabled
                                ? null
                                : cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        if (badgeLabel != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? cs.primary)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeLabel!,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: badgeColor ?? cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Status icon kanan
              Icon(statusIcon, color: statusColor, size: statusSize),
            ],
          ),
        ),
      ),
    );
  }
}
