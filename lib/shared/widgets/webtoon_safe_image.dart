import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A widget that safely renders exceptionally tall webtoon/manga images.
///
/// Mobile GPUs have hardware texture size limits (typically 4096 or 8192 px).
/// When an image taller than this limit (e.g. 24,000+ px from Softkomik or Webtoon)
/// is uploaded as a single texture to the GPU, the driver clamps its height to 4096 px
/// while keeping the original width, causing the image to appear squished/gepeng horizontally.
///
/// [WebtoonSafeImage] detects when an image's height exceeds [maxSliceHeight] (default 3000 px)
/// and seamlessly slices it into smaller vertical chunks using synchronous canvas rendering,
/// then stacks them vertically. This guarantees 100% accurate aspect ratio without any distortion.
class WebtoonSafeImage extends StatefulWidget {
  final ImageProvider imageProvider;
  final BoxFit fit;
  final double? width;
  final FilterQuality filterQuality;

  const WebtoonSafeImage({
    super.key,
    required this.imageProvider,
    this.fit = BoxFit.fitWidth,
    this.width,
    this.filterQuality = FilterQuality.medium,
  });

  @override
  State<WebtoonSafeImage> createState() => _WebtoonSafeImageState();
}

class _WebtoonSafeImageState extends State<WebtoonSafeImage> {
  ImageStream? _imageStream;
  ImageStreamListener? _listener;
  List<ui.Image>? _slices;

  /// Safe height threshold in pixels below standard mobile GPU texture limit (4096 px).
  static const int maxSliceHeight = 3000;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant WebtoonSafeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _disposeSlices();
      _resolveImage();
    }
  }

  void _resolveImage() {
    _stopListening();
    final ImageStream newStream = widget.imageProvider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener(
      _handleImageFrame,
      onError: (exception, stackTrace) {
        debugPrint('[WebtoonSafeImage] Error resolving image: $exception');
      },
    );
    _imageStream = newStream;
    newStream.addListener(_listener!);
  }

  void _stopListening() {
    if (_imageStream != null && _listener != null) {
      _imageStream!.removeListener(_listener!);
      _imageStream = null;
      _listener = null;
    }
  }

  void _disposeSlices() {
    if (_slices != null) {
      for (final slice in _slices!) {
        slice.dispose();
      }
      _slices = null;
    }
  }

  void _handleImageFrame(ImageInfo info, bool synchronousCall) {
    if (!mounted) return;
    final fullImage = info.image;

    // Normal manga pages (<= 3000 px) require no slicing
    if (fullImage.height <= maxSliceHeight) {
      final clone = fullImage.clone();
      setState(() {
        _disposeSlices();
        _slices = [clone];
      });
      return;
    }

    // Oversized webtoon strips that exceed GPU texture limits (causing squashed/gepeng distortion)
    final totalH = fullImage.height;
    final w = fullImage.width;
    final slices = <ui.Image>[];

    for (int y = 0; y < totalH; y += maxSliceHeight) {
      final h = (y + maxSliceHeight > totalH) ? (totalH - y) : maxSliceHeight;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      canvas.drawImageRect(
        fullImage,
        Rect.fromLTWH(0, y.toDouble(), w.toDouble(), h.toDouble()),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = widget.filterQuality,
      );
      final picture = recorder.endRecording();
      slices.add(picture.toImageSync(w, h));
    }

    setState(() {
      _disposeSlices();
      _slices = slices;
    });
  }

  @override
  void dispose() {
    _stopListening();
    _disposeSlices();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slices = _slices;
    if (slices == null || slices.isEmpty) {
      return SizedBox(
        width: widget.width,
        height: 0,
      );
    }

    if (slices.length == 1) {
      return RepaintBoundary(
        child: RawImage(
          image: slices.first,
          fit: widget.fit,
          width: widget.width,
          filterQuality: widget.filterQuality,
        ),
      );
    }

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: slices.map((slice) {
          return RawImage(
            image: slice,
            fit: widget.fit,
            width: widget.width,
            filterQuality: widget.filterQuality,
          );
        }).toList(),
      ),
    );
  }
}
