// ignore_for_file: no-empty-string
import 'dart:convert' show utf8;
import 'dart:ffi';

import 'ffi_error.dart';

String decodeFfiMessage(FfiError error, Pointer<Uint8> errorBuf, int errorCap) {
  if (error.messageLen == 0 || errorBuf == nullptr) return '';
  final len = error.messageLen.clamp(0, errorCap);
  final bytes = errorBuf.asTypedList(len);

  return utf8.decode(bytes);
}

FfiErrorCode mapFfiErrorCode(int code) => FfiErrorCode.fromCode(code);
