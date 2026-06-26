// Integration widget test: verifies bytes from RenderImage.orientedBytes decode and render in
// Flutter's image pipeline. Skipped when the EXIF fixture is not on disk (e.g. partial checkout).
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatebird/frigatebird.dart';

const _noLabel = '';

void main() {
  final _ = TestWidgetsFlutterBinding.ensureInitialized();

  // The exif_6.jpg fixture is 128x64 landscape with orientation tag 6, decoded to 64x128 portrait.
  final fixturePath = _getExifFixturePath();

  group(
    'RenderImage.orientedBytes Flutter rendering',
    () {
      testWidgets('PNG bytes are rendered by Image without throwing', (tester) async {
        // Call real FFI in the test isolate.
        final bytes = await tester.runAsync(
          () => RenderImage.orientedBytes(imagePath: fixturePath),
        );

        expect(bytes, isNotNull);
        if (bytes == null) return;
        expect(bytes, isNotEmpty, reason: 'RenderImage.orientedBytes must return non-empty bytes');

        // Build a widget tree that actually decodes the bytes into a Flutter image.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Image(image: MemoryImage(bytes), semanticLabel: _noLabel),
            ),
          ),
        );
        // Settle is best-effort; the Image widget being found confirms it was built without error.
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsOneWidget);
      });

      testWidgets('JPEG format bytes are also rendered by Image.memory without throwing', (
        tester,
      ) async {
        final bytes = await tester.runAsync(
          () => RenderImage.orientedBytes(format: .jpg, imagePath: fixturePath),
        );

        if (bytes == null) return;
        expect(bytes, isNotEmpty, reason: 'JPEG orientedBytes must return non-empty bytes');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Image.memory(bytes, semanticLabel: _noLabel)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Image), findsOneWidget);
      });
    },
    skip: fixturePath.isEmpty
        ? 'EXIF fixture not found on disk; skipping RenderImage.orientedBytes integration tests'
        : null,
  );
}

String _getExifFixturePath() {
  const candidates = [
    '../frigatebird/rust/tests/fixtures/orientation/exif_6.jpg',
    'frigatebird/rust/tests/fixtures/orientation/exif_6.jpg',
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }

  // ignore: no-empty-string, Native lib not built; tests will skip.
  return '';
}
