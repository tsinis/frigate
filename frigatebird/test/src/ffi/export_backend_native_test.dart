import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() => group('createExportBackend', () {
  test('returns a non-null ExportBackend on the native VM', () {
    final backend = createExportBackend();
    expect(backend, isA<ExportBackend>(), reason: 'native factory should return a backend');
    backend.dispose();
  });

  test('runs the FfiRectElement ABI assert without throwing', () {
    // The factory invokes FfiAbi.assertRectElement before constructing the backend; if the
    // Dart Struct layout drifts from Rust (Cargo build vs Dart sees a different size), the
    // assert fires here with a loud, actionable message instead of corrupting reads later.
    expect(createExportBackend, returnsNormally, reason: 'ABI guard must pass on the host VM');
  });

  test('export() before loadImage throws StateError', () {
    final backend = createExportBackend();
    // _NativeExportBackend.export throws BEFORE returning any Future, so this is a sync
    // throw — expect (not expectLater) is the right matcher. The closure looks like an
    // un-awaited async call to the lints, but the throw fires before any Future exists.
    expect(
      // ignore: avoid-async-call-in-sync-function, throw fires before the Future exists.
      () => backend.export(rects: const []),
      throwsA(isA<StateError>()),
      reason: 'callers must loadImage() before export()',
    );
    backend.dispose();
  });
});
