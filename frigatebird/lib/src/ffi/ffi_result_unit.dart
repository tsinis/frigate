import 'ffi_error.dart';

/// Dart-side representation of a Rust `Result<(), FfiError>`.
sealed class FfiResultUnit {
  const FfiResultUnit();
}

final class OkUnit extends FfiResultUnit {
  const OkUnit();
}

final class ErrUnit extends FfiResultUnit {
  const ErrUnit(this.code, this.message);

  final FfiErrorCode code;
  final String message;
}
