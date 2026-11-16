import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/translated_block.dart';
import '../providers/page_translation_provider.dart';
import '../providers/translator_settings_provider.dart';

/// Overlay widget that detects, inpaints, and renders translated speech bubbles
/// over standard or webtoon manga pages.
///
/// Uses [IgnorePointer] so all touch events (tap navigation, long press for reader controls)
/// pass directly to the underlying MangaReader without being intercepted or disappearing.
class TranslatedPageOverlay extends ConsumerWidget {
  final Widget child;
  final File? imageFile;
  final String pageKey;
  final BoxFit fit;
  final VoidCallback? onToggleMode;

  const TranslatedPageOverlay({
    super.key,
    required this.child,
    required this.imageFile,
    required this.pageKey,
    this.fit = BoxFit.contain,
    this.onToggleMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAutoTranslateEnabled = ref.watch(autoTranslateEnabledProvider);
    final translationMode = ref.watch(translationModeProvider);
    final inpaintEnabled = ref.watch(bubbleInpaintEnabledProvider);
    final sourceLang = ref.watch(sourceLanguageProvider);
    final targetLang = ref.watch(targetLanguageProvider);

    // If auto translate is off or user selected Original Mode, render untranslated manga directly
    if (!isAutoTranslateEnabled ||
        translationMode == 'original' ||
        imageFile == null ||
        !imageFile!.existsSync()) {
      return child;
    }

    final request = TranslationPageRequest(
      imageFile: imageFile!,
      pageKey: pageKey,
      sourceLanguage: sourceLang,
      targetLanguage: targetLang,
    );

    final translationAsync = ref.watch(pageTranslationProvider(request));

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.passthrough,
          children: [
            child,

            // Render translated speech bubbles
            translationAsync.when(
              data: (result) {
                if (result.isEmpty) return const SizedBox.shrink();

                return Positioned.fill(
                  child: IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, overlayConstraints) {
                        final displayWidth = overlayConstraints.maxWidth;
                        final displayHeight = overlayConstraints.maxHeight;

                        if (displayWidth <= 0 || displayHeight <= 0) {
                          return const SizedBox.shrink();
                        }

                        // Compute exact painted image rectangle matching Flutter's Image / BoxFit behavior
                        final fittedSizes = applyBoxFit(
                          fit,
                          result.originalImageSize,
                          Size(displayWidth, displayHeight),
                        );

                        final destRect = Alignment.center.inscribe(
                          fittedSizes.destination,
                          Rect.fromLTWH(0, 0, displayWidth, displayHeight),
                        );

                        final scaleX = destRect.width / result.originalImageSize.width;
                        final scaleY = destRect.height / result.originalImageSize.height;
                        final offsetX = destRect.left;
                        final offsetY = destRect.top;

                        return CustomPaint(
                          size: Size(displayWidth, displayHeight),
                          painter: _TranslatedBubblesPainter(
                            blocks: result.blocks,
                            scaleX: scaleX,
                            scaleY: scaleY,
                            offsetX: offsetX,
                            offsetY: offsetY,
                            inpaintEnabled: inpaintEnabled,
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
              loading: () => Positioned(
                bottom: 12,
                right: 12,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Menerjemahkan...',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              error: (err, _) => const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

/// CustomPainter rendering inpainting background and auto-sized translated text inside bubbles.
class _TranslatedBubblesPainter extends CustomPainter {
  final List<TranslatedBlock> blocks;
  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;
  final bool inpaintEnabled;

  _TranslatedBubblesPainter({
    required this.blocks,
    required this.scaleX,
    required this.scaleY,
    required this.offsetX,
    required this.offsetY,
    required this.inpaintEnabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final block in blocks) {
      if (block.translatedText.trim().isEmpty) continue;

      // Scale coordinates from original image resolution to screen display position
      final origBox = block.boundingBox;
      // Generous padding to cleanly cover edges of speech text underneath and give room for text
      final padX = 5.0 * scaleX;
      final padY = 4.0 * scaleY;

      final rect = Rect.fromLTRB(
        offsetX + origBox.left * scaleX - padX,
        offsetY + origBox.top * scaleY - padY,
        offsetX + origBox.right * scaleX + padX,
        offsetY + origBox.bottom * scaleY + padY,
      );

      // 1. Inpainting: Fill original text area with sampled bubble background color
      if (inpaintEnabled) {
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
        final paint = Paint()
          ..color = block.bgColor
          ..style = PaintingStyle.fill;
        canvas.drawRRect(rrect, paint);
      }

      // 2. Render translated text with auto-fitting font size (rendering full sentence without truncation)
      _drawFittedText(
        canvas: canvas,
        rect: rect,
        text: block.translatedText,
        textColor: block.textColor,
      );
    }
  }

  void _drawFittedText({
    required Canvas canvas,
    required Rect rect,
    required String text,
    required Color textColor,
  }) {
    if (rect.width <= 4 || rect.height <= 4 || text.trim().isEmpty) return;

    // Utilize full rect with slight 1.5px inset
    final innerRect = rect.deflate(1.5);
    final availableWidth = innerRect.width > 4 ? innerRect.width : rect.width;
    final availableHeight = innerRect.height > 4 ? innerRect.height : rect.height;

    TextPainter? bestPainter;

    // Test font sizes from 15.0 down to 6.0 in steps of 0.5
    for (double fs = 15.0; fs >= 6.0; fs -= 0.5) {
      final style = TextStyle(
        color: textColor,
        fontSize: fs,
        fontWeight: FontWeight.w700,
        height: 1.10,
        letterSpacing: -0.3,
      );

      final span = TextSpan(text: text, style: style);
      final tp = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );

      tp.layout(maxWidth: availableWidth);

      // Check if all lines fit within the available bubble height and width
      if (tp.size.height <= availableHeight && tp.size.width <= availableWidth) {
        bestPainter = tp;
        break;
      }
    }

    // If still doesn't fit at 6.0, try down to 4.5
    if (bestPainter == null) {
      for (double fs = 5.5; fs >= 4.5; fs -= 0.5) {
        final style = TextStyle(
          color: textColor,
          fontSize: fs,
          fontWeight: FontWeight.w700,
          height: 1.06,
          letterSpacing: -0.3,
        );

        final span = TextSpan(text: text, style: style);
        final tp = TextPainter(
          text: span,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );

        tp.layout(maxWidth: availableWidth);

        // Allow slight vertical tolerance (15%) because speech bubbles have rounded tops/bottoms
        if (tp.size.height <= availableHeight * 1.15 && tp.size.width <= availableWidth * 1.08) {
          bestPainter = tp;
          break;
        }
      }
    }

    // Fallback: Render all text without artificial maxLines or ellipsis cut-off
    bestPainter ??= TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 4.5,
          fontWeight: FontWeight.w700,
          height: 1.05,
          letterSpacing: -0.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: availableWidth);

    // Center text inside bubble rect
    final dx = rect.left + (rect.width - bestPainter.width) / 2;
    final dy = rect.top + (rect.height - bestPainter.height) / 2;
    bestPainter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _TranslatedBubblesPainter oldDelegate) {
    return oldDelegate.blocks != blocks ||
        oldDelegate.scaleX != scaleX ||
        oldDelegate.scaleY != scaleY ||
        oldDelegate.offsetX != offsetX ||
        oldDelegate.offsetY != offsetY ||
        oldDelegate.inpaintEnabled != inpaintEnabled;
  }
}
