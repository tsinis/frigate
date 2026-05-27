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

  testWidgets('selects element on tap on outline', (tester) async {
    final controller = DrawController();
    const rect = RectElement(height: 100, width: 100, x: 50, y: 50);
    controller
      ..addElement(rect)
      ..selectedIndex = null; // Ensure not already selected.

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

      final interactiveViewerFinder = find.byType(InteractiveViewer);
      final viewerTopLeft = tester.getTopLeft(interactiveViewerFinder);
      final interactViewer = tester.widget<InteractiveViewer>(interactiveViewerFinder);
      final transformationController = interactViewer.transformationController;

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
});
