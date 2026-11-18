import 'package:flutter/material.dart';
import '../../core/services/tracker_notification_service.dart';
import '../../core/storage/local_storage.dart';
import '../main/main_screen.dart';
import '../settings/sync_auth_screen.dart';

/// Layar setup pertama kali — muncul sekali saat fresh install.
/// Menawarkan shortcut: login akun sinkronisasi, izin notifikasi, dan battery optimization.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool? _notifGranted;
  bool? _batteryIgnored;
  bool _syncLoggedIn = false;
  bool _finishing = false;

  // Scale tombol saat ditekan: 1.0 → 0.94
  late final AnimationController _btnController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
  );
  late final Animation<double> _btnScale = Tween<double>(begin: 1.0, end: 0.94)
      .animate(CurvedAnimation(parent: _btnController, curve: Curves.easeInOut));

  // Fade-out seluruh layar saat navigasi ke MainScreen
  late final AnimationController _exitController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _exitOpacity =
      Tween<double>(begin: 1.0, end: 0.0).animate(
    CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _btnController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final notif = await TrackerNotificationService.hasPermission();
    final battery =
        await TrackerNotificationService.isIgnoringBatteryOptimizations();
    final loggedIn = LocalStorage.isSyncLoggedIn();
    if (!mounted) return;
    setState(() {
      _notifGranted = notif;
      _batteryIgnored = battery;
      _syncLoggedIn = loggedIn;
    });
  }

  // ── Aksi per kartu ───────────────────────────────────────────────────────

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

  // ── Tombol animasi ───────────────────────────────────────────────────────

  void _onTapDown(TapDownDetails _) {
    if (!_finishing) _btnController.forward();
  }

  Future<void> _onTapUp(TapUpDetails _) async {
    await _btnController.reverse();
    await _finish();
  }

  Future<void> _onTapCancel() async {
    await _btnController.reverse();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await LocalStorage.setFirstLaunchDone();
    // Fade out layar ini
    await _exitController.forward();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const MainScreen(),
        // MainScreen slide up + fade in
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.055),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ));
          final fade = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
          );
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 420),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return FadeTransition(
      opacity: _exitOpacity,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Column(
            children: [
              // ── Konten utama (scrollable) ────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: icon app + judul
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

                      // Kartu: Akun Sinkronisasi
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
                        statusColor: _syncLoggedIn
                            ? Colors.green
                            : cs.onSurfaceVariant,
                        statusSize: _syncLoggedIn ? 22 : 16,
                        badgeLabel: _syncLoggedIn ? null : 'Opsional',
                        onTap: _syncLoggedIn ? null : _handleSync,
                        enabled: !_syncLoggedIn,
                      ),

                      const SizedBox(height: 12),

                      // Kartu: Notifikasi
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

                      // Kartu: Optimasi Baterai
                      _SetupCard(
                        icon: Icons.battery_charging_full_rounded,
                        iconColor: const Color(0xFF4CAF50),
                        iconBg:
                            const Color(0xFF4CAF50).withValues(alpha: 0.15),
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
                        onTap:
                            _batteryIgnored == true ? null : _handleBattery,
                        enabled: _batteryIgnored != true,
                      ),

                      const SizedBox(height: 24),

                      // Catatan kecil
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

              // ── Tombol "Mulai Membaca" ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: GestureDetector(
                  onTapDown: _finishing ? null : _onTapDown,
                  onTapUp: _finishing ? null : _onTapUp,
                  onTapCancel: _finishing ? null : _onTapCancel,
                  child: AnimatedBuilder(
                    animation: _btnScale,
                    builder: (context, child) =>
                        Transform.scale(scale: _btnScale.value, child: child),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _finishing
                            ? cs.primary.withValues(alpha: 0.7)
                            : cs.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _finishing
                            ? []
                            : [
                                BoxShadow(
                                  color: cs.primary.withValues(alpha: 0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                      ),
                      alignment: Alignment.center,
                      child: _finishing
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: cs.onPrimary,
                              ),
                            )
                          : Text(
                              'Mulai Membaca',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: cs.onPrimary,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widget kartu setup ────────────────────────────────────────────────────────

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
