import 'package:flutter/material.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/models/content_mode.dart';
import 'sync_auth_screen.dart';

class SyncSettingsScreen extends StatefulWidget {
  final String? modeId;
  const SyncSettingsScreen({super.key, this.modeId});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  bool _isSyncing = false;
  String? _syncStatusMessage;

  String get _currentModeId => widget.modeId ?? LocalStorage.getActiveContentModeId();

  ContentMode get _currentMode {
    final modes = LocalStorage.getContentModes();
    return modes.firstWhere(
      (m) => m.id == _currentModeId,
      orElse: () => ContentMode.normal,
    );
  }

  String _formatLastSync(int timestamp) {
    if (timestamp <= 0) return 'Belum pernah disinkronkan';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (isToday) {
      return 'Hari ini pukul $timeStr';
    }
    return '${dt.day}/${dt.month}/${dt.year} $timeStr';
  }

  Future<void> _openAuthScreen() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SyncAuthScreen(modeId: _currentModeId)),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  void _showServerDialog() {
    final currentUrl = LocalStorage.getSyncServerUrl(modeId: _currentModeId);
    final customCtrl = TextEditingController(text: currentUrl);
    bool isTesting = false;
    String? testStatusMessage;
    bool? isOnline;

    final presets = [
      {'name': 'Server Resmi Kotatsu', 'url': 'https://sync.kotatsuredo.app'},
      {'name': 'Cringe Studios Server', 'url': 'https://kotatsu.cringe-studios.com'},
      {'name': 'Dhiksn Server', 'url': 'https://sync.dhiksn.my.id'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Alamat Server Sinkronisasi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gunakan server resmi atau server mandiri yang Anda host di VPS sendiri:',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ...presets.map((p) {
                    final isSel = customCtrl.text.trim() == p['url'];
                    return ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      title: Text(p['name']!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(p['url']!, style: const TextStyle(fontSize: 11)),
                      trailing: isSel ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18) : null,
                      onTap: () {
                        setDialogState(() {
                          customCtrl.text = p['url']!;
                          testStatusMessage = null;
                          isOnline = null;
                        });
                      },
                    );
                  }),
                  const Divider(height: 14),
                  const Text(
                    'Server Mandiri / VPS Kustom:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: customCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'https://sync.domain.com atau http://IP:8080',
                      hintStyle: TextStyle(fontSize: 12.5),
                      prefixIcon: Icon(Icons.dns_outlined, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    onChanged: (_) {
                      if (testStatusMessage != null) {
                        setDialogState(() {
                          testStatusMessage = null;
                          isOnline = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        onPressed: isTesting
                            ? null
                            : () async {
                                final target = customCtrl.text.trim();
                                if (target.isEmpty) return;
                                setDialogState(() {
                                  isTesting = true;
                                  testStatusMessage = null;
                                });
                                final res = await SyncService.testConnection(target);
                                setDialogState(() {
                                  isTesting = false;
                                  isOnline = res.isOnline;
                                  testStatusMessage = res.message;
                                });
                              },
                        icon: isTesting
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.network_check_rounded, size: 15),
                        label: const Text('Uji Koneksi Server', style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ),
                  if (testStatusMessage != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isOnline == true ? Colors.green : Colors.red).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (isOnline == true ? Colors.green : Colors.red).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isOnline == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                            color: isOnline == true ? Colors.green : Colors.red,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              testStatusMessage!,
                              style: TextStyle(
                                fontSize: 11,
                                color: isOnline == true ? Colors.green[800] : Colors.red[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Anda dapat menjalankan kotatsu-syncserver dengan Docker di VPS Anda lalu masukkan IP & port-nya di sini.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () async {
                  final target = customCtrl.text.trim();
                  if (target.isNotEmpty) {
                    await LocalStorage.setSyncServerUrl(SyncService.normalizeUrl(target), modeId: _currentModeId);
                  }
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  setState(() {});
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFrequencyDialog() {
    final current = LocalStorage.getSyncPeriodHours(modeId: _currentModeId);
    final options = [
      {'hours': 1, 'label': 'Setiap 1 jam'},
      {'hours': 3, 'label': 'Setiap 3 jam'},
      {'hours': 6, 'label': 'Setiap 6 jam (Standar Kotatsu)'},
      {'hours': 12, 'label': 'Setiap 12 jam'},
      {'hours': 24, 'label': 'Setiap 24 jam'},
      {'hours': 0, 'label': 'Manual saja (Nonaktif)'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Frekuensi Sinkronisasi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        children: options.map((opt) {
          final isSelected = current == opt['hours'];
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
            title: Text(
              opt['label'] as String,
              style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500),
            ),
            trailing: isSelected ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20) : null,
            onTap: () async {
              await LocalStorage.setSyncPeriodHours(opt['hours'] as int, modeId: _currentModeId);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              setState(() {});
            },
          );
        }).toList(),
      ),
    );
  }

  Future<void> _triggerSync() async {
    setState(() {
      _isSyncing = true;
      _syncStatusMessage = 'Menghubungkan ke server...';
    });

    final res = await SyncService.syncNow(
      modeId: _currentModeId,
      onProgress: (step) {
        if (mounted) {
          setState(() {
            _syncStatusMessage = step;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          content: Text(res.message),
          backgroundColor: res.success ? Colors.green[700] : Colors.red[700],
        ),
      );
    }
  }

  Future<void> _confirmDeleteServerHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hapus Riwayat di Server?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          'Semua riwayat bacaan Anda di server akun cloud dan di perangkat ini akan dihapus secara permanen. Tindakan ini tidak dapat dibatalkan.',
          style: TextStyle(fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Permanen'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isSyncing = true;
      _syncStatusMessage = 'Menghapus riwayat di server...';
    });

    final res = await SyncService.clearServerHistory(modeId: _currentModeId);

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          content: Text(res.message),
          backgroundColor: res.success ? Colors.green[700] : Colors.red[700],
        ),
      );
    }
  }

  Future<void> _confirmDeleteServerFavorites() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hapus Favorit di Server?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          'Semua komik favorit Anda di server akun cloud dan di perangkat ini akan dihapus secara permanen. Kategori Anda akan tetap tersimpan. Tindakan ini tidak dapat dibatalkan.',
          style: TextStyle(fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Permanen'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isSyncing = true;
      _syncStatusMessage = 'Menghapus favorit di server...';
    });

    final res = await SyncService.clearServerFavorites(modeId: _currentModeId);

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncStatusMessage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          content: Text(res.message),
          backgroundColor: res.success ? Colors.green[700] : Colors.red[700],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSyncEnabled = LocalStorage.isSyncEnabled(modeId: _currentModeId);
    final email = LocalStorage.getSyncEmail(modeId: _currentModeId);
    final serverUrl = LocalStorage.getSyncServerUrl(modeId: _currentModeId);
    final lastSyncTime = LocalStorage.getLastSyncTime(modeId: _currentModeId);
    final isSyncFavs = LocalStorage.isSyncFavoritesEnabled(modeId: _currentModeId);
    final isSyncHist = LocalStorage.isSyncHistoryEnabled(modeId: _currentModeId);
    final periodHours = LocalStorage.getSyncPeriodHours(modeId: _currentModeId);

    return Scaffold(
      appBar: AppBar(
        title: Text('Sinkronisasi (${_currentMode.name})'),
      ),
      body: ListView(
        children: [
          // 1. Account status card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSyncEnabled
                              ? theme.colorScheme.primary.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isSyncEnabled ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                          color: isSyncEnabled ? theme.colorScheme.primary : Colors.orange,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isSyncEnabled ? (email ?? 'Akun Terhubung') : 'Belum Masuk Akun',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _currentMode.name,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isSyncEnabled
                                  ? 'Server: $serverUrl'
                                  : 'Masuk akun untuk menyinkronkan data mode ${_currentMode.name}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (!isSyncEnabled)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _openAuthScreen,
                            icon: const Icon(Icons.login_rounded, size: 18),
                            label: const Text('Masuk / Daftar Akun'),
                          ),
                        )
                      else ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                                  contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                                  actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  title: const Text('Keluar Akun?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  content: Text(
                                    'Data lokal mode "${_currentMode.name}" di perangkat Anda tidak akan terhapus, tetapi sinkronisasi akan dihentikan.',
                                    style: const TextStyle(fontSize: 13, height: 1.35),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Batal'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Keluar'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await SyncService.logout(modeId: _currentModeId);
                                setState(() {});
                              }
                            },
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Keluar Akun'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSyncing ? null : _triggerSync,
                            icon: _isSyncing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.sync_rounded, size: 18),
                            label: Text(_isSyncing ? 'Proses...' : 'Sinkronkan'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_syncStatusMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _syncStatusMessage!,
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 2. Data yang disinkronkan
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Data yang Disinkronkan',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Favorit & Kategori'),
            subtitle: const Text('Koleksi manga favorit dan kategori folder Anda'),
            value: isSyncFavs,
            onChanged: (val) async {
              await LocalStorage.setSyncFavoritesEnabled(val, modeId: _currentModeId);
              setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text('Riwayat Bacaan & Progres'),
            subtitle: const Text('Bab terakhir dan posisi halaman yang telah dibaca'),
            value: isSyncHist,
            onChanged: (val) async {
              await LocalStorage.setSyncHistoryEnabled(val, modeId: _currentModeId);
              setState(() {});
            },
          ),

          const Divider(height: 24),

          // 3. Konfigurasi Server & Jadwal
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Konfigurasi Server & Waktu',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dns_rounded),
            title: const Text('Alamat Server'),
            subtitle: Text(serverUrl),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: _showServerDialog,
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Frekuensi Pengecekan'),
            subtitle: Text(
              periodHours > 0 ? 'Setiap $periodHours jam' : 'Manual saja (Nonaktif)',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showFrequencyDialog,
          ),
          ListTile(
            leading: const Icon(Icons.history_toggle_off_rounded),
            title: const Text('Terakhir Disinkronkan'),
            subtitle: Text(_formatLastSync(lastSyncTime)),
          ),

          // 4. Kelola Data Server Sinkronisasi (Hapus dari Cloud Server)
          if (isSyncEnabled) ...[
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Kelola Data Server Sinkronisasi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.delete_sweep_rounded, color: theme.colorScheme.error),
              title: Text(
                'Hapus Riwayat di Server',
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Hapus seluruh riwayat bacaan dari cloud server & perangkat ini'),
              onTap: _confirmDeleteServerHistory,
            ),
            ListTile(
              leading: Icon(Icons.heart_broken_rounded, color: theme.colorScheme.error),
              title: Text(
                'Hapus Favorit di Server',
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Hapus seluruh komik favorit dari cloud server & perangkat ini'),
              onTap: _confirmDeleteServerFavorites,
            ),
          ],

          const Divider(height: 24),

          // 5. VPS Card Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.terminal_rounded, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Dukungan VPS Mandiri (Self-Hosted)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Anda dapat menjalankan server Kotatsu di VPS Anda sendiri menggunakan Docker resmi: "KotatsuApp/kotatsu-syncserver". Masukkan alamat IP/Domain VPS Anda di menu Alamat Server di atas.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
