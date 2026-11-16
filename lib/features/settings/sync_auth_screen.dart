import 'package:flutter/material.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/models/content_mode.dart';

class SyncAuthScreen extends StatefulWidget {
  final String? modeId;
  const SyncAuthScreen({super.key, this.modeId});

  @override
  State<SyncAuthScreen> createState() => _SyncAuthScreenState();
}

class _SyncAuthScreenState extends State<SyncAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isObscure = true;
  bool _isLoading = false;
  String? _errorMessage;

  String get _currentModeId => widget.modeId ?? LocalStorage.getActiveContentModeId();

  ContentMode get _currentMode {
    final modes = LocalStorage.getContentModes();
    return modes.firstWhere(
      (m) => m.id == _currentModeId,
      orElse: () => ContentMode.normal,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showChangeServerDialog() {
    final currentUrl = LocalStorage.getSyncServerUrl(modeId: _currentModeId);
    final customCtrl = TextEditingController(text: currentUrl);
    bool isTesting = false;
    String? testMsg;
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
          final theme = Theme.of(ctx);
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
                  Text(
                    'Pilih server resmi atau gunakan VPS / domain mandiri:',
                    style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  ...presets.map((p) {
                    final isSel = customCtrl.text.trim() == p['url'];
                    return ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      title: Text(
                        p['name']!,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(p['url']!, style: const TextStyle(fontSize: 11)),
                      trailing: isSel ? const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18) : null,
                      onTap: () {
                        setDialogState(() {
                          customCtrl.text = p['url']!;
                          testMsg = null;
                          isOnline = null;
                        });
                      },
                    );
                  }),
                  const Divider(height: 14),
                  const Text(
                    'Server Mandiri / VPS:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: customCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'https://sync.dhiksn.my.id',
                      hintStyle: TextStyle(fontSize: 12.5),
                      prefixIcon: Icon(Icons.dns_outlined, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    onChanged: (_) {
                      if (testMsg != null) {
                        setDialogState(() {
                          testMsg = null;
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
                                  testMsg = null;
                                });
                                final res = await SyncService.testConnection(target);
                                setDialogState(() {
                                  isTesting = false;
                                  isOnline = res.isOnline;
                                  testMsg = res.message;
                                });
                              },
                        icon: isTesting
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.network_ping_rounded, size: 15),
                        label: const Text('Tes Koneksi', style: TextStyle(fontSize: 11.5)),
                      ),
                      const SizedBox(width: 8),
                      if (testMsg != null)
                        Expanded(
                          child: Text(
                            testMsg!,
                            style: TextStyle(
                              fontSize: 11,
                              color: isOnline == true ? Colors.green[700] : Colors.redAccent,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
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
                    await LocalStorage.setSyncServerUrl(target, modeId: _currentModeId);
                    if (!mounted) return;
                    setState(() {});
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    bool isSending = false;
    String? statusMsg;
    bool isSuccess = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Lupa Kata Sandi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Masukkan email akun sinkronisasi Anda untuk mengirimkan permintaan pemulihan kata sandi ke server.',
                  style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
                if (statusMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    statusMsg!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isSuccess ? Colors.green[700] : Colors.redAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: isSending
                    ? null
                    : () async {
                        final email = emailCtrl.text.trim();
                        if (email.isEmpty) return;
                        setDialogState(() {
                          isSending = true;
                          statusMsg = null;
                        });

                        try {
                          await SyncService.forgotPassword(email: email, modeId: _currentModeId);
                          setDialogState(() {
                            isSending = false;
                            isSuccess = true;
                            statusMsg = 'Instruksi pemulihan telah dikirim (periksa email Anda).';
                          });
                        } catch (e) {
                          setDialogState(() {
                            isSending = false;
                            isSuccess = false;
                            statusMsg = e.toString().replaceAll('Exception: ', '');
                          });
                        }
                      },
                child: isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Kirim'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final allModes = LocalStorage.getContentModes();
    for (final other in allModes) {
      if (other.id != _currentModeId) {
        final otherEmail = LocalStorage.getSyncEmail(modeId: other.id);
        if (otherEmail != null && otherEmail.toLowerCase() == email.toLowerCase()) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Akun "$email" sedang digunakan di mode "${other.name}". Server Kotatsu tidak mendukung pemisahan mode konten dalam satu akun yang sama. Gunakan akun Kotatsu yang berbeda untuk mode ${_currentMode.name} agar komik tidak bercampur.';
          });
          return;
        }
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await SyncService.login(
        email: email,
        password: password,
        modeId: _currentModeId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          content: Text('Berhasil masuk sebagai $email di mode ${_currentMode.name}!'),
          backgroundColor: Colors.green[700],
        ),
      );

      // Jalankan sinkronisasi pertama kali di background untuk mode ini
      SyncService.syncNow(modeId: _currentModeId);

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentServer = LocalStorage.getSyncServerUrl(modeId: _currentModeId);

    return Scaffold(
      appBar: AppBar(
        title: Text('Masuk Akun (${_currentMode.name})'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                children: [
                  const SizedBox(height: 8),

                  // Header Icon & Title
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.cloud_sync_rounded,
                        size: 42,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Sinkronisasi Data Anda',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'Mode: ${_currentMode.name}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Masuk ke akun yang sudah ada atau buat akun baru untuk menyinkronkan komik favorit, riwayat baca, dan progress antar seluruh perangkat Anda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Server Indicator Card
                  InkWell(
                    onTap: _showChangeServerDialog,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.dns_rounded,
                            size: 22,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Server Sinkronisasi',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currentServer,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _showChangeServerDialog,
                            child: const Text('Ganti', style: TextStyle(fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Error Banner
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 20,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: 'nama@domain.com',
                      prefixIcon: const Icon(Icons.email_outlined),
                      suffixIcon: _emailController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _emailController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                    ),
                    validator: (val) {
                      final str = val?.trim() ?? '';
                      if (str.isEmpty) return 'Email tidak boleh kosong';
                      if (!str.contains('@') || !str.contains('.')) {
                        return 'Format email tidak valid';
                      }
                      return null;
                    },
                    onChanged: (_) {
                      if (_errorMessage != null) {
                        setState(() => _errorMessage = null);
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _isObscure,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Kata Sandi',
                      helperText: 'Panjang 2 - 24 karakter (persyaratan Kotatsu Server)',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_isObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _isObscure = !_isObscure),
                      ),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                    ),
                    validator: (val) {
                      final str = val ?? '';
                      if (str.isEmpty) return 'Kata sandi tidak boleh kosong';
                      if (str.length < 2 || str.length > 24) {
                        return 'Kata sandi harus terdiri dari 2 - 24 karakter';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _handleAuth(),
                    onChanged: (_) {
                      if (_errorMessage != null) {
                        setState(() => _errorMessage = null);
                      }
                    },
                  ),

                  const SizedBox(height: 8),

                  // Forgot Password Button
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordDialog,
                      child: const Text('Lupa Kata Sandi?', style: TextStyle(fontSize: 13)),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Submit Button
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _handleAuth,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Masuk / Buat Akun',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Info Card (Kotatsu Account Behavior)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Jika email Anda belum pernah terdaftar di server, server akan otomatis mendaftarkannya saat proses masuk pertama kali.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
