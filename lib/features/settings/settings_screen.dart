import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';
import 'appearance_settings_screen.dart';
import 'sources_settings_screen.dart';
import 'reader_settings_screen.dart';
import 'network_storage_settings_screen.dart';
import 'tracker_settings_screen.dart';
import 'services_settings_screen.dart';
import 'backup_settings_screen.dart';
import 'about_settings_screen.dart';
import '../security/security_settings_screen.dart';
import '../translator/widgets/translation_settings_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.watch(appThemeModeProvider);
    final isAppLock = LocalStorage.isAppLockEnabled();
    final readerOrientation = LocalStorage.getReaderOrientation();
    final isTracker = LocalStorage.isTrackerEnabled();
    final trackerFreq = LocalStorage.getTrackerFrequencyHours();
    final doh = LocalStorage.getDohProvider();
    final isSync = LocalStorage.isSyncEnabled();
    final syncEmail = LocalStorage.getSyncEmail();

    final themeSummary = currentTheme == 'amoled'
        ? 'AMOLED'
        : currentTheme == 'dark'
            ? 'Gelap'
            : currentTheme == 'light'
                ? 'Terang'
                : 'Sistem';

    final syncSummary = isSync && syncEmail != null
        ? 'Sinkronisasi aktif ($syncEmail)'
        : 'Sinkronisasi riwayat, favorit, dan pelacak';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          // 1. Tampilan (Appearance)
          _buildCategoryTile(
            context: context,
            icon: Icons.palette_outlined,
            title: 'Tampilan',
            subtitle: 'Tema: $themeSummary',
            destination: const AppearanceSettingsScreen(),
          ),

          // Keamanan dan privasi (Security & Privacy)
          _buildCategoryTile(
            context: context,
            icon: Icons.security_rounded,
            title: 'Keamanan dan privasi',
            subtitle: isAppLock
                ? 'Kunci aplikasi: Aktif (Sidik Jari / PIN)'
                : 'Kunci aplikasi: Nonaktif',
            destination: const SecuritySettingsScreen(),
          ),

          // 2. Sumber manga (Remote Sources)
          _buildCategoryTile(
            context: context,
            icon: Icons.public_rounded,
            title: 'Sumber manga',
            subtitle: 'Kelola sumber, pin, dan penanganan tautan web',
            destination: const SourcesSettingsScreen(),
          ),

          // 3. Pengaturan pembaca (Reader Settings)
          _buildCategoryTile(
            context: context,
            icon: Icons.chrome_reader_mode_outlined,
            title: 'Pengaturan pembaca',
            subtitle: 'Orientasi: ${readerOrientation == 'portrait' ? 'Potret' : readerOrientation == 'landscape' ? 'Lanskap' : 'Otomatis'} • Cegah layar mati',
            destination: const ReaderSettingsScreen(),
          ),

          // Manga Auto Translator
          _buildCategoryTile(
            context: context,
            icon: Icons.translate_rounded,
            title: 'Manga Auto Translator',
            subtitle: LocalStorage.isAutoTranslateEnabled()
                ? 'Aktif (${LocalStorage.getTranslatorSourceLang().toUpperCase()} → ${LocalStorage.getTranslatorTargetLang().toUpperCase()}) • Model Offline'
                : 'Penerjemah balon manga otomatis via Google ML Kit',
            onTapCustom: () => TranslationSettingsSheet.show(context),
          ),

          // 4. Penyimpanan dan jaringan (Storage & Network)
          _buildCategoryTile(
            context: context,
            icon: Icons.storage_rounded,
            title: 'Penyimpanan dan jaringan',
            subtitle: 'Pembersihan data • DoH: ${doh != 'none' ? doh.toUpperCase() : 'Nonaktif'}',
            destination: const NetworkStorageSettingsScreen(),
          ),

          // 5. Periksa bab baru (Check for New Chapters / Tracker)
          _buildCategoryTile(
            context: context,
            icon: Icons.sync_rounded,
            title: 'Periksa bab baru',
            subtitle: isTracker ? 'Aktif (tiap $trackerFreq jam) • Notifikasi' : 'Nonaktif',
            destination: const TrackerSettingsScreen(),
          ),

          // 6. Layanan (Services & Integrations)
          _buildCategoryTile(
            context: context,
            icon: Icons.cloud_sync_outlined,
            title: 'Layanan',
            subtitle: syncSummary,
            destination: const ServicesSettingsScreen(),
          ),

          // 7. Pencadangan dan pemulihan (Backup & Restore)
          _buildCategoryTile(
            context: context,
            icon: Icons.settings_backup_restore_rounded,
            title: 'Pencadangan dan pemulihan',
            subtitle: 'Ekspor / impor data favorit, riwayat, dan kategori',
            destination: const BackupSettingsScreen(),
          ),

          // 8. Tentang (About)
          _buildCategoryTile(
            context: context,
            icon: Icons.info_outline_rounded,
            title: 'Tentang',
            subtitle: 'Versi 1.3.5 • Cek pembaruan',
            destination: const AboutSettingsScreen(),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCategoryTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? destination,
    VoidCallback? onTapCustom,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: theme.colorScheme.primary, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
      onTap: () {
        if (onTapCustom != null) {
          onTapCustom();
        } else if (destination != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => destination),
          );
        }
      },
    );
  }
}
