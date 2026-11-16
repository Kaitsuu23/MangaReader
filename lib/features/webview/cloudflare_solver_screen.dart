import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Screen to resolve Cloudflare Interstitial / Turnstile challenge,
/// modeled after Kotatsu Redo's CloudFlareActivity and CloudFlareDetection.
class CloudflareSolverScreen extends StatefulWidget {
  final String url;
  final String? sourceName;

  const CloudflareSolverScreen({
    super.key,
    required this.url,
    this.sourceName,
  });

  /// Opens the solver screen and returns true if verification succeeded.
  static Future<bool> open(
    BuildContext context, {
    required String url,
    String? sourceName,
  }) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CloudflareSolverScreen(
          url: url,
          sourceName: sourceName,
        ),
      ),
    );
    return result == true;
  }

  @override
  State<CloudflareSolverScreen> createState() => _CloudflareSolverScreenState();
}

class _CloudflareSolverScreenState extends State<CloudflareSolverScreen> {
  late final WebViewController _controller;
  Timer? _probeTimer;
  int _consecutiveOkPasses = 0;
  static const int _requiredStablePasses = 3;
  bool _isLoading = true;
  double _progress = 0.0;
  bool _isSuccess = false;
  String _statusText = 'Selesaikan verifikasi "Saya manusia" jika diminta. Halaman akan otomatis tertutup setelah selesai.';

