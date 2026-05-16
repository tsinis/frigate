import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatebird/frigatebird.dart';

import 'package:frigatedraw/src/ui/buttons/draw_delete_button.dart';
import 'package:frigatedraw/src/ui/buttons/draw_redo_button.dart';
import 'package:frigatedraw/src/ui/buttons/draw_undo_button.dart';
import 'package:frigatedraw/src/ui/draw_controller.dart';
import 'package:frigatedraw/src/ui/draw_editor.dart';

void main() => group('Delete Element Flow', () {
  final file = File('test.jpg');

  testWidgets('Add element -> Select -> Delete -> Undo -> Redo', (tester) async {
    final controller = DrawController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              DrawUndoButton(controller),
              DrawRedoButton(controller),
              DrawDeleteButton(controller),
            ],
          ),
          body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // 1. Add an element.
    controller.addElement(const RectElement(height: 100, width: 100, x: 50, y: 50));
    await tester.pump();
    expect(controller.elements.length, 1);
    expect(controller.selectedIndex, isZero);

    // 2. Verify delete button is enabled
    // We search for IconButton inside DrawDeleteButton because the implementation
    // returns a new IconButton in its build method.
    final deleteButtonFinder = find.descendant(
      matching: find.byType(IconButton),
      of: find.byType(DrawDeleteButton),
    );
    expect(tester.widget<IconButton>(deleteButtonFinder).onPressed, isNotNull);

    await tester.tap(deleteButtonFinder); // 3. Delete the element.
    await tester.pump();
    expect(controller.elements, isEmpty);
    expect(controller.selectedIndex, isNull);
    expect(tester.widget<IconButton>(deleteButtonFinder).onPressed, isNull, reason: 'Disabled');

    final undoButtonFinder = find.descendant(
      matching: find.byType(IconButton),
      of: find.byType(DrawUndoButton), // 4. Undo delete.
    );
    await tester.tap(undoButtonFinder);
    await tester.pump();
    expect(controller.elements.length, 1);
    expect(controller.selectedIndex, isZero);
    expect(tester.widget<IconButton>(deleteButtonFinder).onPressed, isNotNull);

    final redoFinder = find.descendant(
      matching: find.byType(IconButton),
      of: find.byType(DrawRedoButton), // 5. Redo delete.
    );
    await tester.tap(redoFinder);
    await tester.pump();
    expect(controller.elements, isEmpty);
    expect(controller.selectedIndex, isNull);
  });

  testWidgets('Tapping empty space clears selection and disables delete', (tester) async {
    final controller = DrawController()
      ..addElement(const RectElement(height: 100, width: 100, x: 50, y: 50));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [DrawDeleteButton(controller)]),
          body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(controller.selectedIndex, isZero);
    final ivFinder = find.byType(InteractiveViewer); // Tap away from element.
    final topLeft = tester.getTopLeft(ivFinder);
    await tester.tapAt(topLeft + const Offset(300, 300));
    await tester.pump();

    expect(controller.selectedIndex, isNull);
    final deleteButtonFinder = find.descendant(
      matching: find.byType(IconButton),
      of: find.byType(DrawDeleteButton),
    );
    expect(tester.widget<IconButton>(deleteButtonFinder).onPressed, isNull);
  });
});
