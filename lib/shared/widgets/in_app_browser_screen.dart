import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class InAppBrowserScreen extends StatefulWidget {
  final String url;
  final String title;

  const InAppBrowserScreen({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends State<InAppBrowserScreen> {
  late final WebViewController _controller;
  double _progress = 0.0;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _pageTitle;
  late String _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _pageTitle = widget.title;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _progress = progress / 100.0;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _hasError = false;
                _isLoading = true;
                _currentUrl = url;
              });
            }
          },
          onPageFinished: (String url) async {
            final title = await _controller.getTitle();
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUrl = url;
                if (title != null && title.isNotEmpty) {
                  _pageTitle = title;
                }
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            // Abaikan error dari subresource (iklan, analytics komiku, dll)
            // Hanya tampilkan error jika halaman utama yang gagal dimuat
            if (error.isForMainFrame ?? false) {
              debugPrint('[InAppBrowser] Main frame error: ${error.description} (${error.errorCode})');
              if (mounted) {
                setState(() {
                  _hasError = true;
                  _errorMessage = error.description;
                });
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uri = Uri.tryParse(_currentUrl);
    final host = uri?.host ?? '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Tutup',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _pageTitle ?? widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              if (host.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 10, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      host,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          bottom: _isLoading && _progress < 1.0
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress),
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Muat Ulang',
              onPressed: () => _controller.reload(),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded),
              tooltip: 'Buka di Peramban Eksternal',
              onPressed: () async {
                final uri = Uri.tryParse(_currentUrl);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
        body: _hasError
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 56,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Gagal Memuat Halaman',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage ?? 'Tidak dapat terhubung ke situs web.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Coba Lagi'),
                        onPressed: () {
                          setState(() {
                            _hasError = false;
                            _isLoading = true;
                          });
                          _controller.reload();
                        },
                      ),
                    ],
                  ),
                ),
              )
            : WebViewWidget(controller: _controller),
      ),
    );
  }
}
