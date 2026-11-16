import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../core/storage/local_storage.dart';
import '../../core/network/parser_channel.dart';
import '../../core/network/app_http_overrides.dart';
import '../../shared/widgets/sliced_page_image.dart';

class NetworkStorageSettingsScreen extends StatefulWidget {
  const NetworkStorageSettingsScreen({super.key});

  @override
  State<NetworkStorageSettingsScreen> createState() => _NetworkStorageSettingsScreenState();
}

class _NetworkStorageSettingsScreenState extends State<NetworkStorageSettingsScreen> {
  void _showDohDialog() {
    final current = LocalStorage.getDohProvider();
    final options = [
      {'label': 'Nonaktif (DNS Sistem)', 'value': 'none', 'desc': 'Menggunakan DNS dari operator/ISP Anda'},
      {'label': 'Cloudflare DNS (1.1.1.1)', 'value': 'cloudflare', 'desc': 'DNS cepat, aman, dan anti-sensor'},
      {'label': 'Google Public DNS (8.8.8.8)', 'value': 'google', 'desc': 'DNS global stabil dari Google'},
      {'label': 'AdGuard DNS', 'value': 'adguard', 'desc': 'DNS dengan proteksi filter iklan dan tracker'},
      {'label': 'Quad9 DNS', 'value': 'quad9', 'desc': 'DNS privat dengan proteksi malware'},
      {'label': 'Kustom DoH (URL Sendiri)', 'value': 'custom', 'desc': 'Gunakan server DoH kustom (mis. NextDNS, dsb)'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('DNS over HTTPS (DoH)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              Navigator.pop(ctx);
              if (opt['value'] == 'custom') {
                _showCustomDohDialog();
              } else {
                await LocalStorage.setDohProvider(opt['value']!);
                await ParserChannel.setDohConfig(opt['value']!);
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                    content: Text(opt['value'] == 'none'
                        ? 'DoH dinonaktifkan (DNS Sistem aktif)'
                        : 'DoH aktif: ${opt['label']}'),
                  ),
                );
              }
            },
          );
        }).toList(),
      ),
    );
  }

  void _showCustomDohDialog() {
    final controller = TextEditingController(text: LocalStorage.getCustomDohUrl());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Server DoH Kustom', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan endpoint URL DNS over HTTPS (DoH):',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'https://dns.nextdns.io/xxxxxx',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await LocalStorage.setDohProvider('custom');
                await LocalStorage.setCustomDohUrl(url);
                await ParserChannel.setDohConfig('custom', customUrl: url);
              } else {
                await LocalStorage.setDohProvider('none');
                await ParserChannel.setDohConfig('none');
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() {});
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                  content: Text(url.isNotEmpty
                      ? 'DoH Kustom aktif: $url'
                      : 'DoH dinonaktifkan'),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showImageProxyDialog() {
    final current = LocalStorage.getImageProxy();
    final options = [
      {'label': 'Bawaan Otomatis (wsrv.nl fallback)', 'value': 'default', 'desc': 'Membuka gambar langsung, jika 403/404 otomatis gunakan wsrv.nl'},
      {'label': 'Paksa Gambar via wsrv.nl', 'value': 'wsrv', 'desc': 'Selalu kompres dan lewatkan gambar melalui proxy CDN wsrv.nl'},
      {'label': 'Langsung (Tanpa Proxy)', 'value': 'none', 'desc': 'Hanya unduh gambar langsung dari server sumber'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Proxy Gambar (Image Proxy)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              await LocalStorage.setImageProxy(opt['value']!);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() {});
            },
          );
        }).toList(),
      ),
    );
  }

  void _showManualProxyDialog() {
    final hostController = TextEditingController(text: LocalStorage.getManualProxyHost());
    final portController = TextEditingController(text: LocalStorage.getManualProxyPort().toString());
    String type = LocalStorage.getManualProxyType();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Konfigurasi Proxy Manual', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('Protokol:', style: TextStyle(fontSize: 13.5)),
                  const SizedBox(width: 14),
                  DropdownButton<String>(
                    value: type,
                    isDense: true,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    items: const [
                      DropdownMenuItem(value: 'HTTP', child: Text('HTTP')),
                      DropdownMenuItem(value: 'SOCKS5', child: Text('SOCKS5')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => type = val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: hostController,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  labelText: 'Alamat Host / IP',
                  hintText: '127.0.0.1',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: portController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '8080',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                final host = hostController.text.trim();
                final port = int.tryParse(portController.text.trim()) ?? 8080;
                await LocalStorage.setManualProxy(
                  enabled: host.isNotEmpty,
                  host: host,
                  port: port,
                  type: type,
                );
                AppHttpOverrides.install();
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                setState(() {});
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text(host.isNotEmpty ? 'Proxy disimpan ($type $host:$port)' : 'Proxy dinonaktifkan')),
                );
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Bersihkan Riwayat Baca', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          'Hapus semua riwayat membaca komik secara permanen?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalStorage.clearHistory();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Riwayat membaca berhasil dibersihkan')),
              );
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _confirmClearFeed() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Bersihkan Umpan Pembaruan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          'Hapus semua daftar pembaruan di Umpan?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalStorage.clearFeed();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Umpan pembaruan berhasil dibersihkan')),
              );
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentDoh = LocalStorage.getDohProvider();
    final currentImageProxy = LocalStorage.getImageProxy();
    final isSslBypass = LocalStorage.isSslBypassEnabled();
    final isManualProxy = LocalStorage.isManualProxyEnabled();
    final proxyHost = LocalStorage.getManualProxyHost();
    final proxyPort = LocalStorage.getManualProxyPort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Penyimpanan & Jaringan'),
      ),
      body: ListView(
        children: [
          // Pembersihan Data (Data Cleanup)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'Pembersihan Data (Data Cleanup)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.image_not_supported_outlined),
            title: const Text('Hapus Cache Gambar & Cover'),
            subtitle: const Text('Bersihkan memori disk cache cover manga dan thumbnail'),
            trailing: const Icon(Icons.delete_sweep_outlined, size: 20),
            onTap: () async {
              await DefaultCacheManager().emptyCache();
              await PageSliceCache.instance.clear();
              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Cache gambar berhasil dibersihkan')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('Hapus Riwayat Baca'),
            subtitle: const Text('Bersihkan seluruh daftar riwayat komik yang telah dibaca'),
            trailing: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
            onTap: _confirmClearHistory,
          ),
          ListTile(
            leading: const Icon(Icons.rss_feed_rounded),
            title: const Text('Bersihkan Umpan Pembaruan'),
            subtitle: const Text('Kosongkan semua pemberitahuan bab baru di tab Umpan'),
            trailing: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 20),
            onTap: _confirmClearFeed,
          ),

          const Divider(height: 24),

          // Proxy & Keamanan Jaringan
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              'Proxy & Keamanan Jaringan',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.security_rounded),
            title: const Text('DNS over HTTPS (DoH)'),
            subtitle: Text(
              currentDoh == 'cloudflare'
                  ? 'Cloudflare (1.1.1.1)'
                  : currentDoh == 'google'
                      ? 'Google Public DNS (8.8.8.8)'
                      : currentDoh == 'adguard'
                          ? 'AdGuard DNS'
                          : currentDoh == 'quad9'
                              ? 'Quad9 DNS'
                              : currentDoh == 'custom'
                                  ? 'Kustom (${LocalStorage.getCustomDohUrl()})'
                                  : 'Nonaktif (DNS Sistem)',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showDohDialog,
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Proxy Gambar (Image Proxy)'),
            subtitle: Text(
              currentImageProxy == 'wsrv'
                  ? 'Selalu via wsrv.nl'
                  : currentImageProxy == 'none'
                      ? 'Direct (Tanpa Proxy)'
                      : 'Bawaan Otomatis (Fallback wsrv.nl)',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showImageProxyDialog,
          ),
          ListTile(
            leading: const Icon(Icons.alt_route_rounded),
            title: const Text('Proxy Manual (HTTP / SOCKS)'),
            subtitle: Text(
              isManualProxy && proxyHost.isNotEmpty
                  ? 'Aktif: $proxyHost:$proxyPort'
                  : 'Nonaktif (Koneksi langsung)',
            ),
            trailing: const Icon(Icons.tune_rounded, size: 20),
            onTap: _showManualProxyDialog,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_open_rounded),
            title: const Text('Abaikan Galat SSL (Bypass SSL)'),
            subtitle: const Text('Lewati sertifikat SSL tidak valid atau expired pada web manga'),
            value: isSslBypass,
            onChanged: (val) async {
              await LocalStorage.setSslBypassEnabled(val);
              AppHttpOverrides.install();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
