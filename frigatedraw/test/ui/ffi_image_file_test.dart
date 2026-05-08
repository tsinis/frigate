// ignore_for_file: avoid-ignoring-return-values, avoid-returning-widgets, prefer-correct-handler-name, prefer-commenting-analyzer-ignores, prefer-match-file-name, no-object-declaration, prefer-extracting-function-callbacks, avoid-collection-mutating-methods, avoid-duplicate-test-assertions, avoid-unsafe-collection-methods, prefer-moving-to-variable, avoid-local-functions

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

class _ErrorWidget extends StatelessWidget {
  const _ErrorWidget({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Text('Error: $error');
}

void main() {
  group(FfiImageFile, () {
    testWidgets('shows image with correct dimensions after load', (tester) async {
      final file = File('../frigatebird/rust/tests/fixtures/orientation/exif_6.jpg');
      if (!file.existsSync()) {
        final altFile = File('frigatebird/rust/tests/fixtures/orientation/exif_6.jpg');
        if (!altFile.existsSync()) {
          print('Skipping test: fixtures not found');

          return;
        }
      }

      final targetFile = file.existsSync()
          ? file
          : File('frigatebird/rust/tests/fixtures/orientation/exif_6.jpg');

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FfiImageFile(
                targetFile,
                errorBuilder: (bc, error, stack) => _ErrorWidget(error: error),
              ),
            ),
          ),
        );

        // Wait for the async getImageInfo call to complete in the background.
        int attempts = 0;
        while (attempts < 50) {
          // Wait for the background worker (Rust) to finish parsing.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          if (find.byType(Image).evaluate().length > 1 ||
              find.textContaining('Error:').evaluate().isNotEmpty) {
            break;
          }
          attempts += 1;
        }
      });

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

      final finalImage = widgetList.last;
      // Tag 6 is RightTop (90 deg CW rotation) -> original 128x64 becomes 64x128.
      expect(finalImage.width, 64.0);
      expect(finalImage.height, 128.0);
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

      // Inject a failing builder.
      FfiImageFile.infoBuilder = (path) => Future.error('Probe failed');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FfiImageFile(
              file,
              errorBuilder: (bc, error, stack) => _ErrorWidget(error: error),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Error: Probe failed'), findsOneWidget);

      // Reset builder.
      FfiImageFile.infoBuilder = ImageInformation.probe;
    });

    testWidgets('does not re-probe when widget updates with same file path', (tester) async {
      final file = File('cached.jpg');
      int probeCount = 0;

      Future<ImageInformation> mockBuilder(String _) {
        probeCount += 1;

        return Future.value(const ImageInformation(height: 400, width: 300));
      }

      FfiImageFile.infoBuilder = mockBuilder;

      // First mount.
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(file))));
      await tester.pumpAndSettle();
      expect(probeCount, 1);

      // Update with same file path.
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(File('cached.jpg')))));
      await tester.pumpAndSettle();

      // Should still be 1 if didUpdateWidget correctly kept the same future.
      expect(probeCount, 1);

      // Reset builder.
      FfiImageFile.infoBuilder = ImageInformation.probe;
    });

    testWidgets('calls builder with resolved image', (tester) async {
      final file = File('test.jpg');
      Image? resolvedImage;

      FfiImageFile.infoBuilder = (path) async => const ImageInformation(height: 400, width: 300);

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

      // Reset builder.
      FfiImageFile.infoBuilder = ImageInformation.probe;
    });
  });
}
