// Test reads better with inline lambdas + dotted property access; trailing-comma decisions
// are case-by-case for readability inside `expect` blocks.
// ignore_for_file: prefer-extracting-callbacks, prefer-extracting-function-callbacks
// ignore_for_file: prefer-class-destructuring, unnecessary-trailing-comma

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

    test('removeElementAt removes element and notifies', () {
      controller
        ..addElement(rect)
        ..addListener(_handleNotification)
        ..removeElementAt(0);
      expect(controller.elements, isEmpty);
      expect(_wasNotified, isTrue);
    });

    test('removeElementAt ignores out of bounds index', () {
      controller
        ..addListener(_handleNotification)
        ..removeElementAt(0);
      expect(_wasNotified, isFalse);
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
  });
}
