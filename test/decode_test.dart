import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_app/shared/widgets/webtoon_safe_image.dart';

void main() {
  testWidgets('WebtoonSafeImage slices 24k px image properly', (tester) async {
    final file = File('../test_page0.webp');
    if (!file.existsSync()) {
      return;
    }
    final bytes = file.readAsBytesSync();
    final memoryProvider = MemoryImage(bytes);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebtoonSafeImage(
                imageProvider: memoryProvider,
                fit: BoxFit.fitWidth,
                width: double.infinity,
              ),
            ),
          ),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));
    });

    await tester.pump();

    final rawImages = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    expect(rawImages.length, 9);

    final size = tester.getSize(find.byType(WebtoonSafeImage));
    final expectedHeight = 800 * (24656 / 720);
    expect((size.height - expectedHeight).abs() < 1.0, isTrue);
  });

  testWidgets('WebtoonSafeImage handles normal height images without slicing', (tester) async {
    late Uint8List pngBytes;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 800, 1200));
      canvas.drawRect(const Rect.fromLTWH(0, 0, 800, 1200), Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      final uiImg = picture.toImageSync(800, 1200);
      final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
      pngBytes = byteData!.buffer.asUint8List();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebtoonSafeImage(
                imageProvider: MemoryImage(pngBytes),
                fit: BoxFit.fitWidth,
                width: double.infinity,
              ),
            ),
          ),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 100));
    });

    await tester.pump();

    final rawImages = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    expect(rawImages.length, 1);
    final size = tester.getSize(find.byType(WebtoonSafeImage));
    expect(size.height, 1200.0);
  });
}
