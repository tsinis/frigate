import 'dart:ffi';

import 'ffi_element.dart';
import 'ffi_rect_element.dart';

/// Expected byte size of [FfiElement] as defined by the Rust `#[repr(C)]` layout + compile-time
/// assertions in `rust/src/ffi_element.rs`. Both sides MUST agree; a mismatch means silent
/// data corruption the moment we read back any field.
const _ffiElementBytes = 72;

/// Expected byte size of [FfiRectElement]. Mirrors `rust/src/lib.rs`.
const _ffiRectElementBytes = 40;

/// Guard that the Dart-side Struct layout for [FfiElement] matches the wire contract. Called from
/// every FFI entry point that touches an [FfiElement] array. Cheap — `sizeOf<T>()` is a constant
/// folded by the VM. The assertion fires in debug only (that's fine: CI runs in debug, and a
/// mismatch crashes the very first test we run); release builds trust the compile-time asserts
/// on both sides.
void assertFfiElementAbi({int expectedSize = _ffiElementBytes}) {
  final actualSize = sizeOf<FfiElement>();
  assert(
    actualSize == expectedSize,
    'FfiElement ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize. '
    'Struct layout has drifted between sides — all render calls would read garbage.',
  );
}

/// Guard that the Dart-side Struct layout for [FfiRectElement] matches the wire contract. Called
/// from `createExportBackend`.
void assertFfiRectElementAbi({int expectedSize = _ffiRectElementBytes}) {
  final actualSize = sizeOf<FfiRectElement>();
  assert(
    actualSize == expectedSize,
    'FfiRectElement ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize. '
    'Struct layout has drifted between sides — all export_image calls would read garbage.',
  );
}
