// INTERNAL TEST-ONLY binding — not part of the public API.
//
// `ffi_echo_element` round-trips a single [FfiElement] pointer through Rust unchanged.
// Its only purpose is to verify in tests that the Dart struct layout matches the Rust
// `#[repr(C, u8)]` layout without any data transformation. It must never be called in
// production code — the Rust symbol is always compiled into the .dylib but handing it
// a stale pointer in production would be UB.
// ignore_for_file: non_constant_identifier_names, prefer-typedefs-for-callbacks
@DefaultAsset('package:frigatebird/src/ffi/bindings.dart')
library;

import 'dart:ffi';

import 'ffi_element.dart';

/// Round-trips an [FfiElement] through Rust unchanged.
///
/// `isLeaf: true` — O(1) identity function, never calls back into Dart.
@Native<Pointer<FfiElement> Function(Pointer<FfiElement>)>(isLeaf: true)
external Pointer<FfiElement> ffi_echo_element(Pointer<FfiElement> ptr);
