import 'dart:ffi';

import 'ffi_arena.dart';
import 'ffi_element.dart';
import 'ffi_error.dart';
import 'image_info_struct.dart';

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
  static const elementBytes = 56;

  /// Expected byte size of [FfiArena]. 3 pointers + 3 size_t.
  static int get arenaBytes => sizeOf<Pointer>() * 3 + sizeOf<Size>() * 3;

  /// Expected byte size of [FfiError].
  static const errorBytes = 4;

  /// Expected byte size of [ImageInfoStruct].
  /// (2 x u32 + 2 x u8 + 2 bytes padding).
  static const imageInfoBytes = 12;

  /// Expected size in bytes for the element payload union in C.
  static const payloadBytes = 48;

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

  /// Assert the union of payloads matches the target wire size.
  static void assertPayload({int expectedSize = payloadBytes}) {
    final actualSize = sizeOf<FfiPayload>();
    assert(
      actualSize == expectedSize,
      'FfiPayload ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize.',
    );
  }

  static void assertImageInfo({int expectedSize = imageInfoBytes}) {
    final actualSize = sizeOf<ImageInfoStruct>();
    assert(
      actualSize == expectedSize,
      'ImageInfoStruct ABI mismatch: Dart sees $actualSize bytes, Rust expects $expectedSize.',
    );
  }
}
