// ignore_for_file: enum-constants-ordering, to match the Rust order and values.

/// Discriminator for `FfiElement.elementType`. The numeric [value] is what crosses the FFI
/// boundary; the enum is the nicer Dart-side handle.
///
/// Adding a new variant requires a matching update in Rust's `frigate::element_type` — order and
/// numeric values are part of the wire contract.
enum FfiElementType {
  rectangle(0),
  text(1),
  oval(2);

  const FfiElementType(this.value);

  final int value;
}
