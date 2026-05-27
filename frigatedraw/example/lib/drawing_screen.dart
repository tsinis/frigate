import 'dart:async';
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data' show Float64x2, Float64x2List, Uint8List;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:frigatedraw/frigatedraw.dart';
import 'package:image_picker/image_picker.dart';

import 'utils.dart';
import 'widgets/blur_background_dialog.dart';
import 'widgets/export_confirmation_dialog.dart';
import 'widgets/text_annotation_dialog.dart';

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
  final _isExporting = ValueNotifier<bool>(false);

  late File _bgImageFile; // ignore: avoid-late-keyword, it's fine for example purposes.
  late File _originalBgImageFile; // ignore: avoid-late-keyword, it's fine for example purposes.
  double _selectedBlur = 50;
  DrawTool? _selectedTool;

  @override
  void initState() {
    super.initState();
    _bgImageFile = widget.imageFile;
    _originalBgImageFile = widget.imageFile;
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (_selectedTool != _controller.activeTool) setState(_syncSelectedTool);
  }

  void _syncSelectedTool() => _selectedTool = _controller.activeTool;

  void _updateCreationTemplate() {
    final blurVal = _selectedBlur.round();
    final (fill, outline, thickness, blur) = blurVal == 0
        ? (FfiColor.black, FfiColor.transparent, 0, 0)
        : (FfiColor.transparent, FfiColor.transparent, 0, blurVal);

    _controller.creationTemplate = switch (_selectedTool) {
      .rectangle => RectElement(
        blur: blur,
        fillColor: fill,
        height: 0,
        outlineColor: outline,
        outlineThickness: thickness,
        width: 0,
        x: 0,
        y: 0,
      ),
      .oval => OvalElement(
        blur: blur,
        fillColor: fill,
        height: 0,
        outlineColor: outline,
        outlineThickness: thickness,
        width: 0,
        x: 0,
        y: 0,
      ),
      .polygon => PolygonElement(
        blur: blur,
        fillColor: fill,
        height: 0,
        outlineColor: outline,
        outlineThickness: thickness,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(0, 0), Float64x2(0, 0)]),
        width: 0,
        x: 0,
        y: 0,
      ),
      .select || .text || null => null,
    };
  }

  Future<void> _handleReplaceImage() async {
    if (_isExporting.value) return;
    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(source: .gallery);
    if (pickedImage != null && mounted) {
      if (_isExporting.value) return;
      _bgImageFile = File(pickedImage.path);
      setState(() => _originalBgImageFile = File(pickedImage.path));
      _showSnackBar('Background image replaced successfully!');
    }
  }

  Future<void> _handleBlurBackground() async {
    if (_isExporting.value) return;
    final resultBlur = await showDialog<double>(
      builder: (context) => const BlurBackgroundDialog(),
      context: context,
    );

    if (resultBlur != null && mounted) {
      if (_isExporting.value) return;
      _isExporting.value = true;
      try {
        final ext = _originalBgImageFile.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
        final downloadDir = await widget.destination.create(recursive: true);
        final finalFile = File('${downloadDir.path}/blurred_background_image.$ext');

        await RenderImage.blurFullImage(
          imagePath: _originalBgImageFile.path,
          outputPath: finalFile.path,
          radius: resultBlur.round(),
        );

        await FileImage(finalFile).evict(); // ignore: avoid-ignoring-return-values, example only.
        if (mounted) setState(() => _bgImageFile = finalFile);

        _showSnackBar('Background blurred successfully! Saved to ${finalFile.path}');
      } on Object catch (error) {
        _showSnackBar('Failed to blur: $error');
      } finally {
        if (mounted) _isExporting.value = false;
      }
    }
  }

  Future<void> _handleRenderText() async {
    _controller.creationTemplate = null;
    if (_isExporting.value) return;

    final params = await showDialog<TextAnnotationParams>(
      builder: (_) => const TextAnnotationDialog(),
      context: context,
    );
    if (params == null || !mounted) return;
    _isExporting.value = true;

    try {
      final directory = widget.destination;
      final downloadDir = await directory.create(recursive: true);
      final tempDir = widget.tempDir;

      final tempImageFile = await copyAssetToDisk(
        sampleAsset,
        '${tempDir.path}/frigate_sample.png',
      );
      final fontFile = await copyAssetToDisk(fontAsset, '${tempDir.path}/frigate_font.ttf');

      final outFile = File('${downloadDir.path}/frigate_sample.png');

      await RenderImage.run(
        backgroundPath: tempImageFile.path,
        elements: [
          TextElement(
            height: params.fontSize,
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
      if (mounted) _isExporting.value = false;
    }
  }

  Future<void> _handleSave() async {
    if (_isExporting.value) return;
    if (_controller.elements.isEmpty) return _showSnackBar('No elements to export');
    _isExporting.value = true;

    try {
      final tempDir = widget.tempDir;
      final outFile = File('${tempDir.path}/frigate_export.jpg');

      await RenderImage.run(
        backgroundPath: _bgImageFile.path,
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
        // ignore: avoid-ignoring-return-values, example only.
        await finalFile.writeAsBytes(jpegBytes, flush: true);

        if (mounted) {
          final msg = Platform.isIOS
              ? 'Stored in Files app under Frigatedraw'
              : 'Saved to ${finalFile.path}';
          _showSnackBar(msg);
        }
      }
    } on Object catch (error) {
      if (mounted) _showSnackBar('Failed: $error');
    } finally {
      if (mounted) _isExporting.value = false;
    }
  }

  void _handleSavePressed() => unawaited(_handleSave());

  Future<bool?> _isExportConfirmed(Uint8List jpegBytes) => showDialog<bool>(
    builder: (context) => ExportConfirmationDialog(jpegBytes: jpegBytes),
    context: context,
  );

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: SelectableText(message)));
  }

  void _handlePopupMenuSelected(String value) {
    if (value == 'replace') {
      unawaited(_handleReplaceImage());
    } else if (value == 'blur_bg') {
      unawaited(_handleBlurBackground());
    }
  }

  void _handleBlurSliderChanged(double val) {
    final isSelected = _controller.selectedElement != null;
    if (isSelected) {
      final index = _controller.selectedIndex;
      final element = _controller.selectedElement;
      if (index != null && element != null) {
        final blurVal = val.round();
        if (blurVal == 0) {
          _controller.updateElement(
            element.copyWith(
              blur: 0,
              fillColor: .black,
              outlineColor: .transparent,
              outlineThickness: 0,
            ),
            index,
          );
        } else {
          _controller.updateElement(
            element.copyWith(
              blur: blurVal,
              fillColor: .transparent,
              outlineColor: .transparent,
              outlineThickness: 0,
            ),
            index,
          );
        }
      }
    } else {
      _selectedBlur = val;
      setState(_updateCreationTemplate);
    }
  }

  void _handleToolSelectionChanged(DrawTool? tool) {
    if (tool == .text) {
      unawaited(_handleRenderText());
    } else {
      _selectedTool = tool;
      setState(_updateCreationTemplate);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _isExporting.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        DrawUndoButton(_controller),
        DrawRedoButton(_controller),
        DrawDeleteButton(_controller),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'replace',
              child: ListTile(leading: Icon(Icons.image_search), title: Text('Replace image')),
            ),
            PopupMenuItem(
              value: 'blur_bg',
              child: ListTile(leading: Icon(Icons.blur_on), title: Text('Blur background')),
            ),
          ],
          onSelected: _handlePopupMenuSelected,
        ),
        ValueListenableBuilder<bool>(
          builder: (context, isExporting, _) => isExporting
              ? const Padding(
                  padding: .all(12),
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : DrawExportButton(_controller, onExport: _handleSavePressed),
          valueListenable: _isExporting,
        ),
      ],
      title: const Text('Frigate Draw'),
    ),
    body: DrawEditor(_bgImageFile, controller: _controller),
    bottomNavigationBar: BottomAppBar(
      height: 140,
      child: ListenableBuilder(
        builder: (context, _) {
          final isSelected = _controller.selectedElement != null;
          final sliderValue = isSelected
              ? (_controller.selectedElement?.blur.toDouble() ?? 0)
              : _selectedBlur;

          return Column(
            mainAxisAlignment: .center,
            mainAxisSize: .min,
            children: [
              Padding(
                padding: const .symmetric(horizontal: 8),
                child: Row(
                  spacing: 4,
                  children: [
                    DrawBlurToggleButton(_controller, minColor: .black),
                    Expanded(
                      child: DrawBlurSlider(
                        _controller,
                        minColor: .black,
                        onChanged: _handleBlurSliderChanged,
                        value: sliderValue,
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: .horizontal,
                child: Center(
                  child: DrawToolSegmentedButton(
                    _controller,
                    onSelectionChanged: _handleToolSelectionChanged,
                  ),
                ),
              ),
            ],
          );
        },
        listenable: _controller,
      ),
    ),
  );
}
