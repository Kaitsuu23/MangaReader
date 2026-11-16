import 'package:flutter/material.dart';
import '../../core/storage/local_storage.dart';

class ReadingStatsScreen extends StatefulWidget {
  const ReadingStatsScreen({super.key});

  @override
  State<ReadingStatsScreen> createState() => _ReadingStatsScreenState();
}

class _ReadingStatsScreenState extends State<ReadingStatsScreen> {
  String _formatDuration(int totalSeconds) {
    if (totalSeconds < 60) {
      return '$totalSeconds detik';
    }
    final minutes = (totalSeconds / 60).floor();
    if (minutes < 60) {
      return '$minutes menit';
    }
    final hours = (minutes / 60).floor();
    final remMinutes = minutes % 60;
    if (remMinutes == 0) {
      return '$hours jam';
    }
    return '$hours jam $remMinutes mnt';
  }

  void _confirmResetStats() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Statistik Membaca?'),
        content: const Text(
          'Seluruh data durasi waktu, jumlah bab, dan halaman yang telah dibaca akan dihapus secara permanen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await LocalStorage.clearReadingStats();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Statistik membaca berhasil direset.')),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = LocalStorage.getReadingStatsSummary();
    final totalSeconds = summary['totalSeconds'] as int;
    final totalPages = summary['totalPages'] as int;
    final totalChapters = summary['totalChapters'] as int;
    final mangaMap = summary['mangaMap'] as Map<String, dynamic>;
    final avgSeconds = LocalStorage.getAverageSecondsPerPage();
    final isStatsEnabled = LocalStorage.isReadingStatsEnabled();

    final mangaEntries = mangaMap.entries.toList()
      ..sort((a, b) {
        final secA = (a.value['seconds'] as num?)?.toInt() ?? 0;
        final secB = (b.value['seconds'] as num?)?.toInt() ?? 0;
        return secB.compareTo(secA);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik Membaca'),
        actions: [
          if (totalSeconds > 0 || totalPages > 0)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Reset Statistik',
              onPressed: _confirmResetStats,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Banner Status Pelacakan
          if (!isStatsEnabled)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.pause_circle_outline_rounded, color: theme.colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pelacakan statistik sedang dinonaktifkan di Pengaturan Layanan.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Grid Kartu Ringkasan
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  theme: theme,
                  icon: Icons.timer_outlined,
                  iconColor: Colors.deepPurple,
                  label: 'Waktu Membaca',
                  value: _formatDuration(totalSeconds),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  theme: theme,
                  icon: Icons.auto_stories_outlined,
                  iconColor: Colors.teal,
                  label: 'Bab Selesai',
                  value: '$totalChapters bab',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  theme: theme,
                  icon: Icons.layers_outlined,
                  iconColor: Colors.blueAccent,
                  label: 'Halaman Dibaca',
                  value: '$totalPages hal',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  theme: theme,
                  icon: Icons.speed_rounded,
                  iconColor: Colors.orange,
                  label: 'Kecepatan Rata-rata',
                  value: '~${avgSeconds.toStringAsFixed(1)} dtk/hal',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          // Judul Komik yang Dibaca
          Text(
            'Komik yang Dibaca (${mangaEntries.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),

          if (mangaEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.bar_chart_rounded,
                      size: 54,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Belum ada statistik bacaan tercatat',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mulai membaca bab manga untuk melihat rincian waktu dan halaman.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...mangaEntries.map((e) {
              final data = e.value;
              final title = data['title'] as String? ?? e.key;
              final sec = (data['seconds'] as num?)?.toInt() ?? 0;
              final pages = (data['pages'] as num?)?.toInt() ?? 0;
              final chaps = (data['chapters'] as num?)?.toInt() ?? 0;

              return Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.menu_book_rounded, color: theme.colorScheme.primary, size: 20),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatDuration(sec)} • $pages halaman • $chaps bab',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              );
            }),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required ThemeData theme,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
