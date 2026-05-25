import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group(DrawBlurSlider, () {
  testWidgets('acts as normal stateless slider when no element is selected', (tester) async {
    final controller = DrawController();
    const value = 50.0;
    double? changedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawBlurSlider(
            controller,
            onChanged: (val) {
              changedValue = val;
            },
            value: value,
          ),
        ),
      ),
    );

    final sliderFinder = find.byType(Slider);
    final slider = tester.widget<Slider>(sliderFinder);
    expect(slider.value, 50.0);

    // Drag slider.
    await tester.drag(sliderFinder, const Offset(100, 0));
    await tester.pumpAndSettle();

    expect(changedValue, isNotNull);
    expect(changedValue, isNot(50.0));
  });

  testWidgets('binds to selected element and commits command only on change end', (tester) async {
    final controller = DrawController();
    const rect = RectElement(blur: 10, height: 100, width: 100, x: 0, y: 0);
    controller
      ..addElement(rect)
      ..selectedIndex = 0;

    const value = 50.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DrawBlurSlider(controller, value: value)),
      ),
    );

    final sliderFinder = find.byType(Slider);
    final slider = tester.widget<Slider>(sliderFinder);
    expect(slider.value, 10.0);

    // Verify command stack is empty initially.
    expect(controller.commandStack.canUndo, isFalse);

    // Start slider drag.
    final center = tester.getCenter(sliderFinder);
    final gesture = await tester.startGesture(center);
    await tester.pump();

    // While dragging, it updates element in real-time but no command is committed.
    final selectedElement = controller.selectedElement;
    if (selectedElement != null) expect(selectedElement.blur, isNot(10));

    // Release the slider.
    await gesture.up();
    await tester.pumpAndSettle();

    // Command is now committed.
    expect(controller.commandStack.canUndo, isTrue);

    // Revert it.
    controller.undo();
    final revertedElement = controller.selectedElement;
    if (revertedElement != null) expect(revertedElement.blur, 10);
  });
});
