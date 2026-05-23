// Test reads better with inline lambdas + dotted property access; trailing-comma decisions
// are case-by-case for readability inside `expect` blocks.
// ignore_for_file: prefer-extracting-callbacks, prefer-extracting-function-callbacks
// ignore_for_file: prefer-class-destructuring, unnecessary-trailing-comma

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

bool _wasNotified = false;

void _handleNotification() {
  _wasNotified = true;
}

void main() {
  group('DrawController', () {
    DrawController controller = DrawController();
    const rect = RectElement(height: 50, width: 100, x: 10, y: 20);

    setUp(() {
      controller = DrawController();
      _wasNotified = false;
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts with empty elements', () {
      expect(controller.elements, isEmpty);
      expect(controller.selectedIndex, isNull);
      expect(controller.selectedElement, isNull);
    });

    test('addElement adds element and selects it', () {
      controller.addElement(rect);

      expect(controller.elements, hasLength(1));
      expect(controller.selectedIndex, 0);
      expect(controller.selectedElement, rect);
    });

    test('selectedIndex notifies listeners', () {
      controller
        ..addElement(rect)
        ..addListener(_handleNotification)
        ..selectedIndex = null;

      expect(_wasNotified, isTrue);
    });

    test('selectedIndex skips notification on same value', () {
      controller
        ..addListener(_handleNotification)
        ..selectedIndex = null;

      expect(_wasNotified, isFalse);
    });

    test('commitCommand + undo restores previous state', () {
      const moved = RectElement(height: 50, width: 100, x: 30, y: 40);
      controller
        ..addElement(rect)
        ..commitCommand(0, after: moved, before: rect)
        ..undo();

      expect(controller.selectedElement, rect);
    });

    test('commitCommand + undo + redo re-applies', () {
      const moved = RectElement(height: 50, width: 100, x: 30, y: 40);
      controller
        ..addElement(rect)
        ..commitCommand(0, after: moved, before: rect)
        ..undo()
        ..redo();

      expect(controller.selectedElement, moved);
    });

    test('undo with empty stack does not notify', () {
      controller
        ..addListener(_handleNotification)
        ..undo();
      expect(_wasNotified, isFalse, reason: 'no state changed, listeners should stay quiet');
    });

    test('redo with empty stack does not notify', () {
      controller
        ..addListener(_handleNotification)
        ..redo();
      expect(_wasNotified, isFalse, reason: 'no state changed, listeners should stay quiet');
    });

    test('commitCommand skips no-op when before and after are the same instance', () {
      controller
        ..addElement(rect)
        ..addListener(_handleNotification)
        ..commitCommand(0, after: rect, before: rect);
      expect(
        controller.commandStack.canUndo,
        isFalse,
        reason: 'tap-without-drag must not pollute the undo stack',
      );
      expect(_wasNotified, isFalse, reason: 'no state changed, listeners should stay quiet');
    });

    test('commitCommand notifies listeners so undo/redo UI updates', () {
      const moved = RectElement(height: 50, width: 100, x: 30, y: 40);
      controller.addElement(rect);

      _wasNotified = false;
      controller
        ..addListener(_handleNotification)
        ..commitCommand(0, after: moved, before: rect);

      expect(
        _wasNotified,
        isTrue,
        reason: 'commitCommand pushed to stack and must notify listeners to rebuild UI',
      );
    });

    test('removeElementAt removes element and notifies', () {
      controller
        ..addElement(rect)
        ..addListener(_handleNotification)
        ..dropElementAt(0);
      expect(controller.elements, isEmpty);
      expect(_wasNotified, isTrue);
    });

    test('dropElementAt ignores out of bounds index', () {
      controller
        ..addListener(_handleNotification)
        ..dropElementAt(0);
      expect(_wasNotified, isFalse);
    });

    test('dropElementAt clears selection if target is selected', () {
      controller
        ..addElement(rect)
        ..dropElementAt(0);
      expect(controller.selectedIndex, isNull);
    });

    test('dropElementAt decrements selection if target is before selected', () {
      controller.addElement(rect);
      expect(controller.elements, hasLength(1));
      controller.addElement(rect);
      expect(controller.elements, hasLength(2));
      controller.selectedIndex = 1;
      expect(controller.elements.length, 2);
      controller.dropElementAt(0);
      expect(controller.selectedIndex, isZero);
    });

    test('dropElementAt leaves selection alone if target is after selected', () {
      controller.addElement(rect);
      expect(controller.elements, hasLength(1));
      controller.addElement(rect);
      expect(controller.elements, hasLength(2));
      controller.selectedIndex = 0;
      expect(controller.elements.length, 2);
      controller.dropElementAt(1);
      expect(controller.selectedIndex, isZero);
    });

    test('commitAdd adds element and is undoable', () {
      controller.commitAdd(rect);
      expect(controller.elements.length, 1);
      expect(controller.selectedIndex, isZero);

      controller.undo();
      expect(controller.elements, isEmpty);
      expect(controller.selectedIndex, isNull);

      controller.redo();
      expect(controller.elements, hasLength(1));
      expect(controller.selectedIndex, 0);
    });

    test('canUndo and undo with pending polygon vertices', () {
      expect(controller.canUndo, isFalse, reason: 'initially false');

      controller.creationTemplate = PolygonElement(
        height: 0,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(0, 0), Float64x2(0, 0)]),
        width: 0,
        x: 0,
        y: 0,
      );
      expect(controller.canUndo, isFalse, reason: 'still false with 0 pending vertices');

      controller.addPendingVertex(const Offset(10, 20));
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.pendingVertices, isEmpty);
      expect(controller.canUndo, isFalse, reason: 'false after undoing last pending vertex');
    });

    test('updateCursorPosition notifies listeners', () {
      controller
        ..addListener(_handleNotification)
        ..updateCursorPosition(const Offset(10, 20));
      expect(controller.cursorPosition, const Offset(10, 20));
      expect(_wasNotified, isTrue);
    });

    test('resetPolygonCreation clears pending vertices and cursor', () {
      controller.creationTemplate = PolygonElement(
        height: 0,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(0, 0), Float64x2(0, 0)]),
        width: 0,
        x: 0,
        y: 0,
      );
      // ignore: cascade_invocations, expects in between prevent a single cascade.
      controller
        ..addPendingVertex(const Offset(1, 2))
        ..updateCursorPosition(const Offset(3, 4));
      expect(controller.pendingVertices, hasLength(1));
      expect(controller.cursorPosition, isNotNull);

      controller
        ..addListener(_handleNotification)
        ..resetPolygonCreation();

      expect(controller.pendingVertices, isEmpty);
      expect(controller.cursorPosition, isNull);
      expect(_wasNotified, isTrue);
    });

    test('redo when canRedo is false does nothing', () {
      controller
        ..addListener(_handleNotification)
        ..redo(); // Stack is empty.
      expect(_wasNotified, isFalse);
    });

    test('creationTemplate setter clears selection and resets polygon state', () {
      controller
        ..addElement(rect)
        ..selectedIndex = 0;
      expect(controller.selectedIndex, isNotNull);

      controller.creationTemplate = const RectElement(height: 10, width: 10, x: 0, y: 0);

      expect(controller.selectedIndex, isNull);
    });

    test('creationTemplate setter skips notification when value is unchanged', () {
      const template = RectElement(height: 10, width: 10, x: 0, y: 0);
      controller.creationTemplate = template;
      controller.addListener(_handleNotification); // ignore: cascade_invocations, just a test.
      // Assign the same instance again: the identity guard must suppress notification.
      controller.creationTemplate = template; // ignore: cascade_invocations, just a test.

      expect(_wasNotified, isFalse, reason: 'Same value must not notify listeners.');
    });
  });
}
