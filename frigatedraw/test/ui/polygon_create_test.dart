// ignore_for_file: prefer-moving-to-variable

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() {
  testWidgets('Create a polygon with 3 taps', (tester) async {
    final file = File('test.jpg');
    final controller = DrawController()
      ..creationTemplate = PolygonElement(
        height: 0,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(0, 0), Float64x2(0, 0)]),
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

    expect(controller.elements.isEmpty, isTrue);

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    await tester.tapAt(topLeft + const Offset(100, 100)); // Tap 1.
    await tester.pump();

    await tester.tapAt(topLeft + const Offset(150, 100)); // Tap 2.
    await tester.pump();

    await tester.tapAt(topLeft + const Offset(125, 150)); // Tap 3.
    await tester.pump();

    await tester.tapAt(topLeft + const Offset(100, 100)); // Tap 1 again (close).
    await tester.pump();

    expect(controller.elements.singleOrNull, isA<PolygonElement>());
  });

  testWidgets('Polygon creation undo behavior', (tester) async {
    final file = File('test.jpg');
    final controller = DrawController()
      ..creationTemplate = PolygonElement(
        height: 0,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(0, 0), Float64x2(0, 0)]),
        width: 0,
        x: 0,
        y: 0,
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DrawUndoButton(controller),
              Expanded(
                child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
              ),
            ],
          ),
        ),
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
      ),
    );
    await tester.pumpAndSettle();

    // Initially, there are no commands and no pending vertices, so undo should be disabled.
    final undoFinder = find.byType(DrawUndoButton);
    final iconButtonFinder = find.descendant(matching: find.byType(IconButton), of: undoFinder);

    // ignore: avoid-local-functions, just a test helper.
    IconButton undoIconButton() => tester.widget<IconButton>(iconButtonFinder);

    expect(undoIconButton().onPressed, isNull);
    expect(controller.canUndo, isFalse);

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    // Add first point.
    await tester.tapAt(topLeft + const Offset(100, 100));
    await tester.pump();

    // Now undo should be enabled because we have a pending vertex.
    expect(controller.canUndo, isTrue);
    expect(undoIconButton().onPressed, isNotNull);
    expect(controller.pendingVertices.length, 1);

    // Add second point.
    await tester.tapAt(topLeft + const Offset(150, 100));
    await tester.pump();
    expect(controller.pendingVertices.length, 2);

    // Tap Undo button.
    await tester.tap(undoFinder);
    await tester.pump();

    expect(controller.canUndo, isTrue);
    expect(undoIconButton().onPressed, isNotNull);
    expect(
      controller.pendingVertices.singleOrNull,
      isNotNull,
      reason: 'Verify second point is removed, but first point is still there.',
    );

    await tester.tap(undoFinder); // Tap Undo again to remove first point.
    await tester.pump();

    expect(controller.canUndo, isFalse);
    expect(undoIconButton().onPressed, isNull);
    expect(
      controller.pendingVertices.isEmpty,
      isTrue,
      reason: 'Verify all pending vertices are gone and undo is disabled again.',
    );
  });

  testWidgets('Polygon gesture timing: Down shows cursor preview, Up commits vertex', (
    tester,
  ) async {
    final file = File('test.jpg');
    final controller = DrawController()
      ..creationTemplate = PolygonElement(
        height: 0,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(0, 0), Float64x2(0, 0)]),
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

    final gesture = await tester.startGesture(topLeft + const Offset(100, 100));
    await tester.pump();

    expect(controller.pendingVertices.isEmpty, isTrue);
    expect(controller.cursorPosition, const Offset(100, 100));

    await gesture.up();
    await tester.pump();

    expect(controller.pendingVertices.length, 1);
    expect(controller.cursorPosition, isNull);
  });

  testWidgets('Polygon gesture drag/move: updates cursor, release commits coordinate', (
    tester,
  ) async {
    final file = File('test.jpg');
    final controller = DrawController()
      ..creationTemplate = PolygonElement(
        height: 0,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(0, 0), Float64x2(0, 0)]),
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

    final gesture = await tester.startGesture(topLeft + const Offset(100, 100));
    await tester.pump();

    await gesture.moveTo(topLeft + const Offset(120, 130));
    await tester.pump();

    expect(controller.cursorPosition, const Offset(120, 130));
    expect(controller.pendingVertices.isEmpty, isTrue);

    await gesture.up();
    await tester.pump();

    expect(controller.pendingVertices.length, 1);
    expect(controller.pendingVertices.firstOrNull?.x, 120);
    expect(controller.pendingVertices.firstOrNull?.y, 130);
    expect(controller.cursorPosition, isNull);
  });

  testWidgets('Polygon gesture cancel: resets cursor position on cancel', (tester) async {
    final file = File('test.jpg');
    final controller = DrawController()
      ..creationTemplate = PolygonElement(
        height: 0,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(0, 0), Float64x2(0, 0)]),
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

    final gesture = await tester.startGesture(topLeft + const Offset(100, 100));
    await tester.pump();

    expect(controller.cursorPosition, const Offset(100, 100));

    await gesture.cancel();
    await tester.pump();

    expect(controller.pendingVertices.isEmpty, isTrue);
    expect(controller.cursorPosition, isNull);
  });
}
