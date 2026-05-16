import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group('Drag to Create Flow', () {
  final file = File('test.jpg');

  testWidgets('Drag to create a rect shape', (tester) async {
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
    expect(controller.elements.isEmpty, isTrue);

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);
    final gesture = await tester.startGesture(topLeft + const Offset(100, 100)); // Start drag.
    await tester.pump();

    expect(controller.elements.singleOrNull?.height, isZero);
    expect(controller.elements.singleOrNull?.width, isZero);

    await gesture.moveBy(const Offset(50, 50)); // Move by 50, 50.
    await tester.pump();

    expect(controller.elements.singleOrNull?.width, closeTo(50.0, 0.1));
    expect(controller.elements.singleOrNull?.height, closeTo(50.0, 0.1));

    await gesture.up(); // End drag.
    await tester.pump();

    // Ensure command was committed and shape remains.
    expect(controller.elements.singleOrNull?.width, closeTo(50.0, 0.1));
    expect(controller.elements.singleOrNull?.height, closeTo(50.0, 0.1));

    expect(controller.creationTemplate, isNull); // Mode resets to selection.
    controller.undo(); // Can undo.
    await tester.pump();
    expect(controller.elements, isEmpty);

    controller.redo(); // Can redo.
    await tester.pump();
    expect(controller.elements.length, 1);
  });

  testWidgets('Drag too small shape drops it', (tester) async {
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
    final gesture = await tester.startGesture(topLeft + const Offset(100, 100)); // Start drag.
    await tester.pump();

    await gesture.moveBy(const Offset(4, 4)); // Move by only 4 pixels (below threshold of 10).
    await tester.pump();

    await gesture.up(); // End drag.
    await tester.pump();

    expect(controller.elements.isEmpty, isTrue); // Should be dropped.
    expect(controller.creationTemplate, isNull);
  });

  testWidgets('Pointer cancel aborts creation', (tester) async {
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
    final gesture = await tester.startGesture(topLeft + const Offset(100, 100)); // Start drag.
    await tester.pump();

    await gesture.cancel(); // Cancel drag.
    await tester.pump();

    expect(controller.elements.isEmpty, isTrue); // Should be removed.
    expect(controller.creationTemplate, isNull);
  });
});
