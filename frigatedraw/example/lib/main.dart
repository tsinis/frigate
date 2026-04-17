// ColorScheme exposes paired on*/non-on* fields by design; destructuring them all is fine.
// ignore_for_file: avoid-similar-names

import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:frigatedraw/frigatedraw.dart';
import 'package:meta/meta.dart';
import 'package:path_provider_ffi/path_provider_ffi.dart';

import 'text_annotation_dialog.dart';
import 'text_annotation_params.dart';

void main() => runApp(const DrawingApp());

class DrawingApp extends StatelessWidget {
  const DrawingApp({super.key});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: const DrawingScreen(), theme: ThemeData.dark(useMaterial3: true));
}

// ignore: prefer-single-widget-per-file, prefer-single-declaration-per-file, TODO(tsinis): split it
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
  // ignore: avoid-explicit-type-declaration, against specify_nonobvious_property_types.
  final ExportBackend _backend = createExportBackend();

  bool _isExporting = false;
  bool _isImageLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @awaitNotRequired
  Future<void> _loadImage() async {
    final data = await rootBundle.load(_sampleAsset);
    await _backend.loadImage(data.buffer.asUint8List(), height: _imageHeight, width: _imageWidth);
    if (mounted) setState(() => _isImageLoaded = true);
  }

  void _handleAddRect() {
    _controller.addElement(
      const RectElement(height: 100, width: 100, x: _imageWidth / 2 - 50, y: _imageHeight / 2 - 50),
    );
  }

  void _handleAddRoundedRect() {
    // Slightly offset so the rounded one doesn't sit exactly on top of the sharp one when
    // both are added for comparison.
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

  void _handleSavePressed() {
    _handleSave();
  }

  void _handleFabLongPress() => _handleRenderText();

  @awaitNotRequired
  Future<void> _handleSave() async {
    final rects = _controller.elements.whereType<RectElement>().toList();
    if (rects.isEmpty) {
      if (!mounted) return;

      _showSnackBar('No rectangles to export');

      return;
    }

    setState(() => _isExporting = true);

    try {
      final jpegBytes = await _backend.export(rects: rects);

      if (!mounted) return;
      await showDialog<void>(
        builder: (_) => Dialog(child: Image.memory(jpegBytes, semanticLabel: 'Exported Image')),
        context: context,
      );
    } on Object catch (error) {
      if (!mounted) return;

      _showSnackBar('Failed: $error');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Long-press on the FAB: open a dialog to configure a text annotation, then write a fresh
  /// copy of the sample image + font to the user's Downloads folder, render the text onto it
  /// (output path == input path, so the copy is overwritten in place), and show a snackbar
  /// pointing to the saved file.
  @awaitNotRequired
  Future<void> _handleRenderText() async {
    if (_isExporting || !_isImageLoaded) return;
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

      final _ExportDestination(:directory, :successMessage) = destination;
      final downloadDir = await directory.create(recursive: true);
      final imageFile = await _copyAssetToDisk(
        _sampleAsset,
        '${downloadDir.path}/frigate_sample.png',
      );
      final fontFile = await _copyAssetToDisk(_fontAsset, '${downloadDir.path}/frigate_font.ttf');

      // Always start from the pristine asset — without this step, a second render would stack
      // text on top of the previous one (since output path == input path).
      await RenderImage.run(
        elements: [
          TextElement(
            fontSize: params.fontSize,
            rotation: params.rotation,
            text: params.text,
            x: _imageWidth / 4.0,
            y: _imageHeight / 2.0,
          ),
        ],
        fontPath: fontFile.path,
        imagePath: imageFile.path,
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
    _backend.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme(
      :onPrimaryContainer,
      :onSecondaryContainer,
      :primaryContainer,
      :secondaryContainer,
    ) = Theme.of(
      context, // Dart 3.8 formatting.
    ).colorScheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(icon: const Icon(Icons.undo), onPressed: _controller.undo),
          IconButton(icon: const Icon(Icons.redo), onPressed: _controller.redo),
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
              onPressed: _isImageLoaded ? _handleSavePressed : null,
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
      floatingActionButton: Column(
        mainAxisSize: .min,
        spacing: 12,
        children: [
          // Small FAB: adds a rounded-corner rectangle. Sits above the main FAB so the
          // primary tap still adds a sharp rect.
          FloatingActionButton.small(
            backgroundColor: secondaryContainer,
            foregroundColor: onSecondaryContainer,
            heroTag: 'add-rounded-rect',
            onPressed: _isImageLoaded ? _handleAddRoundedRect : null,
            tooltip: 'Add rounded rectangle',
            child: const Icon(Icons.rounded_corner),
          ),
          Tooltip(
            message: 'Tap to add rectangle; long-press to render text',
            child: RawMaterialButton(
              constraints: const BoxConstraints.tightFor(height: 56, width: 56),
              elevation: 6,
              fillColor: primaryContainer,
              onLongPress: _handleFabLongPress,
              onPressed: _handleAddRect,
              shape: const CircleBorder(),
              child: Icon(Icons.add, color: onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ExportDestination {
  const _ExportDestination({required this.directory, required this.successMessage});

  final Directory directory;
  final String successMessage;
}
