import 'package:flutter/material.dart';
import '../../core/storage/local_storage.dart';
import 'security_service.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback? onUnlocked;

  const AppLockScreen({super.key, this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  String _errorMessage = '';
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    // Auto-prompt biometric shortly after screen builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerBiometric();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _triggerBiometric() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = '';
    });

    final success = await SecurityService.authenticate();
    if (mounted) {
      setState(() {
        _isAuthenticating = false;
      });
      if (success) {
        widget.onUnlocked?.call();
      } else {
        setState(() {
          _errorMessage = 'Autentikasi gagal atau dibatalkan.';
        });
      }
    }
  }

  void _verifyPin(String entered) {
    final savedPin = LocalStorage.getInAppPin();
    if (savedPin.isEmpty) return;

    if (entered == savedPin) {
      SecurityService.unlock();
      widget.onUnlocked?.call();
    } else {
      setState(() {
        _errorMessage = 'PIN salah. Coba lagi.';
        _pinController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasInAppPin = LocalStorage.getInAppPin().isNotEmpty;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.lock_rounded,
                        size: 46,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Aplikasi Terkunci',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gunakan sidik jari, pengenalan wajah, atau PIN untuk membuka Yomika',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Tombol Biometrik
                  FilledButton.icon(
                    onPressed: _isAuthenticating ? null : _triggerBiometric,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.fingerprint_rounded, size: 24),
                    label: Text(
                      _isAuthenticating ? 'Memverifikasi...' : 'Buka Kunci Biometrik',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),

                  // PIN Input jika pengguna mengaktifkan custom PIN cadangan
                  if (hasInAppPin) ...[
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(child: Divider(color: theme.dividerColor)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'ATAU MASUKKAN PIN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: theme.dividerColor)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        style: const TextStyle(
                          fontSize: 22,
                          letterSpacing: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '••••',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (val) {
                          if (val.length >= 4) {
                            _verifyPin(val);
                          }
                        },
                      ),
                    ),
                  ],

                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
