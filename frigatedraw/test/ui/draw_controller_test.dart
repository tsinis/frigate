// Test reads better with inline lambdas + dotted property access; trailing-comma decisions
// are case-by-case for readability inside `expect` blocks.

// ignore_for_file: prefer-extracting-function-callbacks, prefer-class-destructuring

import 'dart:typed_data';
import 'dart:ui' show Size;

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

      expect(controller.elements.singleOrNull, rect);
      expect(controller.selectedIndex, isZero);
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

    test(
      'elements and pendingVertices getters cache UnmodifiableListView instances between notifications',
      () {
        final elementsFirst = controller.elements;
        // ignore: avoid-duplicate-initializers, just for the test.
        final elementsOther = controller.elements;
        expect(
          identical(elementsFirst, elementsOther),
          isTrue,
          reason: 'Consecutive elements reads should be identical.',
        );

        final pendingFirst = controller.pendingVertices;
        // ignore: avoid-duplicate-initializers, just for the test.
        final pendingLast = controller.pendingVertices;
        expect(
          identical(pendingFirst, pendingLast),
          isTrue,
          reason: 'Consecutive pendingVertices reads should be identical.',
        );

        // Mutate list -> triggers notifyListeners() -> cache should clear.
        controller.addElement(rect);

        // ignore: avoid-duplicate-initializers, just for the test.
        final elementsThird = controller.elements;
        expect(
          identical(elementsFirst, elementsThird),
          isFalse,
          reason: 'Cache should be invalidated on notification.',
        );

        // ignore: avoid-duplicate-initializers, just for the test.
        final lastElements = controller.elements;
        expect(
          identical(elementsThird, lastElements),
          isTrue,
          reason: 'Elements reads after mutation should be identical.',
        );
      },
    );

    test('activeTool returns correct nullable DrawTool based on selection and template', () {
      expect(controller.activeTool, isNull, reason: 'initially null');

      controller.creationTemplate = const RectElement(height: 10, width: 10, x: 0, y: 0);
      expect(controller.activeTool, DrawTool.rectangle, reason: 'matches creation template tool');

      controller.creationTemplate = null;
      expect(controller.activeTool, isNull, reason: 'null when template and selection are null');

      controller.addElement(rect);
      expect(controller.activeTool, DrawTool.select, reason: 'select when element is selected');

      controller.selectedIndex = null;
      expect(controller.activeTool, isNull, reason: 'null when deselected');
    });

    test('selectTool maps draw tools to default creation templates', () {
      controller.selectTool(.rectangle);
      expect(controller.creationTemplate, RectElement.zero);

      controller.selectTool(.oval);
      expect(controller.creationTemplate, OvalElement.zero);

      controller.selectTool(.polygon);
      final template = controller.creationTemplate;
      expect(template, isA<PolygonElement>());
      // ignore: avoid-type-casts, avoid-non-null-assertion, is already checked by isA.
      expect((template! as PolygonElement).vertices, hasLength(3));

      controller.selectTool(.select);
      expect(controller.creationTemplate, isNull); // ignore: use-existing-variable, it's a getter.
    });

    test('selectTool uses provided template override', () {
      const custom = RectElement(blur: 10, height: 12, width: 34, x: 5, y: 6);
      controller.selectTool(.rectangle, template: custom);

      expect(controller.creationTemplate, custom);
    });

    group('background mode', () {
      test('starts with no treatment and not in background mode', () {
        expect(controller.backgroundTreatment, isNull);
        expect(controller.isBackgroundMode, isFalse);
      });

      test('enterBackgroundMode creates a full-image cover treatment and arms the tool', () {
        controller
          ..addListener(_handleNotification)
          ..enterBackgroundMode(const Size(640, 480));

        expect(controller.isBackgroundMode, isTrue);
        expect(controller.activeTool, DrawTool.background);
        expect(
          controller.backgroundTreatment,
          const BackgroundElement.cover(height: 480, width: 640),
        );
        expect(_wasNotified, isTrue);
      });

      test('selectTool(.background) arms the mode without sizing the treatment', () {
        controller.selectTool(.background);

        expect(controller.isBackgroundMode, isTrue);
        expect(controller.activeTool, DrawTool.background);
        expect(controller.backgroundTreatment, isNull);
      });

      test('entering background mode clears any shape selection', () {
        controller
          ..addElement(rect)
          ..enterBackgroundMode(const Size(100, 100));

        expect(controller.selectedIndex, isNull);
      });

      test('selecting a shape tool exits background mode but keeps the treatment', () {
        controller
          ..enterBackgroundMode(const Size(100, 100))
          ..selectTool(.rectangle);

        expect(controller.isBackgroundMode, isFalse);
        expect(
          controller.backgroundTreatment,
          const BackgroundElement.cover(height: 100, width: 100),
          reason: 'treatment persists after tool switch',
        );
      });

      test('exitBackgroundMode disarms but keeps the treatment', () {
        controller
          ..enterBackgroundMode(const Size(100, 100))
          ..exitBackgroundMode();

        expect(controller.isBackgroundMode, isFalse);
        expect(controller.backgroundTreatment, isNotNull);
      });

      test('updateBackgroundTreatment replaces the slot and notifies', () {
        const next = BackgroundElement(blur: 40, height: 60, width: 60, x: 10, y: 10);
        controller
          ..enterBackgroundMode(const Size(100, 100))
          ..addListener(_handleNotification)
          ..updateBackgroundTreatment(next);

        expect(controller.backgroundTreatment, next);
        expect(_wasNotified, isTrue);
      });

      test('commitBackgroundTreatment supports undo and redo', () {
        controller.enterBackgroundMode(const Size(100, 100));
        const before = BackgroundElement.cover(height: 100, width: 100);
        final after = before.copyWith(blur: 50);

        controller.commitBackgroundTreatment(after: after, before: before);
        expect(controller.backgroundTreatment, after);
        expect(controller.canUndo, isTrue);

        controller.undo();
        expect(controller.backgroundTreatment, before);

        controller.redo();
        // ignore: avoid-duplicate-test-assertions, intentional: verifies redo re-applies state.
        expect(controller.backgroundTreatment, after);
      });

      test('commitBackgroundTreatment is a no-op when before == after', () {
        controller.enterBackgroundMode(const Size(100, 100));
        const treatment = BackgroundElement.cover(height: 100, width: 100);

        controller.commitBackgroundTreatment(after: treatment, before: treatment);

        expect(controller.canUndo, isFalse);
      });

      test('clearing the treatment via the setter notifies', () {
        controller
          ..enterBackgroundMode(const Size(100, 100))
          ..addListener(_handleNotification)
          ..backgroundTreatment = null;

        expect(controller.backgroundTreatment, isNull);
        expect(_wasNotified, isTrue);
      });
    });
  });
}
