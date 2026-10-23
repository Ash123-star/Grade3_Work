import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';

void main() {
  test('all cropped dog PNGs decode with transparent pixels', () async {
    final files = Directory('assets/generated_ui/dog')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.png'))
        .toList();
    expect(files, hasLength(48));

    for (final file in files) {
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final frame = await codec.getNextFrame();
      final rgba = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      var minimumAlpha = 255;
      var maximumAlpha = 0;
      for (var offset = 3; offset < rgba.length; offset += 4) {
        final alpha = rgba[offset];
        if (alpha < minimumAlpha) minimumAlpha = alpha;
        if (alpha > maximumAlpha) maximumAlpha = alpha;
      }
      expect(minimumAlpha, 0, reason: file.path);
      expect(maximumAlpha, greaterThan(0), reason: file.path);
      frame.image.dispose();
      codec.dispose();
    }
  });

  testWidgets('reusable dog widgets render without blocking page content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: DogBackground(index: 0, opacity: .1)),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [DogAvatar(index: 2), DogPose(index: 7)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DogAvatar), findsOneWidget);
    expect(find.byType(DogPose), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
