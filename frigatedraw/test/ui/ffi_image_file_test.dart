// ignore_for_file: avoid-ignoring-return-values, prefer-moving-to-variable, avoid-duplicate-test-assertions, format-comment, avoid-similar-names, prefer-extracting-function-callbacks

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

class _FfiImageFileTest extends StatelessWidget {
  const _FfiImageFileTest({required this.error});

  final Object error; // ignore: diagnostic_describe_all_properties,no-object-declaration, it's test

  @override
  Widget build(BuildContext context) => Text('Error: $error');
}

void main() {
  group(FfiImageFile, () {
    testWidgets('shows image with correct dimensions after load', (tester) async {
      final file = File('test.jpg');

      final restore = FfiImageFile.setInfoBuilder(
        (_) => Future.value(const ImageInformation(height: 128, orientation: 6, width: 64)),
      );
      addTearDown(restore);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FfiImageFile(
              file,
              errorBuilder: (bc, error, stack) => _FfiImageFileTest(error: error),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final errorFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.data != null && (widget.data?.startsWith('Error:') ?? false),
      );
      if (errorFinder.evaluate().isNotEmpty) {
        final textWidget = tester.widget<Text>(errorFinder);
        final errorMessage = textWidget.data ?? 'Unknown error';
        fail('FfiImageFile failed with error: $errorMessage');
      }

      // There are two images: one in the FutureBuilder (placeholder/fallback) and one final.
      final imageFinder = find.byType(Image);
      final widgetList = tester.widgetList<Image>(imageFinder);
      expect(widgetList.length, greaterThanOrEqualTo(1));

      final finalImage = widgetList.lastOrNull;
      // Tag 6 is RightTop (90 deg CW rotation) -> original 128x64 becomes 64x128.
      expect(finalImage?.width, 64.0);
      expect(finalImage?.height, 128.0);
    });

    testWidgets('respects provided width/height and skips FFI', (tester) async {
      final file = File('dummy.jpg');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FfiImageFile(file, size: const Size(100, 200))),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.width, 100.0);
      expect(imageWidget.height, 200.0);
    });

    testWidgets('falls back to Image.file and calls errorBuilder on probe failure', (tester) async {
      final file = File('corrupted.jpg');

      final restore = FfiImageFile.setInfoBuilder((_) => Future.error('Probe failed'));
      addTearDown(restore);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FfiImageFile(
              file,
              errorBuilder: (bc, error, stack) => _FfiImageFileTest(error: error),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Error: Probe failed'), findsOneWidget);
    });

    testWidgets('does not re-probe when widget updates with same file path', (tester) async {
      final file = File('cached.jpg');
      int probeCount = 0;

      // ignore: avoid-local-functions, it's fine for a test.
      Future<ImageInformation> mockBuilder(String _) {
        probeCount += 1;

        return Future.value(const ImageInformation(height: 400, width: 300));
      }

      final restore = FfiImageFile.setInfoBuilder(mockBuilder);
      addTearDown(restore);

      // First mount.
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(file))));
      await tester.pumpAndSettle();
      expect(probeCount, 1);

      // Update with same file path.
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(File('cached.jpg')))));
      await tester.pumpAndSettle();

      // Should still be 1 if didUpdateWidget correctly kept the same future.
      expect(probeCount, 1);
    });

    testWidgets('calls builder with resolved image', (tester) async {
      final file = File('test.jpg');
      Image? resolvedImage;

      final restore = FfiImageFile.setInfoBuilder(
        (_) => Future.value(const ImageInformation(height: 400, width: 300)),
      );
      addTearDown(restore);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FfiImageFile(
              file,
              builder: (context, image) {
                resolvedImage = image;

                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(resolvedImage?.width, 300.0);
      expect(resolvedImage?.height, 400.0);
    });

    testWidgets('re-probes when file path changes', (tester) async {
      final file1 = File('file1.jpg');
      final file2 = File('file2.jpg');
      int probeCount = 0;
      FfiImageFile.setInfoBuilder((_) async {
        probeCount += 1;

        return const ImageInformation(height: 100, width: 100);
      });

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(file1))));
      await tester.pumpAndSettle();
      expect(probeCount, 1);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(file2))));
      await tester.pumpAndSettle();
      expect(probeCount, 2);
    });

    testWidgets('re-probes when size nullability changes', (tester) async {
      final file = File('test.jpg');
      int probeCount = 0;
      FfiImageFile.setInfoBuilder((_) async {
        probeCount += 1;

        return const ImageInformation(height: 100, width: 100);
      });

      // Initially with size -> no probe
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FfiImageFile(file, size: const Size(100, 100))),
        ),
      );
      await tester.pumpAndSettle();
      expect(probeCount, 0);

      // Change to no size -> probe
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(file))));
      await tester.pumpAndSettle();
      expect(probeCount, 1);

      // Change back to size -> reset future (but no probe call because _loadInfo returns null)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FfiImageFile(file, size: const Size(200, 200))),
        ),
      );
      await tester.pumpAndSettle();
      expect(probeCount, 1);
    });

    testWidgets('shows image while waiting if builder is not provided', (tester) async {
      final file = File('test.jpg');
      final completer = Completer<ImageInformation>();
      FfiImageFile.setInfoBuilder((_) => completer.future);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(file))));
      // Should show Image.file (fallback) because no placeholderBuilder provided
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('calls builder with null data while loading', (tester) async {
      final file = File('test.jpg');
      final completer = Completer<ImageInformation>();
      FfiImageFile.setInfoBuilder((_) => completer.future);

      bool isCalledWithNull = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FfiImageFile(
              file,
              builder: (context, image) {
                if (image.width == null) isCalledWithNull = true;

                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(isCalledWithNull, isTrue);
    });

    testWidgets('falls back to Image.file when probe fails and errorBuilder is null', (
      tester,
    ) async {
      final file = File('corrupted.jpg');
      FfiImageFile.setInfoBuilder((_) => Future.error('Failed'));

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(file))));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
    });
  });
}
