import 'dart:typed_data';

import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() => group(ExportBackendNative, () {
  test('returns a non-null instance on the native VM', () {
    final backend = ExportBackendNative();
    expect(backend, isA<ExportBackendNative>(), reason: 'should instantiate backend');
    backend.dispose();
  });

  test('runs the FfiRectElement ABI assert on loadImage', () {
    final backend = ExportBackendNative();
    // The implementation invokes FfiAbi.assertRectElement in loadImage; if the
    // Dart Struct layout drifts from Rust (Cargo build vs Dart sees a different size), the
    // assert fires here with a loud, actionable message instead of corrupting reads later.
    expect(
      () => backend.loadImage(Uint8List(0), height: 0, width: 0),
      returnsNormally,
      reason: 'ABI guard must pass on the host VM',
    );
    backend.dispose();
  });

  test('export() before loadImage throws StateError', () {
    final backend = ExportBackendNative();
    // The native impl validates `loadImage()` was called BEFORE returning the Isolate.run
    // future, so the throw is synchronous — `expect`/`throwsA` is the right matcher.
    // The closure looks like a fire-and-forget async call to the lints, hence the ignore.
    expect(
      // ignore: avoid-async-call-in-sync-function, the throw is sync; no Future is created.
      () => backend.export(rects: const []),
      throwsA(isA<StateError>()),
      reason: 'callers must loadImage() before export()',
    );
    backend.dispose();
  });
});
