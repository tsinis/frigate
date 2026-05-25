import 'package:flutter/material.dart';
import 'package:frigatedraw/frigatedraw.dart';

import 'tool_segmented_button.dart';

/// A row containing [ToolSegmentedButton].
class ToolsRow extends StatelessWidget {
  const ToolsRow({required this.onToolSelectionChanged, required this.selectedTool, super.key});

  final ValueChanged<DrawTool> onToolSelectionChanged;
  final DrawTool selectedTool;

  @override
  Widget build(BuildContext context) => Center(
    child: ToolSegmentedButton(
      onSelectionChanged: onToolSelectionChanged,
      selectedTool: selectedTool,
    ),
  );
}
