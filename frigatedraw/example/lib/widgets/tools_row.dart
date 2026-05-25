import 'package:flutter/material.dart';
import 'package:frigatedraw/frigatedraw.dart';

import 'style_dropdown.dart';
import 'tool_segmented_button.dart';

/// A row containing [StyleDropdown] and [ToolSegmentedButton].
class ToolsRow extends StatelessWidget {
  const ToolsRow({
    required this.onStyleModeChanged,
    required this.onToolSelectionChanged,
    required this.selectedStyleMode,
    required this.selectedTool,
    super.key,
  });

  final ValueChanged<DrawingStyleMode?> onStyleModeChanged;
  final ValueChanged<DrawTool> onToolSelectionChanged;
  final DrawingStyleMode selectedStyleMode;
  final DrawTool selectedTool;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: .spaceEvenly,
    children: [
      StyleDropdown(onChanged: onStyleModeChanged, selectedStyleMode: selectedStyleMode),
      ToolSegmentedButton(onSelectionChanged: onToolSelectionChanged, selectedTool: selectedTool),
    ],
  );
}
