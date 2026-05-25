import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group(DrawExportButton, () {
  testWidgets('is disabled when controller elements are empty, enabled when not', (tester) async {
    final controller = DrawController();
    bool isPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DrawExportButton(controller, onExport: () => isPressed = true)),
      ),
    );

    final buttonFinder = find.byType(IconButton);
    final iconButton = tester.widget<IconButton>(buttonFinder);

    expect(iconButton.onPressed, isNull);

    controller.addElement(const RectElement(fillColor: .black, height: 10, width: 10, x: 0, y: 0));
    await tester.pump();

    final updatedIconButton = tester.widget<IconButton>(buttonFinder);
    expect(updatedIconButton.onPressed, isNotNull);

    await tester.tap(buttonFinder);
    expect(isPressed, isTrue);
  });
});
