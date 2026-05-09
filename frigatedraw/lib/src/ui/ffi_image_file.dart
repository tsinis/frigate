// ignore_for_file: prefer-class-destructuring, in widgets more explicit with named parameters...

import 'dart:async';
import 'dart:io';

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
    super.errorBuilder,
    super.excludeFromSemantics,
    super.filterQuality,
    super.fit,
    super.key,
    super.semanticLabel,
    this.size,
  }) : super.file(_image, height: size?.height, width: size?.width);

  @visibleForTesting
  /// Sets a test-only builder and returns a function to restore the previous builder.
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
  final Widget Function(BuildContext context, Image image)? builder;

  /// Optional fixed size. If provided, FFI probing is skipped.
  final Size? size; // ignore: diagnostic_describe_all_properties, shown via parent width/height.

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty.has('builder', builder));
  }

  @override
  State<FfiImageFile> createState() => _FfiImageFileState();

  static Future<ImageInformation> Function(String path) _infoBuilder = ImageInformation.probe;
}

class _FfiImageFileState extends State<FfiImageFile> {
  // ignore: avoid-late-keyword, it's more efficient to reuse the same Future instance.
  late Future<ImageInformation?> _infoFuture = _loadInfo();

  // ignore: prefer-getter-over-method, more suitable for the FutureBuilder pattern.
  Future<ImageInformation?> _loadInfo() async =>
      widget.size == null ? FfiImageFile._infoBuilder(widget._image.absolute.path) : null;

  @override
  void didUpdateWidget(FfiImageFile oldWidget) {
    super.didUpdateWidget(oldWidget);

    final hasPathChanged = oldWidget._image.absolute.path != widget._image.absolute.path;
    final hasSizeNullabilityChanged = (oldWidget.size == null) != (widget.size == null);

    //ignore:avoid-async-call-in-sync-function,avoid-unnecessary-setstate, to trigger FutureBuilder.
    if (hasPathChanged || hasSizeNullabilityChanged) setState(() => _infoFuture = _loadInfo());
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Image.file(
      widget._image,
      errorBuilder: widget.errorBuilder,
      excludeFromSemantics: widget.excludeFromSemantics,
      filterQuality: widget.filterQuality,
      fit: widget.fit,
      height: widget.size?.height,
      semanticLabel: widget.semanticLabel,
      width: widget.size?.width,
    );
    if (widget.size != null) return widget.builder?.call(context, fallback) ?? fallback;

    return FutureBuilder(
      builder: (bc, snap) {
        final image = Image.file(
          widget._image,
          errorBuilder: widget.errorBuilder,
          excludeFromSemantics: widget.excludeFromSemantics,
          filterQuality: widget.filterQuality,
          fit: widget.fit,
          height: snap.data?.height.toDouble() ?? fallback.height,
          semanticLabel: widget.semanticLabel,
          width: snap.data?.width.toDouble() ?? fallback.width,
        );
        if (snap.connectionState == .waiting) return widget.builder?.call(bc, image) ?? image;

        return snap.hasError
            ? (widget.errorBuilder?.call(bc, snap.error ?? 'frigatedraw', snap.stackTrace) ?? image)
            : (widget.builder?.call(bc, image) ?? image);
      },
      future: _infoFuture,
    );
  }
}
