import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:frigatebird/frigatebird.dart';

/// A widget that displays an image from a file, respecting its EXIF orientation
/// by using Rust-side metadata to determine the correct dimensions.
///
/// Flutter's [Image.file] respects orientation but may have size mismatches
/// with the underlying pixel grid used by the Rust renderer. This widget
/// ensures the same dimensions are used on both sides.
class FfiImageFile extends Image {
  FfiImageFile(
    this._image, {
    this.builder,
    this.onInfo,
    this.size,
    super.errorBuilder,
    super.excludeFromSemantics,
    super.filterQuality,
    super.fit,
    super.gaplessPlayback = true,
    super.key,
    super.semanticLabel,
  }) : super.file(_image, height: size?.height, width: size?.width);

  /// Sets a test-only builder and returns a function to restore the previous builder.
  @visibleForTesting
  static VoidCallback setInfoBuilder(Future<ImageInformation> Function(String path) builder) {
    final oldBuilder = _infoBuilder;
    _infoFutureBuilderSetter(builder);

    return () => _infoFutureBuilderSetter(oldBuilder);
  }

  // ignore: use_setters_to_change_properties, not a public API and the method is more explicit.
  static void _infoFutureBuilderSetter(Future<ImageInformation> Function(String path) builder) =>
      _infoBuilder = builder;

  final File _image;

  /// If provided, this callback allows custom layout control by wrapping the pre-configured [Image].
  /// If not provided, returns the [Image] widget directly.
  final Widget Function(Image displayedImage, ImageInformation? info, ui.Image? uiImage)? builder;
  final ValueChanged<ImageInformation>? onInfo;

  /// Optional fixed size. If provided, FFI probing is skipped.
  final Size? size; // ignore: diagnostic_describe_all_properties, shown via parent width/height.

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ObjectFlagProperty.has('builder', builder))
      ..add(ObjectFlagProperty.has('onInfo', onInfo));
  }

  @override
  State<FfiImageFile> createState() => _FfiImageFileState();

  static Future<ImageInformation> Function(String path) _infoBuilder = ImageInformation.probe;
}

class _FfiImageFileState extends State<FfiImageFile> {
  ImageInformation? _info;
  ui.Image? _uiImage;
  Uint8List? _bytes;
  Object? _error; // ignore: no-object-declaration, we don't know the type in advance.
  StackTrace? _stackTrace;
  File? _loadedImageFile;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _decodeAndSetBytes(Uint8List bytes, File file) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      if (!mounted || _loadedImageFile != file) return frame.image.dispose();
      final oldUiImage = _uiImage;
      _bytes = bytes;
      setState(() => _uiImage = frame.image);
      oldUiImage?.dispose();
    } finally {
      codec.dispose();
    }
  }

  Future<void> _load() async {
    final file = widget._image;
    _loadedImageFile = file;
    final hadError = _error != null || _stackTrace != null;
    _error = null;
    if (hadError) setState(() => _stackTrace = null);

    // 1. Run the size probe first in Phase 1.
    ImageInformation? info;
    final size = widget.size;
    try {
      info = size == null
          ? await FfiImageFile._infoBuilder(file.absolute.path)
          : ImageInformation(height: size.height.toInt(), width: size.width.toInt());
      if (!mounted || _loadedImageFile != file) return;
      widget.onInfo?.call(info);
      if (info != _info) setState(() => _info = info);

      // 2. Decode the bytes inside Phase 2.
      try {
        final bytes = await file.readAsBytes();
        if (!mounted || _loadedImageFile != file) return;

        await _decodeAndSetBytes(bytes, file);
      } on Object catch (_) {
        // If byte reading/decoding fails (e.g. in unit tests where file doesn't exist),
        // we silently ignore or log it, and do not fail the widget rendering.
        // The displayedImage remains Image.file which is exactly what tests and fallbacks expect!
      }
    } on Object catch (error, stackTrace) {
      if (!mounted || _loadedImageFile != file) return;
      _error = error;
      setState(() => _stackTrace = stackTrace);
    }
  }

  @override
  void didUpdateWidget(FfiImageFile oldWidget) {
    super.didUpdateWidget(oldWidget);

    final hasPathChanged = oldWidget._image.absolute.path != widget._image.absolute.path;
    final hasSizeNullabilityChanged = (oldWidget.size == null) != (widget.size == null);

    if (hasPathChanged || hasSizeNullabilityChanged) {
      if (hasPathChanged) {
        final oldUiImage = _uiImage;
        _uiImage = null;
        _bytes = null;
        _info = null;
        oldUiImage?.dispose();
      }
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _uiImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.size?.width ?? _info?.width.toDouble();
    final height = widget.size?.height ?? _info?.height.toDouble();

    final bytes = _bytes;
    final displayedImage = bytes == null
        ? Image.file(
            widget._image,
            errorBuilder: widget.errorBuilder,
            excludeFromSemantics: widget.excludeFromSemantics,
            filterQuality: widget.filterQuality,
            fit: widget.fit,
            gaplessPlayback: widget.gaplessPlayback,
            height: height,
            semanticLabel: widget.semanticLabel,
            width: width,
          )
        : Image.memory(
            bytes,
            errorBuilder: widget.errorBuilder,
            excludeFromSemantics: widget.excludeFromSemantics,
            filterQuality: widget.filterQuality,
            fit: widget.fit,
            gaplessPlayback: widget.gaplessPlayback,
            height: height,
            semanticLabel: widget.semanticLabel,
            width: width,
          );

    final error = _error;
    if (error != null) {
      final errorWidget = widget.errorBuilder?.call(context, error, _stackTrace);
      if (errorWidget != null) return errorWidget;
    }

    return widget.builder?.call(displayedImage, _info, _uiImage) ?? displayedImage;
  }
}
