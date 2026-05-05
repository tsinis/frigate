// ignore_for_file: no-empty-string
import 'dart:convert' show utf8;
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi_error.dart';

String decodeFfiMessage(FfiError error, Pointer<Uint8> errorBuf, int errorCap) {
  if (error.messageLen == 0 || errorBuf == nullptr) return '';
  final len = error.messageLen.clamp(0, errorCap);
  final bytes = errorBuf.asTypedList(len);

  return utf8.decode(bytes);
}

/// Decodes a null-terminated UTF-8 message from the error buffer.
String decodeFfiMessageFromBuffer(Pointer<Uint8> errorBuf, int errorCap) {
  if (errorBuf == nullptr || errorCap == 0) return '';

  // Pointer<Uint8> cast to Pointer<Utf8> allows using toDartString() which reads until \0.
  return errorBuf.cast<Utf8>().toDartString();
}

FfiErrorCode mapFfiErrorCode(int code) => FfiErrorCode.fromCode(code);
