// ignore_for_file: prefer-extracting-callbacks
// ignore_for_file: prefer-extracting-function-callbacks
// ignore_for_file: prefer-class-destructuring
// ignore_for_file: unnecessary-trailing-comma

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
  });
}
