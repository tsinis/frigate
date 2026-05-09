import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'bindings.dart' as ffi;
import 'ffi_arena.dart';
import 'ffi_element.dart';
import 'ffi_error.dart';
import 'image_info_struct.dart';

/// Runtime guards that the Dart-side `Struct` layouts for the FFI types match the wire
/// contract baked into the Rust crate.
///
/// Class with statics rather than top-level functions so the FFI namespace stays discoverable
/// (`FfiAbi.` autocompletes both checks together) instead of leaking two unrelated-looking
/// names into every file that imports `ffi_abi.dart`.
sealed class FfiAbi {
  /// Single entry point for all ABI stability checks.
  ///
  /// Probes the Rust library at runtime to verify that the byte-size of every shared struct
  /// matches Dart's expectation. This catches cross-language drift (e.g. adding a field in
  /// Rust but forgetting to update the Dart Struct) which would otherwise cause silent memory
  /// corruption or garbage reads.
  ///
  /// No-op in release builds (asserts are stripped).
  static void assertAll() {
    // ignore: avoid-immediately-invoked-functions, standard assert-gated init pattern.
    assert(() {
      final elementSizePtr = calloc<Size>();
      // ignore: avoid-duplicate-initializers, allocating multiple Size pointers is intentional.
      final arenaSizePtr = calloc<Size>();
      // ignore: avoid-duplicate-initializers, allocating multiple Size pointers is intentional.
      final errorSizePtr = calloc<Size>();
      // ignore: avoid-duplicate-initializers, allocating multiple Size pointers is intentional.
      final infoSizePtr = calloc<Size>();
      try {
        ffi.get_abi_sizes(elementSizePtr, arenaSizePtr, errorSizePtr, infoSizePtr);

        _matchSize(sizeOf<FfiElement>(), elementSizePtr.value, 'FfiElement');
        _matchSize(sizeOf<FfiArena>(), arenaSizePtr.value, 'FfiArena');
        _matchSize(sizeOf<FfiError>(), errorSizePtr.value, 'FfiError');
        _matchSize(sizeOf<ImageInfoStruct>(), infoSizePtr.value, 'ImageInfoStruct');
        _matchSize(sizeOf<FfiPayload>(), 48, 'FfiPayload');
      } finally {
        calloc
          ..free(elementSizePtr)
          ..free(arenaSizePtr)
          ..free(errorSizePtr)
          ..free(infoSizePtr);
      }

      return true;
    }(), 'ABI check failed');
  }

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

  static void _matchSize(int dartSize, int rustSize, String name) {
    assert(
      dartSize == rustSize,
      '$name ABI mismatch: Dart sees $dartSize bytes, Rust expects $rustSize.',
    );
  }

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
