import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group(DrawBlurToggleButton, () {
  testWidgets('renders Icons.blur_circular and is disabled when no element is selected', (
    tester,
  ) async {
    final controller = DrawController();

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DrawBlurToggleButton(controller))));

    expect(find.byIcon(Icons.blur_circular), findsOneWidget);
    expect(find.byIcon(Icons.blur_on), findsNothing);
    expect(find.byIcon(Icons.blur_off), findsNothing);

    // Verify it is disabled because callback is null.
    final btn = tester.widget<IconButton>(find.byType(IconButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('renders Icons.blur_off and is disabled when selected element has 0 blur', (
    tester,
  ) async {
    final controller = DrawController();
    const rect = RectElement(height: 100, width: 100, x: 0, y: 0);
    controller
      ..addElement(rect)
      ..selectedIndex = 0;

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DrawBlurToggleButton(controller))));

    expect(find.byIcon(Icons.blur_off), findsOneWidget);
    expect(find.byIcon(Icons.blur_on), findsNothing);

    final btn = tester.widget<IconButton>(find.byType(IconButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('renders Icons.blur_on and sets blur to 0 when tapped on active shape', (
    tester,
  ) async {
    final controller = DrawController();
    const rect = RectElement(blur: 50, height: 100, width: 100, x: 0, y: 0);
    controller
      ..addElement(rect)
      ..selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DrawBlurToggleButton(controller, minColor: FfiColor.black)),
      ),
    );

    expect(find.byIcon(Icons.blur_on), findsOneWidget);

    final btnFinder = find.byType(IconButton);
    final btn = tester.widget<IconButton>(btnFinder);
    expect(btn.onPressed, isNotNull);

    // Tap to set to 0.
    await tester.tap(btnFinder);
    await tester.pumpAndSettle();

    final selected = controller.selectedElement;
    if (selected != null) {
      expect(selected.blur, 0);
      expect(selected.fillColor.argb, 0xFF000000);
    }
    expect(controller.commandStack.canUndo, isTrue);

    // After setting to 0, button becomes disabled and shows blur_off.
    expect(find.byIcon(Icons.blur_off), findsOneWidget);
    final btnAfter = tester.widget<IconButton>(btnFinder);
    expect(btnAfter.onPressed, isNull);

    // Undo restores blur to 50.
    controller.undo();
    final undone = controller.selectedElement;
    if (undone != null) {
      expect(undone.blur, 50);
    }
  });
});
