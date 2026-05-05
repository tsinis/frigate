import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:frigatedraw/frigatedraw.dart';
import 'package:meta/meta.dart';
import 'package:path_provider_ffi/path_provider_ffi.dart';

import 'text_annotation_dialog.dart';
import 'text_annotation_params.dart';

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  static const _imageWidth = 800;
  static const _imageHeight = 600;
  static const _sampleAsset = 'assets/sample.png';
  static const _fontAsset = 'assets/RobotoMono.ttf';

  static _ExportDestination? get _exportDestination {
    if (Platform.isIOS) {
      final documents = getApplicationDocumentsDirectory();

      return _ExportDestination(
        directory: documents,
        successMessage: 'Stored in Files app under Frigatedraw',
      );
    }

    final downloads = getDownloadsDirectory();
    if (downloads == null) return null;

    final successMessage = Platform.isAndroid
        ? 'Stored in app-specific downloads'
        : 'Stored in Downloads';

    return _ExportDestination(directory: downloads, successMessage: successMessage);
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

  void _handleSavePressed() {
    _handleSave();
  }

  @awaitNotRequired
  Future<void> _handleSave() async {
    if (_controller.elements.isEmpty) {
      if (!mounted) return;
      _showSnackBar('No elements to export');

      return;
    }

    setState(() => _isExporting = true);

    try {
      final destination = _exportDestination;
      if (destination == null) {
        if (!mounted) return;
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
      await _showExportDialog(jpegBytes);
    } on Object catch (error) {
      if (!mounted) return;
      _showSnackBar('Failed: $error');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _showExportDialog(Uint8List jpegBytes) async {
    await showDialog<void>(
      builder: (_) => Dialog(
        clipBehavior: .antiAlias,
        child: Column(
          mainAxisSize: .min,
          children: [
            Image.memory(jpegBytes, semanticLabel: 'Exported Image'),
            Padding(
              padding: const .all(8),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
      context: context,
    );
  }

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
        if (!mounted) return;
        _showSnackBar('Downloads directory not available on this platform');

        return;
      }

      final directory = destination.directory;
      final successMessage = destination.successMessage;
      final downloadDir = await directory.create(recursive: true);
      final imageFile = await _copyAssetToDisk(
        _sampleAsset,
        '${downloadDir.path}/frigate_sample.png',
      );
      final fontFile = await _copyAssetToDisk(_fontAsset, '${downloadDir.path}/frigate_font.ttf');

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
        outputPath: imageFile.path,
      );

      if (!mounted) return;
      _showSnackBar('$successMessage: ${imageFile.path}');
    } on RenderException catch (error) {
      if (!mounted) return;
      _showSnackBar('Render failed: $error');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showSnackBar(String message) {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _controller.undo, tooltip: 'Undo'),
          IconButton(icon: const Icon(Icons.redo), onPressed: _controller.redo, tooltip: 'Redo'),
          if (_isExporting)
            const Padding(
              padding: .all(12),
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
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
      body: Center(
        child: Padding(
          padding: const .all(16),
          child: AspectRatio(
            aspectRatio: _imageWidth / _imageHeight,
            child: Material(
              clipBehavior: .antiAlias,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: const .all(.circular(12)),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: DrawEditor(
                controller: _controller,
                image: const AssetImage(_sampleAsset),
                imageHeight: _imageHeight.toDouble(),
                imageWidth: _imageWidth.toDouble(),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: .center,
          spacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.crop_square),
              label: const Text('Rect'),
              onPressed: _handleAddRect,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.rounded_corner),
              label: const Text('Rounded'),
              onPressed: _handleAddRoundedRect,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.circle_outlined),
              label: const Text('Oval'),
              onPressed: _handleAddOval,
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.text_fields),
              label: const Text('Add Text'),
              // ignore: avoid-passing-async-when-sync-expected, intentional tearoff
              onPressed: _handleRenderText,
            ),
          ],
        ),
      ),
    );
  }
}

final class _ExportDestination {
  const _ExportDestination({required this.directory, required this.successMessage});

  final Directory directory;
  final String successMessage;
}
