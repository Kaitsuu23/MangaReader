import 'package:flutter/material.dart';
import '../../features/webview/cloudflare_solver_screen.dart';

/// Convert raw exception/PlatformException messages into short, user-friendly text.
String friendlyError(String raw) {
  // Cloudflare verification
  if (raw.contains('CLOUDFLARE_PROTECTED') || raw.contains('cf-mitigated') || raw.contains('challenge')) {
    return 'Situs ini dilindungi oleh verifikasi Cloudflare.\nBuka verifikasi web untuk melanjutkan.';
  }
  // HTTP 404
  if (raw.contains('404')) {
    return 'Konten tidak ditemukan (404).\nMungkin manga ini tidak tersedia di sumber ini.';
  }
  // HTTP 403
  if (raw.contains('403')) {
    return 'Akses ditolak (403).\nSitus mungkin dilindungi verifikasi Cloudflare atau memblokir akses.';
  }
  // HTTP 5xx
  if (RegExp(r'HTTP 5\d\d').hasMatch(raw)) {
    return 'Server sedang bermasalah. Coba lagi nanti.';
  }
  // Timeout
  if (raw.contains('timeout') || raw.contains('Timeout') || raw.contains('timed out')) {
    return 'Koneksi habis waktu. Periksa jaringan dan coba lagi.';
  }
  // No internet
  if (raw.contains('SocketException') ||
      raw.contains('NetworkException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('No address') ||
      raw.contains('UnknownHostException') ||
      raw.contains('ConnectException') ||
      raw.contains('unreachable') ||
      raw.contains('tidak ada koneksi') ||
      raw.contains('koneksi internet')) {
    return 'Tidak ada koneksi internet.\nPeriksa sambungan Wi-Fi atau data seluler Anda.';
  }
  // SSL
  if (raw.contains('SSL') || raw.contains('certificate') || raw.contains('HandshakeException')) {
    return 'Gagal terhubung (SSL error). Coba lagi.';
  }
  // Parser error — trim to first line
  if (raw.contains('PARSER_ERROR') || raw.contains('PlatformException')) {
    final firstLine = raw
        .replaceAll(RegExp(r'PlatformException\(\w+,\s*'), '')
        .split('\n')
        .first
        .trim();
    // If first line still has HTML, just show generic
    if (firstLine.contains('<') || firstLine.length > 80) {
      return 'Gagal memuat data. Coba lagi.';
    }
    return firstLine;
  }
  // Generic — if raw is too long or has HTML, show generic
  if (raw.contains('<html') || raw.contains('DOCTYPE') || raw.length > 120) {
    return 'Gagal memuat data. Coba lagi.';
  }
  return raw;
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String? cloudflareUrl;
  final String? sourceName;

  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.cloudflareUrl,
    this.sourceName,
  });

  bool get _isCloudflare =>
      message.contains('CLOUDFLARE') ||
      message.contains('403') ||
      message.contains('cf-mitigated') ||
      message.contains('challenge');

  String? _resolveCloudflareUrl() {
    if (cloudflareUrl != null && cloudflareUrl!.isNotEmpty) return cloudflareUrl;
    final match = RegExp(r'https?://[^\s)"' "'" r']+').firstMatch(message);
    return match?.group(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayMessage = friendlyError(message);
    final isCf = _isCloudflare;
    final effectiveCfUrl = _resolveCloudflareUrl();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCf ? Icons.shield_rounded : Icons.error_outline_rounded,
              size: 52,
              color: isCf ? theme.colorScheme.primary : theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              isCf ? 'Verifikasi Cloudflare' : 'Terjadi Kesalahan',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              displayMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            if (isCf && effectiveCfUrl != null && effectiveCfUrl.isNotEmpty) ...[
              FilledButton.icon(
                onPressed: () async {
                  final ok = await CloudflareSolverScreen.open(
                    context,
                    url: effectiveCfUrl,
                    sourceName: sourceName,
                  );
                  if (ok && onRetry != null) {
                    onRetry!();
                  }
                },
                icon: const Icon(Icons.verified_user_rounded),
                label: const Text('Buka Verifikasi Web'),
              ),
              const SizedBox(height: 10),
            ],
            if (onRetry != null) ...[
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba Lagi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
