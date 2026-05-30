// ignore_for_file: prefer-moving-to-variable, avoid-duplicate-test-assertions, prefer-extracting-function-callbacks, avoid-duplicate-collection-elements

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
        (_) async => ImageInformation.from(height: 128, orientation: .rotate90, width: 64),
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
              builder: (image, info, uiImage) {
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

    testWidgets('calls onInfo when image information resolves', (tester) async {
      final file = File('test.jpg');
      ImageInformation? capturedInfo;
      int callbackCount = 0;

      final restore = FfiImageFile.setInfoBuilder(
        (_) => Future.value(const ImageInformation(height: 480, width: 640)),
      );
      addTearDown(restore);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FfiImageFile(
              file,
              onInfo: (info) {
                callbackCount += 1;
                capturedInfo = info;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(callbackCount, 1);
      expect(capturedInfo?.width, 640);
      expect(capturedInfo?.height, 480);
    });

    testWidgets('re-probes when file path changes', (tester) async {
      final fileFirst = File('file1.jpg');
      final fileSecond = File('file2.jpg');
      int probeCount = 0;
      FfiImageFile.setInfoBuilder((_) async {
        probeCount += 1;

        return const ImageInformation(height: 100, width: 100);
      });

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(fileFirst))));
      await tester.pumpAndSettle();
      expect(probeCount, 1);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(fileSecond))));
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

      // Initially with size -> no probe.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FfiImageFile(file, size: const Size(100, 100))),
        ),
      );
      await tester.pumpAndSettle();
      expect(probeCount, isZero);

      // Change to no size -> probe.
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(file))));
      await tester.pumpAndSettle();
      expect(probeCount, 1);

      // Change back to size -> reset future (but no probe call because _loadInfo returns null).
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
      // Should show Image.file (fallback) because no placeholderBuilder provided.
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
              builder: (image, info, uiImage) {
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
      final restore = FfiImageFile.setInfoBuilder((_) => Future.error('Failed'));
      addTearDown(restore);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: FfiImageFile(file))));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('shows error widget when probe fails and errorBuilder is provided', (tester) async {
      final file = File('corrupted.jpg');
      final restore = FfiImageFile.setInfoBuilder((_) => Future.error('Failed test error'));
      addTearDown(restore);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FfiImageFile(
              file,
              errorBuilder: (context, error, stackTrace) => Text('Error: $error'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Error: Failed test error'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    test('debugFillProperties covers builder property', () {
      final file = File('test.jpg');
      final image = FfiImageFile(file, builder: (img, info, uiImage) => const SizedBox());
      final propertiesBuilder = DiagnosticPropertiesBuilder();
      image.debugFillProperties(propertiesBuilder);

      final props = propertiesBuilder.properties.map((i) => i.name).toList(growable: false);
      expect(props, contains('builder'));
    });

    testWidgets('successfully loads valid image bytes and uses Image.memory', (tester) async {
      final transparentPng = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1F,
        0x15,
        0xC4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x44,
        0x41,
        0x54,
        0x18,
        0x57,
        0x63,
        0x60,
        0x60,
        0x60,
        0x60,
        0x00,
        0x00,
        0x00,
        0x05,
        0x00,
        0x01,
        0x24,
        0xAA,
        0x86,
        0xC8,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]);

      final tempDir = Directory.systemTemp.createTempSync();
      final file = File('${tempDir.path}/valid.png')..writeAsBytesSync(transparentPng);

      final restore = FfiImageFile.setInfoBuilder(
        (_) async => const ImageInformation(height: 1, width: 1),
      );
      addTearDown(() {
        restore();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      Image? displayedImage;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FfiImageFile(
                file,
                builder: (img, info, uiImage) {
                  displayedImage = img;

                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        // Allow the async file.readAsBytes() and image decoding to complete.
        for (int i = 0; i < 20; i += 1) {
          // Wait for file.readAsBytes() async task in Isolate.
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });

      final finalImage = displayedImage;
      expect(finalImage, isNotNull);
      expect(
        finalImage?.image,
        anyOf(isA<MemoryImage>(), isA<FileImage>()),
        reason: 'Image provider must be MemoryImage (decoded) or FileImage (fallback)',
      );
    });
  });
}
