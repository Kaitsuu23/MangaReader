import 'package:flutter/material.dart';
import '../../core/storage/local_storage.dart';

class ReaderSettingsScreen extends StatefulWidget {
  const ReaderSettingsScreen({super.key});

  @override
  State<ReaderSettingsScreen> createState() => _ReaderSettingsScreenState();
}

class _ReaderSettingsScreenState extends State<ReaderSettingsScreen> {
  void _showReaderModeDialog() {
    final currentMode = LocalStorage.getReaderMode();
    final modeOptions = [
      {'label': 'Webtoon (Continuous Vertical)', 'value': 'webtoon', 'desc': 'Bergulir mulus ke bawah, ideal untuk Manhwa/Webtoon'},
      {'label': 'RTL Manga (Kanan ke Kiri)', 'value': 'paged_rtl', 'desc': 'Mode tradisional komik Jepang per halaman'},
      {'label': 'LTR (Kiri ke Kanan)', 'value': 'paged_ltr', 'desc': 'Mode membaca barat/manhua per halaman'},
      {'label': 'Vertikal Paged', 'value': 'vertical', 'desc': 'Satu halaman per slide dari atas ke bawah'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Mode Membaca Standar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        children: modeOptions.map((opt) {
          final isSelected = currentMode == opt['value'];
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
            title: Text(opt['label']!, style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
            subtitle: Text(opt['desc']!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            trailing: isSelected ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20) : null,
            onTap: () async {
              await LocalStorage.setReaderMode(opt['value']!);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() {});
            },
          );
        }).toList(),
      ),
    );
  }

  void _showOrientationDialog() {
    final current = LocalStorage.getReaderOrientation();
    final options = [
      {'label': 'Otomatis (Ikuti Sistem)', 'value': 'system', 'desc': 'Mengikuti sensor rotasi perangkat'},
      {'label': 'Terkunci Potret (Portrait)', 'value': 'portrait', 'desc': 'Selalu tegak lurus, nyaman untuk satu tangan'},
      {'label': 'Terkunci Lanskap (Landscape)', 'value': 'landscape', 'desc': 'Layar lebar, ideal untuk double-page spread'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Orientasi Layar Pembaca', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        children: options.map((opt) {
          final isSelected = current == opt['value'];
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
            title: Text(opt['label']!, style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
            subtitle: Text(opt['desc']!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            trailing: isSelected ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20) : null,
            onTap: () async {
              await LocalStorage.setReaderOrientation(opt['value']!);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() {});
            },
          );
        }).toList(),
      ),
    );
  }

  void _showCdnDialog() {
    final currentCdn = LocalStorage.getReaderCdn();
    final cdns = ['cdn1', 'cdn2', 'cdn3'];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Server CDN Gambar Softkomik', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        children: cdns.map((cdn) {
          final isSelected = currentCdn == cdn;
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
            title: Text(cdn.toUpperCase(), style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
            trailing: isSelected ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20) : null,
            onTap: () async {
              await LocalStorage.setReaderCdn(cdn);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() {});
            },
          );
        }).toList(),
      ),
    );
  }

  void _showShinigamiServerDialog() {
    final currentServer = LocalStorage.getShinigamiServer();
    final servers = [
      {'id': 1, 'name': 'Server 1 (storage.shngm.id)'},
      {'id': 2, 'name': 'Server 2 (delivery.shngm.id)'},
      {'id': 3, 'name': 'Server 3 (mirror1.shngm.id)'},
      {'id': 4, 'name': 'Server 4 (mirror2.shngm.id)'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Default Server Shinigami', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        children: servers.map((s) {
          final isSelected = currentServer == s['id'];
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
            title: Text(s['name'] as String, style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
            trailing: isSelected ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20) : null,
            onTap: () async {
              await LocalStorage.setShinigamiServer(s['id'] as int);
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
    final currentMode = LocalStorage.getReaderMode();
    final currentOrientation = LocalStorage.getReaderOrientation();
    final isKeepScreenOn = LocalStorage.isKeepScreenOn();
    final currentCdn = LocalStorage.getReaderCdn();
    final currentShinigamiServer = LocalStorage.getShinigamiServer();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Pembaca'),
      ),
      body: ListView(
        children: [
          // Navigasi & Layar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'Layar & Orientasi',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.screen_rotation_rounded),
            title: const Text('Orientasi Layar'),
            subtitle: Text(
              currentOrientation == 'portrait'
                  ? 'Terkunci Potret (Portrait)'
                  : currentOrientation == 'landscape'
                      ? 'Terkunci Lanskap (Landscape)'
                      : 'Otomatis (Ikuti Sistem)',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showOrientationDialog,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.remove_red_eye_outlined),
            title: const Text('Cegah Layar Mati (Keep Screen On)'),
            subtitle: const Text('Pertahankan layar tetap menyala terus selama membaca komik'),
            value: isKeepScreenOn,
            onChanged: (val) async {
              await LocalStorage.setKeepScreenOn(val);
              setState(() {});
            },
          ),

          const Divider(height: 24),

          // Format Pembaca
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              'Mode & Tata Letak',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.chrome_reader_mode_outlined),
            title: const Text('Mode Membaca Standar'),
            subtitle: Text(
              currentMode == 'webtoon'
                  ? 'Webtoon (Vertikal Mulus)'
                  : currentMode == 'paged_rtl'
                      ? 'RTL (Manga Kanan-Kiri)'
                      : currentMode == 'paged_ltr'
                          ? 'LTR (Kiri-Kanan)'
                          : 'Vertikal Paged',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showReaderModeDialog,
          ),

          const Divider(height: 24),

          // Server CDN
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              'Server Gambar Pembaca',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Server CDN Softkomik'),
            subtitle: Text('${currentCdn.toUpperCase()} (Alternatif bila gambar gagal muat)'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showCdnDialog,
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server Gambar Shinigami'),
            subtitle: Text('Server $currentShinigamiServer (delivery/storage shngm)'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showShinigamiServerDialog,
          ),
        ],
      ),
    );
  }
}
