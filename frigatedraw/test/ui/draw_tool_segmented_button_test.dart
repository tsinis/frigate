import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group(DrawToolSegmentedButton, () {
  test('debugFillProperties includes constructor-backed diagnostics', () {
    final controller = DrawController();
    final widget = DrawToolSegmentedButton(
      controller,
      direction: Axis.vertical,
      expandedInsets: const EdgeInsets.all(8),
      isEmptySelectionAllowed: false,
      onSelectionChanged: (_) {}, // ignore: no-empty-block, just a test.
      selectedIcon: const Icon(Icons.check),
      shouldShowSelectedIcon: false,
      style: const ButtonStyle(),
      tools: const {.select: Icons.mouse},
    );

    final properties = DiagnosticPropertiesBuilder();
    widget.debugFillProperties(properties);
    final names = properties.properties.map((e) => e.name).toSet();

    expect(
      names,
      containsAll(<String>{
        '_controller',
        '_direction',
        '_isEmptySelectionAllowed',
        '_expandedInsets',
        '_selectedIcon',
        '_shouldShowSelectedIcon',
        '_style',
        '_tools',
        '_onSelectionChanged',
      }),
    );
  });

  testWidgets('renders segments for each tool as icon-only and triggers onSelectionChanged', (
    tester,
  ) async {
    final controller = DrawController();
    DrawTool? selected = .select;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawToolSegmentedButton(
            controller,
            onSelectionChanged: (tool) {
              selected = tool;
            },
          ),
        ),
      ),
    );

    final segmentedFinder = find.byType(SegmentedButton<DrawTool>);
    expect(segmentedFinder, findsOneWidget);

    final segments = tester.widget<SegmentedButton<DrawTool>>(segmentedFinder).segments;
    expect(segments.length, 6);

    expect(find.descendant(matching: find.byType(Text), of: segmentedFinder), findsNothing);

    final rectSegmentFinder = find.byIcon(Icons.crop_square_outlined);
    expect(rectSegmentFinder, findsOneWidget);

    await tester.tap(rectSegmentFinder);
    await tester.pumpAndSettle();

    expect(selected, DrawTool.rectangle);
  });

  testWidgets('supports custom tools list and custom icon mapping', (tester) async {
    final controller = DrawController();
    DrawTool? selected = .select;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawToolSegmentedButton(
            controller,
            onSelectionChanged: (tool) => selected = tool,
            selectedIcon: const Icon(Icons.check),
            tools: const {.select: Icons.mouse, .rectangle: Icons.check},
          ),
        ),
      ),
    );

    final segmentedFinder = find.byType(SegmentedButton<DrawTool>);
    final segments = tester.widget<SegmentedButton<DrawTool>>(segmentedFinder).segments;
    expect(segments.length, 2);

    expect(find.byIcon(Icons.mouse), findsOneWidget);
    expect(find.byIcon(Icons.check), findsAtLeast(1));
    expect(selected, DrawTool.select);
  });

  testWidgets('renders with no selection when activeTool is null', (tester) async {
    final controller = DrawController();
    // Initially, no elements and no creationTemplate, so activeTool is null.
    expect(controller.activeTool, isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawToolSegmentedButton(
            controller,
            onSelectionChanged: (tool) {
              final _ = tool;
            },
          ),
        ),
      ),
    );

    final segmentedFinder = find.byType(SegmentedButton<DrawTool>);
    final segmentedButton = tester.widget<SegmentedButton<DrawTool>>(segmentedFinder);
    expect(segmentedButton.selected, isEmpty);
  });

  testWidgets('updates controller even when onSelectionChanged is not provided', (tester) async {
    final controller = DrawController();

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DrawToolSegmentedButton(controller))));

    await tester.tap(find.byIcon(Icons.crop_square_outlined));
    await tester.pumpAndSettle();

    expect(controller.activeTool, DrawTool.rectangle);
    expect(controller.creationTemplate, RectElement.zero);
  });

  testWidgets('triggers callback with null when tool is deselected', (tester) async {
    final controller = DrawController();
    DrawTool? selected = .select;
    final isEmptyAllowed = controller.elements.isEmpty;

    // Set selected index to make activeTool not null initially.
    controller.addElement(const RectElement(height: 50, width: 100, x: 10, y: 20));
    expect(controller.activeTool, DrawTool.select);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawToolSegmentedButton(
            controller,
            isEmptySelectionAllowed: isEmptyAllowed,
            onSelectionChanged: (tool) => selected = tool,
          ),
        ),
      ),
    );

    final panToolFinder = find.byIcon(Icons.pan_tool_alt_outlined);
    expect(panToolFinder, findsOneWidget);

    // Tap the already selected segment to deselect it.
    await tester.tap(panToolFinder);
    await tester.pumpAndSettle();

    expect(selected, isNull);
  });
});
