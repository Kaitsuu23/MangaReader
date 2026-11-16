import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildPullFeedbackPillTest({
    required ValueNotifier<double> progressNotifier,
    required bool hasTarget,
    required String readyText,
    required String emptyText,
    required bool isTop,
  }) {
    return ValueListenableBuilder<double>(
      valueListenable: progressNotifier,
      builder: (context, progress, child) {
        final clamped = progress.clamp(0.0, 1.2);
        if (clamped <= 0.0) return const SizedBox.shrink();

        final isReady = clamped >= 1.0;
        final alpha = (0.15 + 0.85 * clamped.clamp(0.0, 1.0)).clamp(0.0, 1.0);
        final scale = 0.9 + 0.1 * clamped.clamp(0.0, 1.0);

        return IgnorePointer(
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: alpha,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xE61E1D24),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isReady && hasTarget
                        ? const Color(0xFF8AB4F8)
                        : const Color(0x33FFFFFF),
                    width: isReady && hasTarget ? 2.0 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isTop ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 16,
                      color: isReady && hasTarget ? const Color(0xFF8AB4F8) : Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasTarget ? readyText : emptyText,
                      style: TextStyle(
                        color: isReady && hasTarget ? const Color(0xFF8AB4F8) : Colors.white,
                        fontSize: 13,
                        fontWeight: isReady && hasTarget ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  group('Kotatsu-style Pull-to-Chapter Transition Tests', () {
    testWidgets('Top pull indicator is hidden when progress is 0', (tester) async {
      final notifier = ValueNotifier<double>(0.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildPullFeedbackPillTest(
              progressNotifier: notifier,
              hasTarget: true,
              readyText: 'Lepas untuk membuka bab sebelumnya',
              emptyText: 'Tidak ada bab sebelumnya',
              isTop: true,
            ),
          ),
        ),
      );

      expect(find.text('Lepas untuk membuka bab sebelumnya'), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('Top pull indicator displays ready text and active border when progress >= 1.0', (tester) async {
      final notifier = ValueNotifier<double>(0.5);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildPullFeedbackPillTest(
              progressNotifier: notifier,
              hasTarget: true,
              readyText: 'Lepas untuk membuka bab sebelumnya',
              emptyText: 'Tidak ada bab sebelumnya',
              isTop: true,
            ),
          ),
        ),
      );

      // Halfway: visible but not ready outline
      expect(find.text('Lepas untuk membuka bab sebelumnya'), findsOneWidget);

      // Now set to 1.0 (ready)
      notifier.value = 1.0;
      await tester.pump();

      expect(find.text('Lepas untuk membuka bab sebelumnya'), findsOneWidget);
      final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      final decoration = container.decoration as BoxDecoration;
      expect((decoration.border as Border).top.color, const Color(0xFF8AB4F8));
      expect((decoration.border as Border).top.width, 2.0);
    });

    testWidgets('Bottom pull indicator shows emptyText when hasTarget is false', (tester) async {
      final notifier = ValueNotifier<double>(1.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildPullFeedbackPillTest(
              progressNotifier: notifier,
              hasTarget: false,
              readyText: 'Lepas untuk membuka bab selanjutnya',
              emptyText: 'Tidak ada bab berikutnya',
              isTop: false,
            ),
          ),
        ),
      );

      expect(find.text('Tidak ada bab berikutnya'), findsOneWidget);
      expect(find.text('Lepas untuk membuka bab selanjutnya'), findsNothing);
    });
  });
}
