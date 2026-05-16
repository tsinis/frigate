// ignore_for_file: avoid-ignoring-return-values

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group(DrawEditor, () {
  final file = File('test.jpg');

  setUp(
    () => FfiImageFile.setInfoBuilder((_) async => const ImageInformation(height: 600, width: 800)),
  );

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
    expect(props, contains('controller'));
    expect(props, contains('image'));
    expect(props, contains('size.height'));
    expect(props, contains('size.width'));
  });
});
