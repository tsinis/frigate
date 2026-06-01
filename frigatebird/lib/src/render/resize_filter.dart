/// Interpolation filter for image resizing.
///
/// Wire values (0..3) match the Rust `ResizeFilter` enum exactly.
/// Default is [bilinear] (Triangle filter), matching OpenCV's default.
enum ResizeFilter {
  /// Bilinear (Triangle): good default balance of speed and quality.
  bilinear(1),

  /// Bicubic (Catmull-Rom): sharper than bilinear, slightly slower.
  catmullRom(2),

  /// Lanczos3: highest quality, slowest. Best for downscaling.
  lanczos3(3),

  /// Nearest-neighbor: fastest, no interpolation, blocky artifacts.
  nearest(0);

  const ResizeFilter(this.wire);

  /// Wire value sent to Rust FFI (matches `#[repr(u8)]` enum).
  final int wire;
}
