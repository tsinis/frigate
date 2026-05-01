import 'dart:ffi';

import 'export_backend_native.dart' show ExportBackendNative;
import 'ffi_arena.dart';
import 'ffi_element.dart';
import 'ffi_error.dart';
import 'ffi_rect_element.dart';
import 'ffi_result_count.dart';
import 'ffi_result_unit.dart';

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
  /// Expected byte size of [FfiElement] as defined by the Rust `#[repr(C, u8)]` layout.
  static const elementBytes = 64;

  /// Expected byte size of [FfiArena]. 3 pointers + 3 size_t.
  static int get arenaBytes => sizeOf<Pointer>() * 3 + sizeOf<Size>() * 3;

  /// Expected byte size of [FfiError].
  static const errorBytes = 4;

  /// Expected byte size of [FfiRectElement]. Mirrors `rust/src/lib.rs` (4 × f64 + 3 × u32 with
  /// 8-byte alignment padding).
  static const rectElementBytes = 48;

  /// Expected byte size of [FfiResultUnitStruct].
  ///
  /// Rust `repr(C, u8)` enum `FfiResultUnit { Ok(()) = 0, Err(FfiError) = 1 }`:
  /// discriminant(1) + implicit_pad(1, align FfiError to 2) + payload_union(4) = **6 bytes**.
  static const resultUnitBytes = 6;

  /// Error buffer capacity allocated by `FfiMarshal.encodeElements` for Rust to write
  /// diagnostic messages into. Single source of truth — Rust docs reference this value too.
  static const errorCapBytes = 256;

  /// Guard that the Dart-side Struct layout for [FfiElement] matches the wire contract.
  static void assertElement({int expectedSize = elementBytes}) {
    final actualSize = sizeOf<FfiElement>();
    assert(
      actualSize == expectedSize,
      'FfiElement ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize.',
    );
  }

  static void assertArena({int? expectedSize}) {
    final actualSize = sizeOf<FfiArena>();
    final targetSize = expectedSize ?? arenaBytes;
    assert(
      actualSize == targetSize,
      'FfiArena ABI mismatch: Dart sees $actualSize bytes, Rust expects $targetSize.',
    );
  }

  static void assertError({int expectedSize = errorBytes}) {
    final actualSize = sizeOf<FfiError>();
    assert(
      actualSize == expectedSize,
      'FfiError ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize.',
    );
  }

  static void assertResultUnit({int expectedSize = resultUnitBytes}) {
    final actualSize = sizeOf<FfiResultUnitStruct>();
    assert(
      actualSize == expectedSize,
      'FfiResultUnitStruct ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize.',
    );
  }

  /// Guard that the Dart-side [FfiResultCountStruct] layout matches Rust.
  /// Called from `RenderImage.run` alongside the other startup layout guards.
  static void assertResultCount({int expectedSize = 8}) {
    final actualSize = sizeOf<FfiResultCountStruct>();
    assert(
      actualSize == expectedSize,
      'FfiResultCountStruct ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize.',
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
