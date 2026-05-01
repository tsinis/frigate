import 'dart:ffi';

import 'export_backend_native.dart' show ExportBackendNative;
import 'ffi_element.dart';
import 'ffi_rect_element.dart';

/// Runtime guards that the Dart-side `Struct` layouts for the FFI types match the wire
/// contract baked into the Rust crate. Cheap — `sizeOf<T>()` specializes to a direct read for
/// fixed-layout `Struct` subclasses. Assertions fire in debug only (CI runs in debug, and a
/// mismatch crashes the very first test we run); release builds trust the Rust-side compile-
/// time asserts on both sides of the boundary.
///
/// Class with statics rather than top-level functions so the FFI namespace stays discoverable
/// (`FfiAbi.` autocompletes both checks together) instead of leaking two unrelated-looking
/// names into every file that imports `ffi_abi.dart`.
sealed class FfiAbi {
  /// Expected byte size of [FfiElement] as defined by the Rust `#[repr(C)]` layout +
  /// compile-time assertions in `rust/src/ffi_element.rs`. Both sides MUST agree; a mismatch
  /// means silent data corruption the moment we read back any field.
  static const elementBytes = 72;

  /// Expected byte size of [FfiRectElement]. Mirrors `rust/src/lib.rs` (4 × f64 + 3 × u32 with
  /// 8-byte alignment padding).
  static const rectElementBytes = 48;

  /// Guard that the Dart-side Struct layout for [FfiElement] matches the wire contract.
  /// Called from every FFI entry point that touches an [FfiElement] array.
  static void assertElement({int expectedSize = elementBytes}) {
    final actualSize = sizeOf<FfiElement>();
    assert(
      actualSize == expectedSize,
      'FfiElement ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize. '
      'Struct layout has drifted between sides — all render calls would read garbage.',
    );
  }

  /// Guard that the Dart-side Struct layout for [FfiRectElement] matches the wire contract.
  /// Called from [ExportBackendNative.loadImage].
  static void assertRectElement({int expectedSize = rectElementBytes}) {
    final actualSize = sizeOf<FfiRectElement>();
    assert(
      actualSize == expectedSize,
      'FfiRectElement ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize. '
      'Struct layout has drifted between sides — all export_image calls would read garbage.',
    );
  }
}
