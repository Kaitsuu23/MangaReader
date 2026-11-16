import 'dart:math';
import 'package:flutter/material.dart';

/// Reusable heart badge indicating a manga is in favorites.
/// Positioned at the top-left corner per UI requirements.
class FavoriteBadge extends StatelessWidget {
  final double size;
  final double iconSize;

  const FavoriteBadge({
    super.key,
    this.size = 28,
    this.iconSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.95),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.favorite,
          size: iconSize,
          color: theme.colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }
}

/// Reusable badge displaying "+{number}" for new chapters released.
/// Positioned to the left of the favorite heart badge at the top-left of the manga card.
class NewChaptersBadge extends StatelessWidget {
  final int count;
  final double height;
  final double fontSize;

  const NewChaptersBadge({
    super.key,
    required this.count,
    this.height = 28,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final countText = count > 99 ? '+99' : '+$count';

    return Container(
      height: height,
      constraints: BoxConstraints(minWidth: height),
      padding: EdgeInsets.symmetric(
        horizontal: max(5.0, height * 0.22),
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          countText,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimary,
            height: 1,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

/// Circular progress badge matching Kotatsu Redo (Material 3 Expressive ProgressDrawable).
/// Positioned at the top-right corner per UI requirements.
class ReadingProgressBadge extends StatelessWidget {
  final double progress;
  final double size;
  final double strokeWidth;

  const ReadingProgressBadge({
    super.key,
    required this.progress,
    this.size = 28,
    this.strokeWidth = 3.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Kotatsu Redo: PROGRESS_COMPLETED_THRESHOLD = 0.99999f
    final isDone = progress >= 0.999;
    final percentInt = isDone ? 100 : ((progress * 100).round()).clamp(0, 99);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: CustomPaint(
        painter: ProgressPainter(
          progress: progress,
          bgColor: theme.colorScheme.secondaryContainer,
          trackColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          progressColor: theme.colorScheme.primary,
          strokeWidth: strokeWidth,
        ),
        child: Center(
          child: isDone
              ? Icon(
                  Icons.check_rounded,
                  size: size * 0.55,
                  color: theme.colorScheme.primary,
                )
              : Text(
                  '$percentInt%',
                  style: TextStyle(
                    fontSize: size * 0.28,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSecondaryContainer,
                    height: 1,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Custom painter for Material 3 Expressive circular progress indicator with track arc & gap.
class ProgressPainter extends CustomPainter {
  final double progress;
  final Color bgColor;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  const ProgressPainter({
    required this.progress,
    required this.bgColor,
    required this.trackColor,
    required this.progressColor,
    this.strokeWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = min(size.width, size.height) / 2;

    // 1. Tonal background circle (fill) - M3 SecondaryContainer
    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), radius, bgPaint);

    final innerRadius = radius - (strokeWidth / 2);
    final arcRect = Rect.fromCircle(center: Offset(cx, cy), radius: innerRadius);

    final sweepDegrees = 360.0 * progress.clamp(0.0, 1.0);
    // Material 3 Expressive: 14 degrees gap between progress indicator and track
    const gapDegrees = 14.0;
    final gap = (sweepDegrees > 0 && sweepDegrees < 360.0) ? gapDegrees : 0.0;

    // 2. Track arc (remaining progress) per M3 Expressive
    final trackSweep = 360.0 - sweepDegrees - (gap * 2.0);
    if (trackSweep > 0) {
      final trackStartDeg = -90.0 + sweepDegrees + gap;
      final trackStartRad = trackStartDeg * (pi / 180.0);
      final trackSweepRad = trackSweep * (pi / 180.0);

      final trackPaint = Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(arcRect, trackStartRad, trackSweepRad, false, trackPaint);
    }

    // 3. Progress arc (active) with round stroke cap
    if (sweepDegrees > 0) {
      final progressSweepRad = sweepDegrees * (pi / 180.0);
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(arcRect, -pi / 2, progressSweepRad, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(ProgressPainter old) =>
      old.progress != progress ||
      old.bgColor != bgColor ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor ||
      old.strokeWidth != strokeWidth;
}
