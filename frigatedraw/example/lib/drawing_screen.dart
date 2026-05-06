import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:frigatedraw/frigatedraw.dart';
import 'package:meta/meta.dart';
import 'package:path_provider_dart/path_provider_dart.dart';

import 'text_annotation_dialog.dart';
import 'text_annotation_params.dart';

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

enum _DrawingTool { oval, rect, rounded, text }

class _DrawingScreenState extends State<DrawingScreen> {
  static const _imageWidth = 800;
  static const _imageHeight = 600;
  static const _sampleAsset = 'assets/sample.png';
  static const _fontAsset = 'assets/RobotoMono.ttf';

  static _ExportDestination? get _exportDestination {
    if (Platform.isIOS) {
      final documents = getApplicationDocumentsDirectory();

      return _ExportDestination(
        directory: Directory('${documents.path}/Frigatedraw'),
        successMessage: 'Stored in Files app under Frigatedraw',
      );
    }

    final downloads = getDownloadsDirectory();
    if (downloads == null) return null;

    return _ExportDestination(
      directory: Directory('${downloads.path}/Frigatedraw'),
      successMessage: 'Stored in Downloads/Frigatedraw',
    );
  }

  static Future<File> _copyAssetToDisk(String assetKey, String destPath) async {
    final bytes = await rootBundle.load(assetKey);

    return File(destPath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  final _controller = DrawController();

  bool _isExporting = false;

  void _handleAddRect() {
    _controller.addElement(
      const RectElement(height: 100, width: 100, x: _imageWidth / 2 - 50, y: _imageHeight / 2 - 50),
    );
  }

  void _handleAddRoundedRect() {
    _controller.addElement(
      const RectElement(
        cornerRadius: 16,
        height: 100,
        width: 100,
        x: _imageWidth / 2 - 30,
        y: _imageHeight / 2 - 30,
      ),
    );
  }

  void _handleAddOval() {
    _controller.addElement(
      const OvalElement(height: 100, width: 150, x: _imageWidth / 2 - 75, y: _imageHeight / 2 - 50),
    );
  }

  void _handleSavePressed() => _handleSave();

  @awaitNotRequired
  Future<void> _handleSave() async {
    if (_controller.elements.isEmpty) {
      _showSnackBar('No elements to export');

      return;
    }

    setState(() => _isExporting = true);

    try {
      final destination = _exportDestination;
      if (destination == null) {
        _showSnackBar('Export directory not available');

        return;
      }

      final directory = destination.directory;
      final tempDir = await directory.create(recursive: true);
      final backgroundFile = await _copyAssetToDisk(_sampleAsset, '${tempDir.path}/frigate_bg.png');
      final outFile = File('${tempDir.path}/frigate_export.jpg');
      final fontFile = await _copyAssetToDisk(_fontAsset, '${tempDir.path}/frigate_font.ttf');

      await RenderImage.run(
        backgroundPath: backgroundFile.path,
        elements: _controller.elements,
        fontPath: fontFile.path,
        outputPath: outFile.path,
      );

      final jpegBytes = await outFile.readAsBytes();

      if (!mounted) return;
      final shouldSave = await _showExportDialog(jpegBytes);
      if (shouldSave == true) {
        final finalFile = File('${tempDir.path}/frigate_composition.jpg')
          ..writeAsBytesSync(jpegBytes, flush: true);

        if (mounted) _showSnackBar('Saved to ${finalFile.path}');
      }
    } on Object catch (error) {
      if (!mounted) return;
      _showSnackBar('Failed: $error');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<bool?> _showExportDialog(Uint8List jpegBytes) => showDialog<bool>(
    builder: (context) => AlertDialog(
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Close')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
      ],
      clipBehavior: .antiAlias,
      content: Image.memory(jpegBytes, semanticLabel: 'Exported Image'),
      contentPadding: .zero,
      title: const Text('Exported Image'),
    ),
    context: context,
  );

  @awaitNotRequired
  Future<void> _handleRenderText() async {
    if (_isExporting) return;
    final params = await showDialog<TextAnnotationParams>(
      builder: (_) => const TextAnnotationDialog(),
      context: context,
    );
    if (params == null || !mounted) return;

    setState(() => _isExporting = true);

    try {
      final destination = _exportDestination;
      if (destination == null) {
        _showSnackBar('Export directory not available');

        return;
      }

      final directory = destination.directory;
      final downloadDir = await directory.create(recursive: true);
      final imageFile = await _copyAssetToDisk(
        _sampleAsset,
        '${downloadDir.path}/frigate_sample.png',
      );
      final fontFile = await _copyAssetToDisk(_fontAsset, '${downloadDir.path}/frigate_font.ttf');

      // Write to a temporary file then rename to ensure we don't open the same
      // file for reading and writing simultaneously in Rust.
      final outFile = File('${imageFile.path}.tmp.png');
      await RenderImage.run(
        backgroundPath: imageFile.path,
        elements: [
          TextElement(
            fontSize: params.fontSize,
            rotation: params.rotation,
            text: params.text,
            x: _imageWidth / 4,
            y: _imageHeight / 2,
          ),
        ],
        fontPath: fontFile.path,
        outputPath: outFile.path,
      );
      // ignore: avoid-ignoring-return-values, we don't need the returned File instance
      await outFile.rename(imageFile.path);

      _showSnackBar(destination.successMessage);
    } on Object catch (error, stackTrace) {
      _showSnackBar('Render failed: $error, $stackTrace');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

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
    body: DrawEditor(
      controller: _controller,
      image: const AssetImage(_sampleAsset),
      imageHeight: _imageHeight.toDouble(),
      imageWidth: _imageWidth.toDouble(),
    ),
    bottomNavigationBar: BottomAppBar(
      child: Center(
        child: SegmentedButton<_DrawingTool>(
          emptySelectionAllowed: true,
          onSelectionChanged: (select) => switch (select.firstOrNull) {
            .rounded => _handleAddRoundedRect(),
            .text => _handleRenderText(),
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

final class _ExportDestination {
  const _ExportDestination({required this.directory, required this.successMessage});

  final Directory directory;
  final String successMessage;
}
