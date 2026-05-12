import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart' show internal;

/// Returns true if the provided allocator is compatible with `malloc.nativeFree`.
/// `malloc` and `calloc` are compatible because they both use the standard C library allocator.
@internal
bool isMallocCompatible(Allocator a) => identical(a, malloc) || identical(a, calloc);
