// ignore_for_file: diagnostic_describe_all_properties, prefer-single-declaration-per-file, prefer-single-widget-per-file, prefer-static-class

import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:frigatedraw/frigatedraw.dart';
import 'package:path_provider_dart/path_provider_dart.dart';

Future<void> main() async {
  final _ = WidgetsFlutterBinding.ensureInitialized();
  final directory = _exportDestination;

  if (directory == null) {
    runApp(const MaterialApp(home: Scaffold(body: Text('Failed to initialize local directories'))));

    return;
  }

  final tempDir = await Directory.systemTemp.createTemp('frigate_');
  final imageFile = await _copyAssetToDisk(_sampleAsset, '${tempDir.path}/frigate_bg.png');
  final fontFile = await _copyAssetToDisk(_fontAsset, '${tempDir.path}/frigate_font.ttf');

  runApp(DrawingApp(directory, fontFile: fontFile, imageFile: imageFile, tempDir: tempDir));
}

const _fontAsset = 'assets/RobotoMono.ttf';
const _sampleAsset = 'assets/sample.png';

Directory? get _exportDestination {
  if (Platform.isIOS) {
    final documents = getApplicationDocumentsDirectory();

    return Directory('${documents.path}/Frigatedraw');
  }

  final downloads = getDownloadsDirectory();
  if (downloads == null) return null;

  return Directory('${downloads.path}/Frigatedraw');
}

