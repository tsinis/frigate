import '../model/draw_element.dart';

/// Arguments bundle for `RenderImage.run`'s background-isolate worker.
///
/// The wrapper is a plain final class — `List` itself is not deeply-immutable, but the
/// `DrawElement` instances inside *are* (each subtype carries `@pragma('vm:deeply-immutable')`),
/// so they transfer zero-copy across the isolate boundary. Strings and ints are also
/// deeply-immutable. Cost is one args-object copy per call.
final class RenderImageArgs {
  const RenderImageArgs({
    required this.elements,
    required this.fontPath,
    required this.imagePath,
    required this.imageQuality,
    required this.outputPath,
  });

  final List<DrawElement> elements;
  final String? fontPath;
  final String imagePath;
  final int imageQuality;
  final String outputPath;
}
