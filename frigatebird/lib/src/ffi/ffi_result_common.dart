// ignore_for_file: no-empty-string
import 'dart:convert' show utf8;
import 'dart:ffi';

import 'ffi_error.dart';

/// Decodes a null-terminated UTF-8 message from the error buffer.
String decodeFfiMessageFromBuffer(Pointer<Uint8> errorBuf, int errorCap) {
  if (errorBuf == nullptr || errorCap == 0) return '';

  final bytes = errorBuf.asTypedList(errorCap);
  final nullIndex = bytes.indexOf(0);
  final len = nullIndex == -1 ? errorCap : nullIndex;

  return utf8.decode(bytes.sublist(0, len));
}

FfiErrorCode mapFfiErrorCode(int code) => FfiErrorCode.fromCode(code);
