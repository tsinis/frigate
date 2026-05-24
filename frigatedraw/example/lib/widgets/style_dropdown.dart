// ignore_for_file: parameters-ordering, prefer-switch-with-sealed-classes, avoid-type-casts, diagnostic_describe_all_properties, prefer_expression_function_bodies
import 'package:flutter/material.dart';
import 'package:frigatedraw/frigatedraw.dart';

/// A dropdown menu for selecting [DrawingStyleMode] presets.
class StyleDropdown extends StatelessWidget {
  const StyleDropdown({required this.selectedStyleMode, required this.onChanged, super.key});

  final DrawingStyleMode selectedStyleMode;
  final ValueChanged<DrawingStyleMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<DrawingStyleMode>(
      icon: const Icon(Icons.style),
      items: [
        const DropdownMenuItem(value: ColorStyle(), child: Text('Black Fill')),
        const DropdownMenuItem(
          value: ColorStyle(color: FfiColor(0xFFFF0000)),
          child: Text('Red Fill'),
        ),
        const DropdownMenuItem(
          value: ColorStyle(color: FfiColor(0xFF0000FF)),
          child: Text('Blue Fill'),
        ),
        const DropdownMenuItem(value: BlurStyle(), child: Text('Blur (10px)')),
        const DropdownMenuItem(value: BlurStyle(blur: 50), child: Text('Blur (50px)')),
        if (selectedStyleMode != const ColorStyle() &&
            selectedStyleMode != const ColorStyle(color: FfiColor(0xFFFF0000)) &&
            selectedStyleMode != const ColorStyle(color: FfiColor(0xFF0000FF)) &&
            selectedStyleMode != const BlurStyle() &&
            selectedStyleMode != const BlurStyle(blur: 50))
          DropdownMenuItem(
            value: selectedStyleMode,
            child: Text(
              selectedStyleMode is BlurStyle
                  ? 'Custom Blur (${(selectedStyleMode as BlurStyle).blur}px)'
                  : 'Custom Color',
            ),
          ),
      ],
      onChanged: onChanged,
      underline: const SizedBox(),
      value: selectedStyleMode,
    );
  }
}
