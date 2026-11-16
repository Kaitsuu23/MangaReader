import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/translator_settings_provider.dart';
import 'translated_page_overlay.dart';

/// Lightweight wrapper that automatically provides the cached or local page image file
/// to [TranslatedPageOverlay] without altering the underlying image rendering.
class ReaderPageTranslatorWrapper extends ConsumerStatefulWidget {
  final String pageUrl;
  final String pageKey;
  final BoxFit fit;
  final Widget child;

  const ReaderPageTranslatorWrapper({
    super.key,
    required this.pageUrl,
    required this.pageKey,
    this.fit = BoxFit.contain,
    required this.child,
  });

  @override
  ConsumerState<ReaderPageTranslatorWrapper> createState() =>
      _ReaderPageTranslatorWrapperState();
}

class _ReaderPageTranslatorWrapperState
    extends ConsumerState<ReaderPageTranslatorWrapper> {
  File? _resolvedFile;
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    _checkAndResolveFile();
  }

  @override
  void didUpdateWidget(covariant ReaderPageTranslatorWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageUrl != widget.pageUrl) {
      _resolvedFile = null;
      _checkAndResolveFile();
    }
  }

  Future<void> _checkAndResolveFile() async {
    final isEnabled = ref.read(autoTranslateEnabledProvider);
    if (!isEnabled || _isResolving) return;

    final url = widget.pageUrl.trim();
    if (url.isEmpty) return;

    // Check if it's already a local file
    if (url.startsWith('/') || url.startsWith('file://')) {
      final f = File(url.replaceFirst('file://', ''));
      if (f.existsSync()) {
        if (mounted) setState(() => _resolvedFile = f);
        return;
      }
    }

    _isResolving = true;
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(url);
      if (fileInfo != null && fileInfo.file.existsSync()) {
        if (mounted) {
          setState(() {
            _resolvedFile = fileInfo.file;
            _isResolving = false;
          });
        }
        return;
      }

      // If not yet cached, attempt to fetch file in background
      final downloaded = await DefaultCacheManager().getSingleFile(url);
      if (mounted && downloaded.existsSync()) {
        setState(() {
          _resolvedFile = downloaded;
          _isResolving = false;
        });
      }
    } catch (_) {
      // Background resolution error is harmless — page still displays normally
    } finally {
      _isResolving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = ref.watch(autoTranslateEnabledProvider);

    if (!isEnabled) {
      return widget.child;
    }

    // Trigger file resolution if not yet resolved
    if (_resolvedFile == null && !_isResolving) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkAndResolveFile();
      });
    }

    if (_resolvedFile == null) {
      return widget.child;
    }

    return TranslatedPageOverlay(
      imageFile: _resolvedFile,
      pageKey: widget.pageKey,
      fit: widget.fit,
      child: widget.child,
    );
  }
}
