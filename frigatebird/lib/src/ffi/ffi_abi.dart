import 'dart:ffi';

import 'export_backend_native.dart' show ExportBackendNative;
import 'ffi_arena.dart';
import 'ffi_element.dart';
import 'ffi_error.dart';
import 'ffi_rect_element.dart';
import 'ffi_result.dart';

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

  /// Expected byte size of [FfiArena].
  static const arenaBytes = 48;

  /// Expected byte size of [FfiError].
  static const errorBytes = 4;

  /// Expected byte size of [FfiResultUnit].
  static const resultUnitBytes = 6;

  /// Expected byte size of [FfiRectElement].
  // Both arenaBytes and rectElementBytes equal 48 by coincidence — different structs.
  // ignore: avoid-duplicate-constant-values
  static const rectElementBytes = 48;

  /// Guard that the Dart-side Struct layout for [FfiElement] matches the wire contract.
  static void assertElement({int expectedSize = elementBytes}) {
    final actualSize = sizeOf<FfiElement>();
    assert(
      actualSize == expectedSize,
      'FfiElement ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize.',
    );
  }

  static void assertArena({int expectedSize = arenaBytes}) {
    final actualSize = sizeOf<FfiArena>();
    assert(
      actualSize == expectedSize,
      'FfiArena ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize.',
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
    final actualSize = sizeOf<FfiResultUnit>();
    assert(
      actualSize == expectedSize,
      'FfiResultUnit ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize.',
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
