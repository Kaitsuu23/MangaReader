import 'package:flutter/material.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/models/content_mode.dart';
import 'sync_settings_screen.dart';
import 'reading_stats_screen.dart';

class ServicesSettingsScreen extends StatefulWidget {
  const ServicesSettingsScreen({super.key});

  @override
  State<ServicesSettingsScreen> createState() => _ServicesSettingsScreenState();
}

class _ServicesSettingsScreenState extends State<ServicesSettingsScreen> {
  String _buildSyncSubtitle() {
    final modeId = LocalStorage.getActiveContentModeId();
    final mode = LocalStorage.getContentModes().firstWhere(
      (m) => m.id == modeId,
      orElse: () => ContentMode.normal,
    );
    final isSync = LocalStorage.isSyncEnabled(modeId: modeId);
    final email = LocalStorage.getSyncEmail(modeId: modeId);
    if (!isSync || email == null) {
      return 'Mode: ${mode.name} • Masuk akun untuk sinkronisasi';
    }
    final List<String> targets = [];
    if (LocalStorage.isSyncFavoritesEnabled(modeId: modeId)) targets.add('Favorit');
    if (LocalStorage.isSyncHistoryEnabled(modeId: modeId)) targets.add('Riwayat');
    final targetsStr = targets.isNotEmpty ? ' (${targets.join(', ')})' : '';
    return 'Mode: ${mode.name} • $email$targetsStr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSuggestions = LocalStorage.isSuggestionsEnabled();
    final isRelated = LocalStorage.isRelatedMangaEnabled();
    final isStats = LocalStorage.isReadingStatsEnabled();
    final isReadingTime = LocalStorage.isReadingTimeEstimationEnabled();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Layanan'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          // 1. Sinkronisasi (Sync Settings Navigation)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.cloud_sync_rounded, color: theme.colorScheme.primary, size: 22),
            ),
            title: const Text(
              'Sinkronisasi',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            subtitle: Text(
              _buildSyncSubtitle(),
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
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SyncSettingsScreen()),
              );
              if (mounted) setState(() {});
            },
          ),

          const Divider(height: 24),

          // 2. Saran & Statistik
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Text(
              'Saran & Statistik',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Saran bacaan'),
            subtitle: const Text('Tampilkan rekomendasi bacaan di halaman penjelajahan'),
            value: isSuggestions,
            onChanged: (val) async {
              await LocalStorage.setSuggestionsEnabled(val);
              setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text('Manga terkait'),
            subtitle: const Text('Tampilkan judul yang serupa di layar rincian manga'),
            value: isRelated,
            onChanged: (val) async {
              await LocalStorage.setRelatedMangaEnabled(val);
              setState(() {});
            },
          ),
          ListTile(
            title: const Text('Statistik membaca'),
            subtitle: Text(
              isStats
                  ? 'Kumpulkan statistik bab & waktu membaca (Ketuk untuk melihat)'
                  : 'Pelacakan statistik bacaan dinonaktifkan',
            ),
            trailing: Switch(
              value: isStats,
              onChanged: (val) async {
                await LocalStorage.setReadingStatsEnabled(val);
                setState(() {});
              },
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReadingStatsScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text('Perkiraan waktu membaca'),
            subtitle: const Text('Estimasi durasi waktu yang dibutuhkan untuk menyelesaikan tiap bab'),
            value: isReadingTime,
            onChanged: (val) async {
              await LocalStorage.setReadingTimeEstimationEnabled(val);
              setState(() {});
            },
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
