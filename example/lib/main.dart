import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:frigate_draw/frigate_draw.dart';

void main() {
  runApp(const DrawingApp());
}

class DrawingApp extends StatelessWidget {
  const DrawingApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: const DrawingScreen(),
  );
}

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  static const _imageWidth = 800;
  static const _imageHeight = 600;

  final _controller = DrawController();
  final _backend = createExportBackend();

  bool _exporting = false;
  bool _imageLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final data = await rootBundle.load('assets/sample.png');
    await _backend.loadImage(
      data.buffer.asUint8List(),
      height: _imageHeight,
      width: _imageWidth,
    );
    if (mounted) setState(() => _imageLoaded = true);
  }

  void _addRectInCenter() {
    _controller.addElement(
      RectElement(
        height: 100,
        width: 100,
        x: _imageWidth / 2 - 50,
        y: _imageHeight / 2 - 50,
      ),
    );
  }

  Future<void> _onSave() async {
    final rects = _controller.elements.whereType<RectElement>().toList();
    if (rects.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No rectangles to export')));

      return;
    }

    setState(() => _exporting = true);

    try {
      final jpegBytes = await _backend.export(rects: rects);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(child: Image.memory(jpegBytes)),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
      title: const Text('Frigate Draw'),
      actions: [
        IconButton(icon: const Icon(Icons.undo), onPressed: _controller.undo),
        IconButton(icon: const Icon(Icons.redo), onPressed: _controller.redo),
        if (_exporting)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _imageLoaded ? _onSave : null,
          ),
      ],
    ),
    body: DrawEditor(
      controller: _controller,
      image: const AssetImage('assets/sample.png'),
      imageHeight: _imageHeight.toDouble(),
      imageWidth: _imageWidth.toDouble(),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: _addRectInCenter,
      child: const Icon(Icons.add),
    ),
  );
}
