// ignore_for_file: prefer-shorthands-with-enums, parameters-ordering, prefer-extracting-callbacks, diagnostic_describe_all_properties, prefer_expression_function_bodies
import 'package:flutter/material.dart';
import 'package:frigatedraw/frigatedraw.dart';

/// A segmented button for selecting the active [DrawTool].
class ToolSegmentedButton extends StatelessWidget {
  const ToolSegmentedButton({
    required this.selectedTool,
    required this.onSelectionChanged,
    super.key,
  });

  final DrawTool selectedTool;
  final ValueChanged<DrawTool> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<DrawTool>(
      emptySelectionAllowed: true,
      onSelectionChanged: (select) {
        onSelectionChanged(select.firstOrNull ?? DrawTool.select);
      },
      segments: const [
        ButtonSegment(
          icon: Icon(Icons.pan_tool_alt),
          label: Text('Select'),
          value: DrawTool.select,
        ),
        ButtonSegment(
          icon: Icon(Icons.crop_square),
          label: Text('Rect'),
          value: DrawTool.rectangle,
        ),
        ButtonSegment(icon: Icon(Icons.circle_outlined), label: Text('Oval'), value: DrawTool.oval),
        ButtonSegment(
          icon: Icon(Icons.hexagon_outlined),
          label: Text('Polygon'),
          value: DrawTool.polygon,
        ),
        ButtonSegment(icon: Icon(Icons.text_fields), label: Text('Text'), value: DrawTool.text),
      ],
      selected: {selectedTool},
    );
  }
}
