// ignore_for_file: avoid-ignoring-return-values

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group(DrawEditor, () {
  final file = File('test.jpg');

  setUp(
    () => FfiImageFile.setInfoBuilder((_) async => const ImageInformation(height: 600, width: 800)),
  );

  testWidgets('renders image and CustomPaint', (tester) async {
    final controller = DrawController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawEditor(file, controller: controller, size: const Size(800, 600)),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(FfiImageFile), findsOneWidget);
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
  });

  testWidgets('selects element on tap on outline', (tester) async {
    final controller = DrawController();
    const rect = RectElement(height: 100, width: 100, x: 50, y: 50);
    controller.addElement(rect);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    // Tap on the top-left corner (50, 50).
    await tester.tapAt(topLeft + const Offset(50, 50));
    await tester.pump();

    expect(controller.selectedIndex, 0);
  });

  testWidgets('moves element on drag', (tester) async {
    final controller = DrawController();
    const rect = RectElement(height: 100, width: 100, x: 50, y: 50);
    controller
      ..addElement(rect)
      ..selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    // Start drag from top-left corner (50, 50).
    final gesture = await tester.startGesture(topLeft + const Offset(50, 50));
    await tester.pump();

    // Move by 50, 50.
    await gesture.moveBy(const Offset(50, 50));
    await tester.pump();

    expect(controller.elements.firstOrNull?.x, closeTo(100.0, 0.1));
    expect(controller.elements.firstOrNull?.y, closeTo(100.0, 0.1));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('resizes element via handles', (tester) async {
    final controller = DrawController();
    const rect = RectElement(height: 100, width: 100, x: 100, y: 100);
    controller
      ..addElement(rect)
      ..selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 800,
            child: DrawEditor(file, controller: controller, size: const Size(800, 600)),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final ivFinder = find.byType(InteractiveViewer);
    final topLeft = tester.getTopLeft(ivFinder);

    TestGesture gesture = await tester.startGesture(topLeft + const Offset(100, 100));
    await tester.pump();
    await gesture.moveBy(const Offset(-20, -20));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.elements.firstOrNull?.x, closeTo(80.0, 0.1));
    expect(controller.elements.firstOrNull?.width, closeTo(120.0, 0.1));

    // 2. Bottom-right handle (200, 200).
    gesture = await tester.startGesture(topLeft + const Offset(200, 200));
    await tester.pump();
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.elements.firstOrNull?.width, closeTo(130.0, 0.1));
    expect(controller.elements.firstOrNull?.height, closeTo(130.0, 0.1));
  });

  test('debugFillProperties coverage', () {
    final draw = DrawController();
    final builder = DiagnosticPropertiesBuilder();
    DrawEditor(file, controller: draw, size: const .new(100, 200)).debugFillProperties(builder);
    final props = builder.properties.map((i) => i.name).toList();
    expect(props, contains('controller'));
    expect(props, contains('image'));
    expect(props, contains('size.height'));
    expect(props, contains('size.width'));
  });
});
