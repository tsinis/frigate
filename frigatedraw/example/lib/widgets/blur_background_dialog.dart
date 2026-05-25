// ignore_for_file: prefer-shorthands-with-enums, diagnostic_describe_all_properties, prefer_expression_function_bodies
import 'package:flutter/material.dart';

/// A dialog to customize the background blur radius.
class BlurBackgroundDialog extends StatefulWidget {
  const BlurBackgroundDialog({super.key});

  @override
  State<BlurBackgroundDialog> createState() => _BlurBackgroundDialogState();
}

class _BlurBackgroundDialogState extends State<BlurBackgroundDialog> {
  double _currentBlur = 10;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_currentBlur),
          child: const Text('Apply'),
        ),
      ],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Blur radius: ${_currentBlur.round()} px'),
          Slider(
            divisions: 255,
            max: 255,
            onChanged: (val) => setState(() => _currentBlur = val),
            value: _currentBlur,
          ),
        ],
      ),
      title: const Text('Blur Background'),
    );
  }
}
