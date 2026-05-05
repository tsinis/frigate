import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() => group(ExportBackendNative, () {
  test('returns a non-null instance on the native VM', () {
    const backend = ExportBackendNative();
    expect(backend, isA<ExportBackendNative>(), reason: 'should instantiate backend');
  });

  // TODO(tsinis): More complex tests for merge would require a valid background image path
  // and foreground PNG bytes. For now, we just ensure the backend is correctly structured.
});