Future<File> _copyAssetToDisk(String assetKey, String destPath) async {
  final bytes = await rootBundle.load(assetKey);

  return File(destPath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
}

class DrawingApp extends StatelessWidget {
  const DrawingApp(
    this.directory, {
    required this.fontFile,
    required this.imageFile,
    required this.tempDir,
    super.key,
  });

  final Directory directory;
  final File fontFile;
  final File imageFile;
  final Directory tempDir;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: DrawingScreen(
      destination: directory,
      fontFile: fontFile,
      imageFile: imageFile,
      tempDir: tempDir,
    ),
    theme: ThemeData.dark(useMaterial3: true),
  );
}

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({
    required this.destination,
    required this.fontFile,
    required this.imageFile,
    required this.tempDir,
    super.key,
  });

  final Directory destination;
  final File fontFile;
  final File imageFile;
  final Directory tempDir;

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  final _controller = DrawController();

  bool _isExporting = false;

  void _handleAddOval() => _controller.addElement(
    const OvalElement(height: 100, width: 150, x: 800 / 2 - 75, y: 600 / 2 - 50),
  );

  void _handleAddRect() => _controller.addElement(
    const RectElement(height: 100, width: 100, x: 800 / 2 - 50, y: 600 / 2 - 50),
  );

  void _handleAddRoundedRect() => _controller.addElement(
    const RectElement(cornerRadius: 16, height: 100, width: 100, x: 800 / 2 - 50, y: 600 / 2 - 50),
  );

  Future<void> _handleRenderText() async {
    if (_isExporting) return;

    final params = await showDialog<_TextAnnotationParams>(
      builder: (_) => const _TextAnnotationDialog(),
      context: context,
    );
    if (params == null || !mounted) return;

    setState(() => _isExporting = true);

    try {
      final directory = widget.destination;
      final downloadDir = await directory.create(recursive: true);
      final tempDir = widget.tempDir;

      final tempImageFile = await _copyAssetToDisk(
        _sampleAsset,
        '${tempDir.path}/frigate_sample.png',
      );
      final fontFile = await _copyAssetToDisk(_fontAsset, '${tempDir.path}/frigate_font.ttf');

      final outFile = File('${downloadDir.path}/frigate_sample.png');

      await RenderImage.run(
        backgroundPath: tempImageFile.path,
        elements: [
          TextElement(
            fontSize: params.fontSize,
            rotation: params.rotation,
            text: params.text,
            x: 800 / 4,
            y: 600 / 2,
          ),
        ],
        fontPath: fontFile.path,
        outputPath: outFile.path,
      );

      final msg = Platform.isIOS
          ? 'Stored in Files app under Frigatedraw'
          : 'Stored at ${outFile.path}';
      _showSnackBar(msg);
    } on Object catch (error, stackTrace) {
      _showSnackBar('Render failed: $error, $stackTrace');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _handleSave() async {
    if (_controller.elements.isEmpty) {
      _showSnackBar('No elements to export');

      return;
    }

    setState(() => _isExporting = true);

    try {
      final tempDir = widget.tempDir;
      final outFile = File('${tempDir.path}/frigate_export.jpg');

      await RenderImage.run(
        backgroundPath: widget.imageFile.path,
        elements: _controller.elements,
        fontPath: widget.fontFile.path,
        outputPath: outFile.path,
      );

      final jpegBytes = await outFile.readAsBytes();

      if (!mounted) return;
      final isConfirmed = await _isExportConfirmed(jpegBytes);
      if (isConfirmed == true) {
        final downloadDir = await widget.destination.create(recursive: true);
        final finalFile = File('${downloadDir.path}/frigate_composition.jpg');
        // ignore: avoid-ignoring-return-values, it is just an example
        await finalFile.writeAsBytes(jpegBytes, flush: true);

        if (mounted) {
          final msg = Platform.isIOS
              ? 'Stored in Files app under Frigatedraw'
              : 'Saved to ${finalFile.path}';
          _showSnackBar(msg);
        }
      }
    } on Object catch (error) {
      if (!mounted) return;
      _showSnackBar('Failed: $error');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _handleSavePressed() => unawaited(_handleSave());

  Future<bool?> _isExportConfirmed(Uint8List jpegBytes) => showDialog<bool>(
    builder: (context) => AlertDialog(
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Close')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
      ],
      clipBehavior: .antiAlias,
      content: Image.memory(jpegBytes, semanticLabel: 'Exported Image'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Exported Image'),
    ),
    context: context,
  );

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(icon: const Icon(Icons.undo), onPressed: _controller.undo, tooltip: 'Undo'),
        IconButton(icon: const Icon(Icons.redo), onPressed: _controller.redo, tooltip: 'Redo'),
        if (_isExporting)
          const Padding(
            padding: .all(12),
            child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _handleSavePressed,
            tooltip: 'Export composition',
          ),
      ],
      title: const Text('Frigate Draw'),
    ),
    body: DrawEditor(widget.imageFile, controller: _controller),
    bottomNavigationBar: BottomAppBar(
      child: Center(
        child: SegmentedButton<_DrawingTool>(
          emptySelectionAllowed: true,
          onSelectionChanged: (select) => switch (select.firstOrNull) {
            .text => unawaited(_handleRenderText()),
            .rounded => _handleAddRoundedRect(),
            .oval => _handleAddOval(),
            _ => _handleAddRect(), // ignore: avoid-wildcard-cases-with-enums, just an example.
          },
          segments: const [
            ButtonSegment(
              icon: Icon(Icons.crop_square),
              label: Text('Rect'),
              value: _DrawingTool.rect,
            ),
            ButtonSegment(
              icon: Icon(Icons.rounded_corner),
              label: Text('Rounded'),
              value: _DrawingTool.rounded,
            ),
            ButtonSegment(
              icon: Icon(Icons.circle_outlined),
              label: Text('Oval'),
              value: _DrawingTool.oval,
            ),
            ButtonSegment(
              icon: Icon(Icons.text_fields),
              label: Text('Text'),
              value: _DrawingTool.text,
            ),
          ],
          selected: const {},
        ),
      ),
    ),
  );
}

enum _DrawingTool { oval, rect, rounded, text }

class _TextAnnotationDialog extends StatefulWidget {
  const _TextAnnotationDialog();

  @override
  State<_TextAnnotationDialog> createState() => _TextAnnotationDialogState();
}

class _TextAnnotationDialogState extends State<_TextAnnotationDialog> {
  final _textController = TextEditingController(text: 'Frigate');
  double _fontSize = 48;
  double _rotation = 0;

  String get _trimmedText => _textController.text.trim();

  void _handleSubmit() {
    final text = _trimmedText;
    if (text.isEmpty) return;

    final params = _TextAnnotationParams(
      fontSize: _fontSize,
      rotation: _rotation.round(),
      text: text,
    );

    Navigator.of(context).pop(params);
  }

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
      ListenableBuilder(
        builder: (_, _) => FilledButton(
          onPressed: _trimmedText.isEmpty ? null : _handleSubmit,
          child: const Text('Render'),
        ),
        listenable: _textController,
      ),
    ],
    content: Column(
      mainAxisSize: .min,
      children: [
        TextField(
          autofocus: true,
          controller: _textController,
          decoration: const InputDecoration(labelText: 'Text to render'),
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

@immutable
final class _TextAnnotationParams {
  const _TextAnnotationParams({required this.fontSize, required this.rotation, required this.text});

  final double fontSize;
  final int rotation;
  final String text;
}
