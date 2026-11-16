import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/parser_channel.dart';
import '../models/page_slices.dart';

/// Caches native slice requests so rebuilding a reader item neither
/// re-downloads nor re-decodes a page.
class PageSliceCache {
  PageSliceCache._();

  static final PageSliceCache instance = PageSliceCache._();

  final ParserChannel _channel = ParserChannel();
  final Map<String, Future<PageSlices?>> _futures = {};

  /// Returns the slices for [url], or `null` when native slicing is unavailable
  /// (non-Android platform, unsupported format, network error, ...).
  Future<PageSlices?> load(String url, {String? referer}) {
    if (url.isEmpty) return Future<PageSlices?>.value(null);
    return _futures.putIfAbsent(url, () => _fetch(url, referer));
  }

  Future<PageSlices?> _fetch(String url, String? referer) async {
    PageSlices? result;
    try {
      result = await _channel.getPageSlices(url, referer: referer);
    } on MissingPluginException {
      result = null;
    } catch (_) {
      result = null;
    }

    if (result == null || result.slices.isEmpty) {
      // Allow a later rebuild to retry.
      _futures.remove(url);
      return null;
    }
    return result;
  }

  void invalidate(String url) => _futures.remove(url);

  /// Drops every in-memory entry and wipes the native on-disk slice cache.
  Future<void> clear() async {
    _futures.clear();
    await _channel.clearPageSliceCache();
  }
}

/// Renders a manga page from native slices instead of decoding the whole image
/// at once.
///
/// Flutter's Impeller renderer squashes any image taller than the GPU's max
/// texture size (it clamps the height but keeps the width). Extremely tall
/// webtoon strips are therefore cut into small vertical slices on the native
/// side and stacked here, so every texture stays small and the aspect ratio is
/// preserved.
///
/// When slicing is unavailable the [fallbackBuilder] path is used.
class SlicedPageImage extends StatefulWidget {
  final String url;
  final String? referer;
  final VoidCallback? onLoaded;
  final Widget Function() placeholderBuilder;
  final Widget Function() fallbackBuilder;

  const SlicedPageImage({
    super.key,
    required this.url,
    required this.placeholderBuilder,
    required this.fallbackBuilder,
    this.referer,
    this.onLoaded,
  });

  @override
  State<SlicedPageImage> createState() => _SlicedPageImageState();
}

class _SlicedPageImageState extends State<SlicedPageImage> {
  Future<PageSlices?>? _future;
  int _retries = 0;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant SlicedPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _retries = 0;
      _reported = false;
      _reload();
    }
  }

  void _reload() {
    _future = PageSliceCache.instance.load(widget.url, referer: widget.referer);
  }

  void _reportLoaded() {
    if (_reported) return;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLoaded?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PageSlices?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.placeholderBuilder();
        }

        final data = snapshot.data;
        if (data == null || data.slices.isEmpty) {
          _reportLoaded();
          return widget.fallbackBuilder();
        }

        // The native cache may have been evicted between the call and now.
        final missing = data.slices.any((s) => !File(s.path).existsSync());
        if (missing) {
          if (_retries < 1) {
            _retries++;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              PageSliceCache.instance.invalidate(widget.url);
              setState(_reload);
            });
            return widget.placeholderBuilder();
          }
          _reportLoaded();
          return widget.fallbackBuilder();
        }

        _reportLoaded();
        return _buildSlices(data);
      },
    );
  }

  Widget _buildSlices(PageSlices data) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The webtoon reader gives an unbounded height (full width, scrolls),
          // while the paged reader is bounded and needs the whole page to fit.
          var width = constraints.maxWidth;
          if (width.isFinite &&
              data.width > 0 &&
              data.height > 0 &&
              constraints.maxHeight.isFinite) {
            final fitted = constraints.maxHeight * data.width / data.height;
            if (fitted < width) width = fitted;
          }
          return SizedBox(
            width: width.isFinite ? width : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final slice in data.slices)
                  AspectRatio(
                    // Known up-front, so the page height never jumps while
                    // decoding.
                    aspectRatio: slice.width / slice.height,
                    child: Image.file(
                      File(slice.path),
                      fit: BoxFit.fill,
                      width: double.infinity,
                      height: double.infinity,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
