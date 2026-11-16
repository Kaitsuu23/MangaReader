import 'package:flutter/material.dart';
import '../../core/storage/local_storage.dart';
import 'security_service.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkDeviceSupport();
  }

  Future<void> _checkDeviceSupport() async {
    final canAuth = await SecurityService.canAuthenticate();
    if (mounted) {
      setState(() {
        _canCheckBiometrics = canAuth;
      });
    }
  }

  Future<void> _toggleAppLock(bool enable) async {
    if (enable) {
      // Require verification before turning on
      final success = await SecurityService.authenticate(
        reason: 'Konfirmasi biometrik untuk mengaktifkan kunci aplikasi',
      );
      if (!success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
            content: Text('Verifikasi gagal. Kunci aplikasi tidak diaktifkan.'),
          ),
        );
        return;
      }
    }

    await LocalStorage.setAppLockEnabled(enable);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        content: Text(enable
            ? 'Kunci aplikasi diaktifkan'
            : 'Kunci aplikasi dinonaktifkan'),
      ),
    );
  }

  void _showTimeoutDialog() {
    final current = LocalStorage.getAppLockTimeout();
    final options = [
      {'label': 'Seketika (Saat berpindah aplikasi)', 'value': 0},
      {'label': 'Setelah 1 menit di latar belakang', 'value': 1},
      {'label': 'Setelah 5 menit di latar belakang', 'value': 5},
      {'label': 'Setelah 15 menit di latar belakang', 'value': 15},
      {'label': 'Setelah 30 menit di latar belakang', 'value': 30},
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Waktu Kunci Otomatis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        children: options.map((opt) {
          final isSelected = current == opt['value'];
          return ListTile(
            dense: true,
            title: Text(opt['label'] as String, style: TextStyle(fontSize: 13.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
            trailing: isSelected ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20) : null,
            onTap: () async {
              await LocalStorage.setAppLockTimeout(opt['value'] as int);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() {});
            },
          );
        }).toList(),
      ),
    );
  }

  void _showSetPinDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Atur PIN Cadangan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Masukkan 4-6 angka PIN sebagai alternatif jika biometrik tidak dapat membaca sidik jari:',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(fontSize: 20, letterSpacing: 8, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'PIN Baru',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          if (LocalStorage.getInAppPin().isNotEmpty)
            TextButton(
              onPressed: () async {
                await LocalStorage.setInAppPin('');
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                setState(() {});
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
                    content: Text('PIN cadangan dihapus'),
                  ),
                );
              },
              child: const Text('Hapus PIN', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final pin = controller.text.trim();
              if (pin.length >= 4) {
                await LocalStorage.setInAppPin(pin);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                setState(() {});
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
                    content: Text('PIN cadangan berhasil disimpan'),
                  ),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLock = LocalStorage.isAppLockEnabled();
    final isBiometric = LocalStorage.isBiometricEnabled();
    final timeout = LocalStorage.getAppLockTimeout();
    final hasPin = LocalStorage.getInAppPin().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keamanan & Privasi', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline_rounded),
            title: const Text('Kunci Aplikasi (App Lock)'),
            subtitle: const Text('Minta verifikasi sidik jari atau PIN saat membuka aplikasi'),
            value: isLock,
            onChanged: _toggleAppLock,
          ),
          if (isLock) ...[
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('Autentikasi Biometrik'),
              subtitle: Text(
                _canCheckBiometrics
                    ? 'Gunakan sidik jari atau pemindai wajah perangkat'
                    : 'Sensor biometrik tidak terdeteksi pada perangkat ini',
              ),
              value: isBiometric,
              onChanged: _canCheckBiometrics
                  ? (val) async {
                      await LocalStorage.setBiometricEnabled(val);
                      setState(() {});
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Waktu Kunci Otomatis'),
              subtitle: Text(
                timeout == 0
                    ? 'Seketika saat berpindah aplikasi'
                    : 'Setelah $timeout menit di latar belakang',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _showTimeoutDialog,
            ),
            ListTile(
              leading: const Icon(Icons.pin_rounded),
              title: const Text('PIN Cadangan Dalam Aplikasi'),
              subtitle: Text(
                hasPin
                    ? 'PIN cadangan telah diatur (Ketuk untuk ubah/hapus)'
                    : 'Atur PIN darurat jika sidik jari gagal',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _showSetPinDialog,
            ),
          ],
        ],
      ),
    );
  }
}
