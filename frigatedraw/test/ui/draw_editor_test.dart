// ignore_for_file: avoid-ignoring-return-values, avoid-long-files

import 'dart:io';
import 'dart:typed_data' show Float64x2, Float64x2List;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group(DrawEditor, () {
  final file = File('test.jpg');

  testWidgets('renders image and CustomPaint', (tester) async {
    final controller = DrawController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(FfiImageFile), findsOneWidget);
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
  });

  testWidgets('applies initial fit transform from resolved image info', (tester) async {
    final controller = DrawController();
    final restore = FfiImageFile.setInfoBuilder(
      (_) => Future.value(const ImageInformation(height: 600, width: 800)),
    );
    addTearDown(restore);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 300,
              width: 400,
              child: DrawEditor(file, controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final interactiveViewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final matrix = interactiveViewer.transformationController?.value;

    expect(matrix?.storage.firstOrNull, closeTo(0.5, 0.001));
    expect(matrix?.storage.elementAtOrNull(5), closeTo(0.5, 0.001));
    expect(matrix?.storage.elementAtOrNull(12), closeTo(0.0, 0.001));
    expect(matrix?.storage.elementAtOrNull(13), closeTo(0.0, 0.001));
  });

  testWidgets('keeps user transform after initial fit is applied once', (tester) async {
    final controller = DrawController();
    final restore = FfiImageFile.setInfoBuilder(
      (_) => Future.value(const ImageInformation(height: 600, width: 800)),
    );
    addTearDown(restore);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 300,
              width: 400,
              child: DrawEditor(file, controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final interactiveViewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final transformationController = interactiveViewer.transformationController;
    transformationController?.value = Matrix4.identity()
      ..setEntry(0, 0, 2)
      ..setEntry(1, 1, 2);
    await tester.pump();
    await tester.pump();

    expect(transformationController?.value.storage.firstOrNull, closeTo(2.0, 0.001));
    expect(transformationController?.value.storage.elementAtOrNull(5), closeTo(2.0, 0.001));
  });

  testWidgets('scales handle radius proportionally for large images', (tester) async {
    final controller = DrawController();
    // 3200x2400 image: max dimension = 3200, scale = 3200/800 = 4 -> handleRadius = 48.
    final restore = FfiImageFile.setInfoBuilder(
      (_) => Future.value(const ImageInformation(height: 2400, width: 3200)),
    );
    addTearDown(restore);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, width: 800, child: DrawEditor(file, controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((customPaint) => customPaint.foregroundPainter)
        .whereType<DrawPainter>()
        .firstOrNull;

    expect(
      painter?.handleRadius,
      closeTo(48.0, 0.001),
      reason: 'handle radius should scale 4x for a 3200-wide image',
    );
  });

  testWidgets('handle radius stays at 12 for 800x600 reference image', (tester) async {
    final controller = DrawController();
    final restore = FfiImageFile.setInfoBuilder(
      (_) => Future.value(const ImageInformation(height: 600, width: 800)),
    );
    addTearDown(restore);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, width: 800, child: DrawEditor(file, controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((customPaint) => customPaint.foregroundPainter)
        .whereType<DrawPainter>()
        .firstOrNull;

    expect(
      painter?.handleRadius,
      closeTo(12.0, 0.001),
      reason: 'handle radius must not shrink below reference at 800x600',
    );
  });

  testWidgets('handle radius does not shrink below 12 for small images', (tester) async {
    final controller = DrawController();
    // 320x240 is smaller than the 800x600 base — should clamp to 12.
    final restore = FfiImageFile.setInfoBuilder(
      (_) => Future.value(const ImageInformation(height: 240, width: 320)),
    );
    addTearDown(restore);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, width: 800, child: DrawEditor(file, controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((customPaint) => customPaint.foregroundPainter)
        .whereType<DrawPainter>()
        .firstOrNull;

    expect(
      painter?.handleRadius,
      closeTo(12.0, 0.001),
      reason: 'handle radius must clamp to 12 for images smaller than the 800px reference',
    );
  });

  testWidgets('scales outline stroke at half handle rate for large images', (tester) async {
    final controller = DrawController();
    // 3200x2400: handle scale = 3200/800 = 4x, outline scale = 3200/1600 = 2x -> strokeWidth = 8.
    final restore = FfiImageFile.setInfoBuilder(
      (_) => Future.value(const ImageInformation(height: 2400, width: 3200)),
    );
    addTearDown(restore);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, width: 800, child: DrawEditor(file, controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((customPaint) => customPaint.foregroundPainter)
        .whereType<DrawPainter>()
        .firstOrNull;

    expect(
      painter?.outlineStrokeWidth,
      closeTo(8.0, 0.001),
      reason: 'outline stroke should scale 2x (half of handle 4x) for a 3200-wide image',
    );
  });

  testWidgets('outline stroke stays at 4 for 800x600 reference image', (tester) async {
    final controller = DrawController();
    final restore = FfiImageFile.setInfoBuilder(
      (_) => Future.value(const ImageInformation(height: 600, width: 800)),
    );
    addTearDown(restore);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, width: 800, child: DrawEditor(file, controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((customPaint) => customPaint.foregroundPainter)
        .whereType<DrawPainter>()
        .firstOrNull;

    expect(
      painter?.outlineStrokeWidth,
      closeTo(4.0, 0.001),
      reason: 'outline stroke must not shrink below reference at 800x600',
    );
  });

  testWidgets('outline stroke does not shrink below 4 for small images', (tester) async {
    final controller = DrawController();
    final restore = FfiImageFile.setInfoBuilder(
      (_) => Future.value(const ImageInformation(height: 240, width: 320)),
    );
    addTearDown(restore);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, width: 800, child: DrawEditor(file, controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((customPaint) => customPaint.foregroundPainter)
        .whereType<DrawPainter>()
        .firstOrNull;

    expect(
      painter?.outlineStrokeWidth,
      closeTo(4.0, 0.001),
      reason: 'outline stroke must clamp to 4 for images smaller than the 800px reference',
    );
  });

  testWidgets('does not dispose external controller when parent rebuilds with controller: null', (
    tester,
  ) async {
    final external = DrawController();
    final key = GlobalKey();

    // Mount with external controller.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: external, key: key),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Rebuild without external controller.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, width: 800, child: DrawEditor(file, key: key)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // External controller must still be usable.
    expect(
      () => external.addElement(const RectElement(height: 10, width: 10, x: 0, y: 0)),
      returnsNormally,
      reason: 'external controller must not be disposed by DrawEditor',
    );
    external.dispose();
  });

  testWidgets('builder overlay receives correct args after image loads', (tester) async {
    final restore = FfiImageFile.setInfoBuilder(
      (_) => Future.value(const ImageInformation(height: 600, width: 800)),
    );
    addTearDown(restore);

    DrawController? receivedController;
    ImageInformation? receivedInfo;
    TransformationController? receivedTransform;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(
              file,
              builder: (controller, info, transform) {
                receivedController = controller;
                receivedInfo = info;
                receivedTransform = transform;

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      receivedController,
      isNotNull,
      reason: 'internal controller must be created when no controller is passed',
    );
    expect(receivedInfo, equals(const ImageInformation(height: 600, width: 800)));
    expect(receivedTransform, isNotNull);
  });

  testWidgets('builder overlay is replaced by external controller when one is provided', (
    tester,
  ) async {
    final restore = FfiImageFile.setInfoBuilder(
      (_) => Future.value(const ImageInformation(height: 600, width: 800)),
    );
    addTearDown(restore);

    final externalController = DrawController();
    DrawController? receivedController;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(
              file,
              builder: (controller, info, transform) {
                receivedController = controller;

                return const SizedBox.shrink();
              },
              controller: externalController,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      receivedController,
      same(externalController),
      reason: 'builder must receive the externally supplied controller',
    );
  });
  testWidgets('selects element on tap on outline', (tester) async {
    final controller = DrawController();
    const rect = RectElement(height: 100, width: 100, x: 50, y: 50);
    controller
      ..addElement(rect)
      ..selectedIndex = null;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    // Tap on the top-left corner (50, 50).
    await tester.tapAt(topLeft + const Offset(50, 50));
    await tester.pump();

    expect(controller.selectedIndex, 0);
  });

  testWidgets('moves element on drag', (tester) async {
    final controller = DrawController();
    const rect = RectElement(height: 100, width: 100, x: 50, y: 50);
    controller
      ..addElement(rect)
      ..selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    // Start drag from center (100, 100).
    final gesture = await tester.startGesture(topLeft + const Offset(100, 100));
    await tester.pump();

    // Move by 50, 50.
    await gesture.moveBy(const Offset(50, 50));
    await tester.pump();

    expect(controller.elements.firstOrNull?.x, closeTo(100.0, 0.1));
    expect(controller.elements.firstOrNull?.y, closeTo(100.0, 0.1));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('resizes element via handles', (tester) async {
    final controller = DrawController();
    const rect = RectElement(height: 100, width: 100, x: 100, y: 100);
    controller
      ..addElement(rect)
      ..selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    TestGesture gesture = await tester.startGesture(topLeft + const Offset(100, 100));
    await tester.pump();
    await gesture.moveBy(const Offset(-20, -20));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.elements.firstOrNull?.x, closeTo(80.0, 0.1));
    expect(controller.elements.firstOrNull?.width, closeTo(120.0, 0.1));

    // 2. Bottom-right handle (200, 200).
    gesture = await tester.startGesture(topLeft + const Offset(200, 200));
    await tester.pump();
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.elements.firstOrNull?.width, closeTo(130.0, 0.1));
    expect(controller.elements.firstOrNull?.height, closeTo(130.0, 0.1));

    gesture = await tester.startGesture(topLeft + const Offset(145, 80)); // 3. Top-center handle.
    await tester.pump();
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.elements.firstOrNull?.y, closeTo(70.0, 0.1));
    expect(controller.elements.firstOrNull?.height, closeTo(140.0, 0.1));

    gesture = await tester.startGesture(topLeft + const Offset(80, 140)); // 4. Center-left handle.
    await tester.pump();
    await gesture.moveBy(const Offset(-10, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.elements.firstOrNull?.x, closeTo(70.0, 0.1));
    expect(controller.elements.firstOrNull?.width, closeTo(140.0, 0.1));
  });

  testWidgets('cancels drag on pointer cancel', (tester) async {
    final controller = DrawController();
    const rect = RectElement(height: 100, width: 100, x: 50, y: 50);
    controller
      ..addElement(rect)
      ..selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    final gesture = await tester.startGesture(topLeft + const Offset(50, 50));
    await tester.pump();
    await gesture.moveBy(const Offset(50, 50));
    await tester.pump();

    expect(
      controller.elements.firstOrNull?.x,
      closeTo(100.0, 0.1),
      reason: 'The element moved mid-drag',
    );

    await gesture.cancel(); // Cancel the gesture!
    await tester.pump();

    expect(
      controller.commandStack.canUndo,
      isFalse,
      reason: 'Undo stack was NOT populated because commitCommand never ran',
    );
  });

  testWidgets('ignores drag on TextElement', (tester) async {
    final controller = DrawController();
    const text = TextElement(text: 'Hello', x: 50, y: 50);
    controller.addElement(text);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    await tester.tapAt(topLeft + const Offset(50, 50)); // Try clicking on the text coordinates.
    await tester.pump();

    expect(
      controller.selectedIndex,
      isNull,
      reason: 'Should NOT be selected because hitTest for TextElement returns false',
    );

    controller.selectedIndex = 0; // Force selection to try dragging.

    final gesture = await tester.startGesture(topLeft + const Offset(50, 50));
    await tester.pump();
    await gesture.moveBy(const Offset(50, 50));
    await tester.pump();

    expect(controller.elements.firstOrNull?.x, 50.0);
    expect(
      controller.elements.firstOrNull?.y,
      50.0,
      reason: 'Should NOT move because canMove = false for TextElement',
    );

    await gesture.up();
  });

  group('Edge Cases', () {
    testWidgets('aborts creation if element is removed mid-drag', (tester) async {
      final controller = DrawController()
        ..creationTemplate = const RectElement(height: 0, width: 0, x: 0, y: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ivFinder = find.byType(InteractiveViewer);
      final topLeft = tester.getTopLeft(ivFinder);

      final gesture = await tester.startGesture(topLeft + const Offset(100, 100)); // Start create.
      await tester.pump();
      expect(controller.elements.length, 1);

      controller.dropElementAt(0); // Mutate list from underneath!
      expect(controller.elements, isEmpty);

      await gesture.moveBy(const Offset(50, 50)); // Move should trigger abortCreation.
      await tester.pump();

      await gesture.up(); // Release should also handle it gracefully.
      await tester.pump();

      expect(controller.creationTemplate, isNull);
    });

    testWidgets('aborts creation if element is removed just before pointer up', (tester) async {
      final controller = DrawController()
        ..creationTemplate = const RectElement(height: 0, width: 0, x: 0, y: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ivFinder = find.byType(InteractiveViewer);
      final topLeft = tester.getTopLeft(ivFinder);

      final gesture = await tester.startGesture(topLeft + const Offset(100, 100)); // Start create.
      await tester.pump();

      controller.dropElementAt(0); // Mutate list just before release.

      await gesture.up();
      await tester.pump();

      expect(controller.creationTemplate, isNull);
    });

    testWidgets('resolves correct preview index if background element is deleted during creation', (
      tester,
    ) async {
      final controller = DrawController()
        ..addElement(const RectElement(height: 10, width: 10, x: 0, y: 0)) // Index 0.
        ..creationTemplate = const RectElement(height: 0, width: 0, x: 0, y: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ivFinder = find.byType(InteractiveViewer);
      final topLeft = tester.getTopLeft(ivFinder);

      final gesture = await tester.startGesture(topLeft + const Offset(100, 100)); // Start create.
      await tester.pump();

      // Now there are 2 elements. index 0 is the old one, index 1 is the preview.
      expect(controller.elements.length, 2);

      // Mutate list: delete the background element (index 0).
      // The preview element shifts to index 0.
      controller.dropElementAt(0);
      expect(controller.elements.length, 1);

      // Continue the gesture. It should resolve the new index and update the size without aborting.
      await gesture.moveBy(const Offset(50, 50));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // The creation template should be cleared, and we should have a sized element.
      expect(controller.creationTemplate, isNull);
      final created = controller.elements.singleOrNull;
      expect(created?.width, 50.0);
      expect(created?.height, 50.0);
    });

    testWidgets('handleMove skips TextElement', (tester) async {
      final controller = DrawController();
      const rect = RectElement(height: 100, width: 100, x: 50, y: 50);
      controller
        ..addElement(rect)
        ..selectedIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ivFinder = find.byType(InteractiveViewer);
      final topLeft = tester.getTopLeft(ivFinder);

      // Start dragging the rect center (100, 100).
      final gesture = await tester.startGesture(topLeft + const Offset(100, 100));
      await tester.pump();

      // SWAP it for a text element mid-drag!
      controller.updateElement(const TextElement(text: 'hi', x: 50, y: 50), 0);

      await gesture.moveBy(const Offset(10, 10)); // Move should.
      await tester.pump();

      expect(controller.elements.firstOrNull?.x, 50.0, reason: 'Should not have moved');
      await gesture.up();
    });
    testWidgets('resizing explicit hit', (tester) async {
      final controller = DrawController();
      const rect = RectElement(height: 100, width: 100, x: 100, y: 100);
      controller
        ..addElement(rect)
        ..selectedIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ivFinder = find.byType(InteractiveViewer);
      final topLeft = tester.getTopLeft(ivFinder);

      // Top-left handle is at (100, 100) document space.
      final gesture = await tester.startGesture(topLeft + const Offset(100, 100));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 10));
      await tester.pump();
      expect(controller.elements.firstOrNull?.width, 90.0);
      await gesture.up();
    });

    testWidgets('snaps matrix back during single-pointer drag (jitter prevention)', (tester) async {
      final controller = DrawController();
      const rect = RectElement(height: 100, width: 100, x: 50, y: 50);
      controller
        ..addElement(rect)
        ..selectedIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ivFinder = find.byType(InteractiveViewer);
      final viewerTopLeft = tester.getTopLeft(ivFinder);
      final ivWidget = tester.widget<InteractiveViewer>(ivFinder);
      final transformationController = ivWidget.transformationController;

      // 1. Start a drag on the element center (100, 100) document space.
      final dragGesture = await tester.startGesture(viewerTopLeft + const Offset(100, 100));
      await tester.pump();
      expect(controller.selectedIndex, 0);

      // 2. While drag is active, manually nudge the matrix (simulating IV jitter).
      final jitterMatrix = Matrix4.identity()..translateByDouble(10, 10, 0, 1);
      transformationController?.value = jitterMatrix;

      // 3. Verify it snapped back IMMEDIATELY (synchronously).
      expect(
        transformationController?.value,
        Matrix4.identity(),
        reason: 'Matrix must snap back to identity during drag',
      );

      await dragGesture.up();
    });
  });

  test('debugFillProperties coverage', () {
    final draw = DrawController();
    final builder = DiagnosticPropertiesBuilder();
    DrawEditor(file, controller: draw, size: const .new(100, 200)).debugFillProperties(builder);
    final props = builder.properties.map((i) => i.name).toList();
    expect(props, contains('_controller'));
    expect(props, contains('_image'));
    expect(props, contains('_size.height'));
    expect(props, contains('_size.width'));
  });
  testWidgets('moves PolygonElement on drag', (tester) async {
    final controller = DrawController();
    final vertices = Float64x2List.fromList([
      Float64x2(50, 50),
      Float64x2(150, 50),
      Float64x2(100, 150),
    ]);
    final poly = PolygonElement(height: 100, vertices: vertices, width: 100, x: 50, y: 50);
    controller
      ..addElement(poly)
      ..selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    // Drag from inside the polygon (center ~100, 83).
    final gesture = await tester.startGesture(topLeft + const Offset(100, 83));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();

    final moved = controller.elements.firstOrNull;
    expect(moved, isA<PolygonElement>());
    expect(moved?.x, closeTo(70.0, 0.5));
    expect(moved?.y, closeTo(60.0, 0.5));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('resizes PolygonElement via corner handle', (tester) async {
    final controller = DrawController();
    final vertices = Float64x2List.fromList([
      Float64x2(100, 100),
      Float64x2(200, 100),
      Float64x2(150, 200),
    ]);
    final poly = PolygonElement(height: 100, vertices: vertices, width: 100, x: 100, y: 100);
    controller
      ..addElement(poly)
      ..selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    // Bottom-right handle is at (200, 200).
    final gesture = await tester.startGesture(topLeft + const Offset(200, 200));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 20));
    await tester.pump();

    final resized = controller.elements.firstOrNull;
    expect(resized, isA<PolygonElement>());
    expect(resized?.width, closeTo(120.0, 1.0));
    expect(resized?.height, closeTo(120.0, 1.0));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('aborts creation on pointer cancel during polygon creation', (tester) async {
    final controller = DrawController();
    final vertices = Float64x2List.fromList([Float64x2(0, 0), Float64x2(0, 0), Float64x2(0, 0)]);
    controller.creationTemplate = PolygonElement(
      height: 0,
      vertices: vertices,
      width: 0,
      x: 0,
      y: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    // Tap to add a vertex, then cancel.
    await tester.tapAt(topLeft + const Offset(100, 100));
    await tester.pump();
    expect(controller.pendingVertices.length, 1);

    // Cancel via a gesture cancel.
    final gesture = await tester.startGesture(topLeft + const Offset(120, 120));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    // Cursor position should be cleared.
    expect(controller.cursorPosition, isNull);
  });

  testWidgets('closing a polygon with zero area does not commit', (tester) async {
    final controller = DrawController();
    final vertices = Float64x2List.fromList([Float64x2(0, 0), Float64x2(0, 0), Float64x2(0, 0)]);
    controller.creationTemplate = PolygonElement(
      height: 0,
      vertices: vertices,
      width: 0,
      x: 0,
      y: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    // Tap 3 collinear points (zero-area polygon).
    await tester.tapAt(topLeft + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(topLeft + const Offset(100, 100));
    await tester.pump();
    await tester.tapAt(topLeft + const Offset(100, 100));
    await tester.pump();

    // Try to close at the same first vertex — should result in zero-area box.
    await tester.tapAt(topLeft + const Offset(100, 100));
    await tester.pump();

    // Zero-area polygon must NOT be committed.
    expect(controller.elements, isEmpty);
  });

  testWidgets('updates close tolerance when minShapeSize changes in didUpdateWidget', (
    tester,
  ) async {
    final controller = DrawController();
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawEditor(
            file,
            controller: controller,
            key: key,
            minShapeSize: 15,
            size: const Size(800, 600),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawEditor(
            file,
            controller: controller,
            key: key,
            minShapeSize: 25,
            size: const Size(800, 600),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((customPaint) => customPaint.foregroundPainter)
        .whereType<DrawPainter>()
        .firstOrNull;

    expect(
      painter?.tolerance,
      closeTo(50.0, 0.001),
      reason: 'tolerance must update to minShapeSize * 2 when minShapeSize changes',
    );
  });
});
