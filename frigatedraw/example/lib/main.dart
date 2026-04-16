import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:frigatedraw/frigatedraw.dart';
import 'package:meta/meta.dart';

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
    final data = await rootBundle.load('assets/sample.png');
    await _backend.loadImage(data.buffer.asUint8List(), height: _imageHeight, width: _imageWidth);
    if (mounted) setState(() => _isImageLoaded = true);
  }

  void _handleAddRect() {
    _controller.addElement(
      const RectElement(height: 100, width: 100, x: _imageWidth / 2 - 50, y: _imageHeight / 2 - 50),
    );
  }

  @awaitNotRequired
  Future<ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?> _handleSave() async {
    final rects = _controller.elements.whereType<RectElement>().toList();
    if (rects.isEmpty) {
      if (!mounted) return null;

      return ScaffoldMessenger.of(
        context, // Dart 3.8 Formatting.
      ).showSnackBar(const SnackBar(content: Text('No rectangles to export')));
    }

    setState(() => _isExporting = true);

    try {
      final jpegBytes = await _backend.export(rects: rects);

      if (!mounted) return null;
      await showDialog<void>(
        builder: (_) => Dialog(child: Image.memory(jpegBytes, semanticLabel: 'Exported Image')),
        context: context,
      );
    } on Object catch (error) {
      if (!mounted) return null;

      return ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $error')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }

    return null;
  }

  @override
  void dispose() {
    _backend.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        IconButton(icon: const Icon(Icons.undo), onPressed: _controller.undo),
        IconButton(icon: const Icon(Icons.redo), onPressed: _controller.redo),
        if (_isExporting)
          const Padding(
            padding: .all(12),
            child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          // ignore: avoid-passing-async-when-sync-expected, await is not required (annotated).
          IconButton(icon: const Icon(Icons.save), onPressed: _isImageLoaded ? _handleSave : null),
      ],
      title: const Text('Frigate Draw'),
    ),
    body: DrawEditor(
      controller: _controller,
      image: const AssetImage('assets/sample.png'),
      imageHeight: _imageHeight.toDouble(),
      imageWidth: _imageWidth.toDouble(),
    ),
    floatingActionButton: FloatingActionButton(
      heroTag: 'Add',
      onPressed: _handleAddRect,
      tooltip: 'Add Rectangle',
      child: const Icon(Icons.add),
    ),
  );
}