  /// Comprehensive passive DOM probe JavaScript.
  /// Detects Cloudflare Managed Challenge / Turnstile across English, Indonesian,
  /// and localized variants without false-positive early exits.
  static const String _cfStateJs = '''
    (function(){
      try {
        var href = (document.location && document.location.href) || '';
        if (href === '' || href === 'about:blank') return 'wait';
        if (document.readyState !== 'interactive' && document.readyState !== 'complete') return 'wait';

        var body = document.body;
        if (!body) return 'wait';

        var title = (document.title || '').toLowerCase();
        var text = (body.innerText || body.textContent || '').toLowerCase();

        // 1. Hard-blocked error checks
        if (title.indexOf('attention required') !== -1 ||
            title.indexOf('access denied') !== -1 ||
            text.indexOf('error 1020') !== -1 ||
            text.indexOf('error 1015') !== -1 ||
            text.indexOf('you have been blocked') !== -1) {
          return 'error';
        }

        // 2. Cloudflare challenge titles (multi-language)
        if (title.indexOf('just a moment') !== -1 ||
            title.indexOf('un instant') !== -1 ||
            title.indexOf('einen moment') !== -1 ||
            title.indexOf('un momento') !== -1 ||
            title.indexOf('один момент') !== -1 ||
            title.indexOf('ddos protection') !== -1 ||
            title.indexOf('security check') !== -1) {
          return 'wait';
        }

        // 3. Known challenge DOM elements (modern Turnstile & legacy Cloudflare)
        var challengeSelectors = [
          '#challenge-running',
          '#challenge-stage',
          '#challenge-container',
          '#cf-challenge-running',
          '.cf-browser-verification',
          '#turnstile-wrapper',
          '#cf-turnstile',
          '.cf-turnstile-wrapper',
          '#cf-please-wait',
          'form#challenge-form',
          'form[action*="__cf_chl"]',
          'form[action*="challenge-platform"]',
          'iframe[src*="challenges.cloudflare.com"]',
          'iframe[src*="challenge-platform"]',
          'iframe[src*="cloudflare.com"]',
          'input[name="cf-turnstile-response"]',
          'input[name="cf_challenge_response"]',
          '#challenge-error-text',
          '#challenge-body-text',
          '[data-translate="challenge_headline"]',
          '.zone-name-title'
        ];
        for (var i = 0; i < challengeSelectors.length; i++) {
          var el = document.querySelector(challengeSelectors[i]);
          if (el) {
            var style = window.getComputedStyle(el);
            if (style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0') {
              // Try auto-clicking turnstile checkbox if accessible
              try {
                var chk = el.querySelector('input[type="checkbox"], [role="checkbox"]');
                if (chk && !chk.checked && !chk.hasAttribute('data-auto-clicked')) {
                  chk.setAttribute('data-auto-clicked', 'true');
                  chk.click();
                }
              } catch (_) {}
              return 'wait';
            }
          }
        }

        // 4. In-page text markers (handles Indonesian, Malay, English, etc.)
        var challengePhrases = [
          'melakukan verifikasi keamanan',
          'memverifikasi bahwa anda bukan bot',
          'verifikasi bahwa anda adalah manusia',
          'verifikasi keamanan',
          'saya manusia',
          'verifying you are human',
          'verify you are human',
          'checking if the site connection is secure',
          'enable javascript and cookies to continue',
          'please turn javascript on and reload the page',
          'performa dan keamanan oleh cloudflare',
          'performance & security by cloudflare'
        ];
        for (var j = 0; j < challengePhrases.length; j++) {
          if (text.indexOf(challengePhrases[j]) !== -1) {
            return 'wait';
          }
        }

        // Ray ID combined with Cloudflare mention
        if (text.indexOf('ray id:') !== -1 && text.indexOf('cloudflare') !== -1) {
          return 'wait';
        }

        // 5. Must have real page body content
        if (body.children.length === 0 && text.trim().length === 0) return 'wait';

        return 'ok';
      } catch (e) { return 'wait'; }
    })()
  ''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);

    _initController();
  }

  Future<void> _initController() async {
    try {
      // 1. Enable third-party cookies on Android (required for challenges.cloudflare.com iframe to complete)
      final cookieManager = WebViewCookieManager();
      if (cookieManager.platform is AndroidWebViewCookieManager &&
          _controller.platform is AndroidWebViewController) {
        await (cookieManager.platform as AndroidWebViewCookieManager).setAcceptThirdPartyCookies(
          _controller.platform as AndroidWebViewController,
          true,
        );
      }

      if (_controller.platform is AndroidWebViewController) {
        final android = _controller.platform as AndroidWebViewController;
        android.setMediaPlaybackRequiresUserGesture(false);
      }

      // 2. Align User-Agent with authentic Chrome Mobile:
      // Cloudflare blocks or loops Turnstile indefinitely on Android WebViews containing '; wv' or 'Version/4.0'
      final defaultUa = await _controller.getUserAgent();
      if (defaultUa != null && defaultUa.isNotEmpty) {
        final cleanUa = defaultUa
            .replaceAll(RegExp(r';\s*wv', caseSensitive: false), '')
            .replaceAll(RegExp(r'Version/\d+\.\d+\s*', caseSensitive: false), '');
        await _controller.setUserAgent(cleanUa);
      }
    } catch (_) {}

    // 3. Set navigation delegate and load URL
    _controller
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p / 100.0);
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _consecutiveOkPasses = 0;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
            _checkState();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

    // Poll every 1000ms to detect challenge completion without premature exit
    _probeTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      _checkState();
    });
  }

  Future<void> _checkState() async {
    if (_isSuccess || !mounted || _isLoading) return;
    try {
      final rawResult = await _controller.runJavaScriptReturningResult(_cfStateJs);
      final state = rawResult.toString().replaceAll('"', '').trim().toLowerCase();

      if (state == 'ok') {
        _consecutiveOkPasses++;
        if (mounted) {
          setState(() {
            _statusText = 'Verifikasi terlewati! Mengalihkan dalam ${_requiredStablePasses - _consecutiveOkPasses + 1} detik...';
          });
        }
        if (_consecutiveOkPasses >= _requiredStablePasses && !_isSuccess) {
          _isSuccess = true;
          _probeTimer?.cancel();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Verifikasi Cloudflare berhasil!'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(left: 16, right: 16, bottom: 16),
              ),
            );
            Navigator.of(context).pop(true);
          }
        }
      } else if (state == 'error') {
        _consecutiveOkPasses = 0;
        if (mounted) {
          setState(() {
            _statusText = 'Akses ditolak oleh Cloudflare (Access Denied / Blocked).';
          });
        }
      } else {
        // state == 'wait'
        _consecutiveOkPasses = 0;
        if (mounted && _statusText != 'Selesaikan verifikasi "Saya manusia" jika diminta. Halaman akan otomatis tertutup setelah selesai.') {
          setState(() {
            _statusText = 'Selesaikan verifikasi "Saya manusia" jika diminta. Halaman akan otomatis tertutup setelah selesai.';
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.sourceName != null ? 'Verifikasi ${widget.sourceName}' : 'Verifikasi Cloudflare';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              widget.url,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Buka di Browser',
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: () async {
              final uri = Uri.parse(widget.url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _consecutiveOkPasses = 0;
              _controller.reload();
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Selesai'),
            onPressed: () {
              Navigator.of(context).pop(true);
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
              child: Row(
                children: [
                  if (_consecutiveOkPasses > 0)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.info_outline_rounded, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusText,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
