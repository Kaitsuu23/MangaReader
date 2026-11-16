import 'package:flutter/material.dart';

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tentang'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          // App Logo & Version
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(21),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Yomika',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 4),
                Text(
                  'Versi 1.3.5',
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),

          // Opsi Tentang
          ListTile(
            leading: const Icon(Icons.system_update_rounded),
            title: const Text('Periksa Pembaruan'),
            subtitle: const Text('Aplikasi sudah menggunakan versi terbaru'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                  content: Text('Yomika v1.0.0 adalah versi terbaru'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: const Text('Kode Sumber & Repositori'),
            subtitle: const Text('Kotatsu Redo Flutter Engine'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16), content: Text('Proyek berbasis Kotatsu Redo')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Lisensi Open Source'),
            subtitle: const Text('GNU General Public License v3.0'),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Yomika',
                applicationVersion: '1.0.0',
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Aplikasi pembaca komik/manga gratis, bebas iklan, dan open-source yang terinspirasi oleh Kotatsu Redo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
