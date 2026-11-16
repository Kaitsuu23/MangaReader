import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';

class AppearanceSettingsScreen extends ConsumerStatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  ConsumerState<AppearanceSettingsScreen> createState() => _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends ConsumerState<AppearanceSettingsScreen> {
  void _showThemeDialog() {
    final currentTheme = ref.read(appThemeModeProvider);
    final themeOptions = [
      {'label': 'Ikuti Sistem', 'value': 'system', 'desc': 'Mengikuti tema perangkat Android Anda'},
      {'label': 'Mode Terang (Light)', 'value': 'light', 'desc': 'Tema terang yang bersih dan cerah'},
      {'label': 'Mode Gelap (Dark)', 'value': 'dark', 'desc': 'Mengurangi ketegangan mata di malam hari'},
      {'label': 'AMOLED (Pure Black)', 'value': 'amoled', 'desc': 'Latar belakang hitam murni hemat daya'},
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SimpleDialog(
          title: const Text('Tema Aplikasi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          children: themeOptions.map((opt) {
            final isSelected = currentTheme == opt['value'];
            return ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
              title: Text(
                opt['label']!,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                opt['desc']!,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
              trailing: isSelected ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 20) : null,
              onTap: () {
                ref.read(appThemeModeProvider.notifier).setTheme(opt['value']!);
                Navigator.pop(ctx);
                setState(() {});
              },
            );
          }).toList(),
        );
      },
    );
  }

  void _showPinDialog() {
    final pinController = TextEditingController();
    final currentPin = LocalStorage.getAppLockPin();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          currentPin == null ? 'Buat PIN Kunci Aplikasi' : 'Ubah PIN Kunci Aplikasi',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan 4 digit PIN keamanan:',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
                counterText: '',
                hintText: '••••',
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
              final pin = pinController.text.trim();
              if (pin.length == 4) {
                await LocalStorage.setAppLockPin(pin);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                setState(() {});
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('PIN Kunci Aplikasi berhasil diperbarui')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('PIN harus 4 digit angka')),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showChapterDateFormatDialog() {
    final currentFormat = LocalStorage.getChapterDateFormat();
    final formatOptions = [
      {
        'label': 'Otomatis / Cerdas (Kotatsu)',
        'value': 'relative_smart',
        'desc': 'Relatif untuk bab baru (< 7 hari), tanggal kalender untuk bab lama',
      },
      {
        'label': 'Selalu Waktu Relatif',
        'value': 'relative',
        'desc': 'Misal: 2 jam lalu, 3 hari lalu, 2 bulan lalu, 1 tahun lalu',
      },
      {
        'label': 'Selalu Tanggal Kalender (Absolut)',
        'value': 'absolute',
        'desc': 'Misal: 15 Oktober 2024, 01 Januari 2023',
      },
      {
        'label': 'Sembunyikan Tanggal',
        'value': 'hidden',
        'desc': 'Hanya tampilkan judul dan nomor bab tanpa tanggal rilis',
      },
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SimpleDialog(
          title: const Text('Format Tanggal Bab', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          children: formatOptions.map((opt) {
            final isSelected = currentFormat == opt['value'];
            return ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              title: Text(
                opt['label']!,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                opt['desc']!,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
              trailing: isSelected ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 20) : null,
              onTap: () async {
                await LocalStorage.setChapterDateFormat(opt['value']!);
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
            );
          }).toList(),
        );
      },
    );
  }

  String _getChapterDateFormatLabel(String format) {
    switch (format) {
      case 'relative':
        return 'Selalu Waktu Relatif';
      case 'absolute':
        return 'Selalu Tanggal Kalender';
      case 'hidden':
        return 'Sembunyikan Tanggal';
      case 'relative_smart':
      default:
        return 'Otomatis / Cerdas (Kotatsu)';
    }
  }

  void _showChapterSortDialog() {
    final currentSort = LocalStorage.getChapterSortAscending();
    final sortOptions = [
      {
        'label': 'Terbaru ke Terlama (Menurun)',
        'value': false,
        'desc': 'Bab terbaru berada di posisi paling atas (default)',
      },
      {
        'label': 'Terlama ke Terbaru (Menaik)',
        'value': true,
        'desc': 'Bab paling awal / chapter 1 berada di posisi paling atas',
      },
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SimpleDialog(
          title: const Text('Urutan Bab Default', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          children: sortOptions.map((opt) {
            final isSelected = currentSort == opt['value'];
            return ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              title: Text(
                opt['label']! as String,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                opt['desc']! as String,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
              trailing: isSelected ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 20) : null,
              onTap: () async {
                await LocalStorage.setChapterSortAscending(opt['value']! as bool);
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = ref.watch(appThemeModeProvider);
    final isFloatingNav = LocalStorage.isFloatingNavEnabled();
    final isShowLabels = LocalStorage.isShowNavLabels();
    final isAppLock = LocalStorage.isAppLockEnabled();
    final chapterDateFormat = LocalStorage.getChapterDateFormat();
    final isSortAscending = LocalStorage.getChapterSortAscending();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tampilan'),
      ),
      body: ListView(
        children: [
          // Kategori Tema
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              'Tema & Warna',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Tema Gelap / Terang'),
            subtitle: Text(
              currentTheme == 'amoled'
                  ? 'AMOLED (Pure Black)'
                  : currentTheme == 'dark'
                      ? 'Mode Gelap'
                      : currentTheme == 'light'
                          ? 'Mode Terang'
                          : 'Mengikuti Sistem',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showThemeDialog,
          ),

          const Divider(height: 24),

          // Kategori Detail Manga
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              'Detail Manga & Daftar Bab',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Format Tanggal Bab'),
            subtitle: Text(_getChapterDateFormatLabel(chapterDateFormat)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showChapterDateFormatDialog,
          ),
          ListTile(
            leading: const Icon(Icons.sort_rounded),
            title: const Text('Urutan Bab Default'),
            subtitle: Text(isSortAscending ? 'Terlama ke Terbaru (Menaik)' : 'Terbaru ke Terlama (Menurun)'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showChapterSortDialog,
          ),

          const Divider(height: 24),

          // Kategori Bagian Layar Utama
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              'Bagian Layar Utama',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.navigation_outlined),
            title: const Text('Bilah Navigasi Mengambang'),
            subtitle: const Text('Tampilkan navbar bergaya kapsul melayang (Floating Navbar)'),
            value: isFloatingNav,
            onChanged: (val) async {
              await LocalStorage.setFloatingNavEnabled(val);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.label_outline_rounded),
            title: const Text('Tampilkan Label di Navbar'),
            subtitle: const Text('Menampilkan teks judul di bawah ikon navbar'),
            value: isShowLabels,
            onChanged: (val) async {
              await LocalStorage.setShowNavLabels(val);
              setState(() {});
            },
          ),

          const Divider(height: 24),

          // Kategori Kunci Aplikasi
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              'Privasi & Kunci Aplikasi',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline_rounded),
            title: const Text('Kunci Aplikasi (PIN Lock)'),
            subtitle: Text(
              isAppLock
                  ? 'Aplikasi diproteksi dengan 4-digit PIN'
                  : 'Buka aplikasi tanpa kode keamanan',
            ),
            value: isAppLock,
            onChanged: (val) async {
              if (val) {
                _showPinDialog();
              } else {
                await LocalStorage.setAppLockPin(null);
                setState(() {});
              }
            },
          ),
          if (isAppLock)
            ListTile(
              leading: const SizedBox(width: 24),
              title: const Text('Ubah PIN Keamanan'),
              subtitle: const Text('Ganti 4-digit PIN yang tersimpan'),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: _showPinDialog,
            ),
        ],
      ),
    );
  }
}
