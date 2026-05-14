// INTERNAL TEST-ONLY bindings — not part of the public API.
//
// These helpers are used to verify ABI stability, error handling, and memory
// accounting in tests. They must never be called in production code.
// ignore_for_file: non_constant_identifier_names, prefer-typedefs-for-callbacks, prefer-named-parameters
@DefaultAsset('package:frigatebird/src/ffi/bindings.dart')
library;

import 'dart:ffi';

import 'package:meta/meta.dart' show visibleForTesting;

import 'ffi_arena.dart';
import 'ffi_element.dart';

/// Round-trips an [FfiElement] through Rust unchanged.
///
/// `isLeaf: true` — O(1) identity function, never calls back into Dart.
@visibleForTesting
@Native<Pointer<FfiElement> Function(Pointer<FfiElement>)>(isLeaf: true)
external Pointer<FfiElement> ffi_echo_element(Pointer<FfiElement> ptr);

/// Test helper to force an error.
///
/// Writes [msg] to [arena].errorBuf and returns [code].
@visibleForTesting
@Native<Uint8 Function(Uint8, Pointer<Uint8>, Size, Pointer<FfiArena>)>(isLeaf: true)
external int ffi_force_error(int code, Pointer<Uint8> msg, int len, Pointer<FfiArena> arena);

/// Test helper to zero an element.
@visibleForTesting
@Native<Void Function(Pointer<FfiElement>)>(isLeaf: true)
external void ffi_zero_element(Pointer<FfiElement> out);

/// Test helper to fill an element with 0xAA pattern.
@visibleForTesting
@Native<Void Function(Pointer<FfiElement>)>(isLeaf: true)
external void ffi_fill_element_0xAA(Pointer<FfiElement> out);
