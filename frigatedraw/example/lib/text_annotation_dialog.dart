import 'package:flutter/material.dart';

import 'text_annotation_params.dart';

class TextAnnotationDialog extends StatefulWidget {
  const TextAnnotationDialog({super.key});

  @override
  State<TextAnnotationDialog> createState() => _TextAnnotationDialogState();
}

class _TextAnnotationDialogState extends State<TextAnnotationDialog> {
  final _textController = TextEditingController(text: 'Frigate');
  String _textValue = 'Frigate';
  double _fontSize = 48;
  double _rotation = 0;

  String get _trimmedText => _textValue.trim();

  void _handleSubmit() {
    final text = _trimmedText;
    if (text.isEmpty) return;

    final params = TextAnnotationParams(
      fontSize: _fontSize,
      rotation: _rotation.round(),
      text: text,
    );

    Navigator.of(context).pop(params);
  }

  void _handleTextChanged(String value) => setState(() => _textValue = value);

  void _handleTextSubmitted(String _) => _handleSubmit();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(
        onPressed: _trimmedText.isEmpty ? null : _handleSubmit,
        child: const Text('Render'),
      ),
    ],
    content: Column(
      mainAxisSize: .min,
      children: [
        TextField(
          autofocus: true,
          controller: _textController,
          decoration: const InputDecoration(labelText: 'Text to render'),
          onChanged: _handleTextChanged,
          onSubmitted: _handleTextSubmitted,
        ),
        const SizedBox(height: 16),
        Text('Font size: ${_fontSize.toStringAsFixed(0)} px'),
        Slider(
          max: 128,
          min: 12,
          onChanged: (value) => setState(() => _fontSize = value),
          value: _fontSize,
        ),
        Text('Rotation: ${_rotation.toStringAsFixed(0)} deg'),
        Slider(
          max: 180,
          min: -180,
          onChanged: (value) => setState(() => _rotation = value),
          value: _rotation,
        ),
      ],
    ),
    title: const Text('Render text annotation'),
  );
}
