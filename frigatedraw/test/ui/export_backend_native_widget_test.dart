// ignore_for_file: avoid-duplicate-collection-elements, avoid-local-functions
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
  const data = [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    2,
    0,
    0,
    0,
    144,
    119,
    83,
    222,
    0,
    0,
    0,
    12,
    73,
    68,
    65,
    84,
    8,
    215,
    99,
    248,
    207,
    192,
    0,
    0,
    3,
    1,
    1,
    0,
    24,
    221,
    141,
    176,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ];

  return Uint8List.fromList(data);
}

String _getBgPath() {
  final segments = Uri.base.pathSegments;
  final lastSegment = segments.isNotEmpty
      ? segments.lastWhere((segment) => segment.isNotEmpty, orElse: () => 'none')
      : 'none';

  return lastSegment == 'frigatedraw'
      ? '../frigatebird/test/assets/paint.jpg'
      : 'frigatebird/test/assets/paint.jpg';
}
