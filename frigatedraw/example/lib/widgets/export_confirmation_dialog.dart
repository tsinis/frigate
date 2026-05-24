// ignore_for_file: prefer-shorthands-with-enums, diagnostic_describe_all_properties, prefer_expression_function_bodies
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A preview dialog to confirm saving the exported composition.
class ExportConfirmationDialog extends StatelessWidget {
  const ExportConfirmationDialog({required this.jpegBytes, super.key});

  final Uint8List jpegBytes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Close')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
      ],
      clipBehavior: Clip.antiAlias,
      content: Image.memory(jpegBytes, semanticLabel: 'Exported Image'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Exported Image'),
    );
  }
}
