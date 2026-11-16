import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Detected bubble color theme for text removal and redraw.
class InpaintedBubbleStyle {
  final Color bgColor;
  final Color textColor;

  const InpaintedBubbleStyle({
    required this.bgColor,
    required this.textColor,
  });
}

/// Service that analyzes speech bubble backgrounds to provide seamless text removal and coloring.
/// Samples pixel colors at the perimeter of detected bounding boxes to determine the exact background
/// and optimal text contrast (light vs dark).
class MangaInpaintingService {
  /// Analyze the image at the given bounding box and compute the bubble's background & text colors.
  static Future<InpaintedBubbleStyle> analyzeBubbleColor(
    File imageFile,
    Rect boundingBox,
  ) async {
    final styles = await batchAnalyzeBubbleColors(imageFile, [boundingBox]);
    return styles.isNotEmpty
        ? styles.first
        : const InpaintedBubbleStyle(bgColor: Colors.white, textColor: Colors.black);
  }

  /// Batch analyze colors for all blocks in a page.
  static Future<List<InpaintedBubbleStyle>> batchAnalyzeBubbleColors(
    File imageFile,
    List<Rect> boxes,
  ) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return List.filled(
          boxes.length,
          const InpaintedBubbleStyle(bgColor: Colors.white, textColor: Colors.black),
        );
      }

      final imgWidth = decoded.width;
      final imgHeight = decoded.height;

      final results = <InpaintedBubbleStyle>[];

      for (final box in boxes) {
        // Expand slightly outward so we sample clean background area, not text strokes
        final left = (box.left - 4).toInt().clamp(0, imgWidth - 1);
        final top = (box.top - 4).toInt().clamp(0, imgHeight - 1);
        final right = (box.right + 4).toInt().clamp(0, imgWidth - 1);
        final bottom = (box.bottom + 4).toInt().clamp(0, imgHeight - 1);

        if (right <= left || bottom <= top) {
          results.add(const InpaintedBubbleStyle(bgColor: Colors.white, textColor: Colors.black));
          continue;
        }

        int totalR = 0;
        int totalG = 0;
        int totalB = 0;
        int bgCount = 0;
        int whiteCount = 0;
        int totalCount = 0;

        void samplePixel(int x, int y) {
          final p = decoded.getPixel(x, y);
          final r = p.r.toInt();
          final g = p.g.toInt();
          final b = p.b.toInt();
          final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
          totalCount++;

          if (lum > 0.82) {
            whiteCount++;
          }
          // Filter out dark text strokes (lum < 0.40)
          if (lum >= 0.40) {
            totalR += r;
            totalG += g;
            totalB += b;
            bgCount++;
          }
        }

        for (int x = left; x <= right; x += 3) {
          samplePixel(x, top);
          samplePixel(x, bottom);
        }
        for (int y = top; y <= bottom; y += 3) {
          samplePixel(left, y);
          samplePixel(right, y);
        }

        // Standard manga speech bubble: if majority of border pixels are light/white, use solid pure white
        if (totalCount > 0 && (whiteCount / totalCount) > 0.50) {
          results.add(const InpaintedBubbleStyle(bgColor: Colors.white, textColor: Colors.black));
          continue;
        }

        if (bgCount == 0) {
          // Dark/black speech bubble or night scene
          results.add(const InpaintedBubbleStyle(bgColor: Colors.black, textColor: Colors.white));
          continue;
        }

        final avgR = (totalR / bgCount).round().clamp(0, 255);
        final avgG = (totalG / bgCount).round().clamp(0, 255);
        final avgB = (totalB / bgCount).round().clamp(0, 255);

        final lum = (0.2126 * avgR + 0.7152 * avgG + 0.0722 * avgB) / 255.0;
        final bgColor = Color.fromARGB(255, avgR, avgG, avgB);
        final textColor = lum > 0.5 ? Colors.black : Colors.white;

        results.add(InpaintedBubbleStyle(bgColor: bgColor, textColor: textColor));
      }

      return results;
    } catch (_) {
      return List.filled(
        boxes.length,
        const InpaintedBubbleStyle(bgColor: Colors.white, textColor: Colors.black),
      );
    }
  }
}
