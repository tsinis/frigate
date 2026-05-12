import 'dart:ffi';

import 'bindings.dart' as ffi;
import 'ffi_arena.dart';
import 'ffi_element.dart';
import 'ffi_error.dart';
import 'image_info_struct.dart';

/// Runtime guards that the Dart-side `Struct` layouts for the FFI types match the wire
/// contract baked into the Rust crate.
abstract final class FfiAbi {
  /// Expected size in bytes for the element payload union in C.
  /// Used by [FfiPayload] to anchor its size.
  static const payloadBytes = 48;

  /// Error buffer capacity allocated by `FfiMarshal.encodeElements` for Rust to write
  /// diagnostic messages into. Single source of truth — Rust docs reference this value too.
  static const errorCapBytes = 256;

  static bool _hasAsserted = false;

  /// Single entry point for all ABI stability checks.
  ///
  /// Probes the Rust library at runtime to verify that the byte-size of every shared struct
  /// matches what Dart expects. (e.g. if a developer adds a field to `ImageInformation` in
  /// Rust but forgetting to update the Dart Struct) which would otherwise cause silent memory
  /// corruption or garbage reads.
  ///
  /// **Throws in release builds** — ABI mismatch is a fatal error that leads to data corruption.
  static void assertAll() {
    if (_hasAsserted) return;
    _check('FfiElement', sizeOf<FfiElement>(), ffi.sizeof_ffi_element());
    _check('FfiPayload', sizeOf<FfiPayload>(), ffi.sizeof_ffi_payload());
    _check('FfiArena', sizeOf<FfiArena>(), ffi.sizeof_ffi_arena());
    _check('FfiError', sizeOf<FfiError>(), ffi.sizeof_ffi_error());
    _check('ImageInfo', sizeOf<ImageInfoStruct>(), ffi.sizeof_image_info());
    _hasAsserted = true;
  }

  static void _check(String name, int dart, int rust) {
    if (dart != rust) throw StateError('ABI mismatch: $name Dart=$dart Rust=$rust');
  }
}
