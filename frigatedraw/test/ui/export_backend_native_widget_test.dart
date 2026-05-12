// ignore_for_file: avoid-duplicate-collection-elements, avoid-local-functions
import 'dart:convert' show base64;
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatebird/frigatebird.dart';
import 'package:frigatebird/src/ffi/native_image.dart';

void main() {
  final _ = TestWidgetsFlutterBinding.ensureInitialized();

  final bgPath = _getBgPath();

  group('ExportBackendNative UI Binding', () {
    testWidgets('NativeImage bytes can be bound to UI and merged concurrently', (tester) async {
      // 1. Create a 1x1 red PNG.
      final redPng = _create1x1RedPng();

      // Wrap in NativeImage.
      final nativeImage = NativeImage.fromBytes(redPng, height: 1, width: 1);

      // 2. Bind to a Flutter widget.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Image.memory(
                nativeImage.bytes, // The zero-copy view.
                height: 50,
                semanticLabel: 'test image',
                width: 50,
              ),
            ),
          ),
        ),
      );

      // Let the image decode and render.
      final _ = await tester.pumpAndSettle();

      // Verify the image widget is in the tree.
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      // 3. Concurrently run the merge operation using the identical source bytes.
      const backend = ExportBackendNative();

      Future<void> performMerge() async {
        final result = await backend.merge(
          backgroundPath: bgPath,
          foregroundPng: nativeImage.bytes,
        );
        expect(result, isNotEmpty);
      }

      await tester.runAsync(performMerge);

      // Re-pump to ensure the widget didn't crash due to detached memory.
      await tester.pump();
      expect(imageFinder, findsOneWidget);

      // Cleanup.
      nativeImage.dispose();
    });
  });
}

Uint8List _create1x1RedPng() {
  // A standard 1x1 red PNG.
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  return base64.decode(b64);
}

String _getBgPath() {
  final candidates = [
    '../frigatebird/test/assets/paint.jpg',
    'frigatebird/test/assets/paint.jpg',
    'test/assets/paint.jpg',
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }

  throw StateError('Fixture paint.jpg not found. Checked: $candidates. CWD: ${Uri.base}');
}
