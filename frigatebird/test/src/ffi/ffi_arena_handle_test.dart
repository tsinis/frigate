import 'package:frigatebird/src/ffi/ffi_arena_handle.dart';
import 'package:test/test.dart';

void main() => group(FfiArenaHandle, () {
  test('readErrorMessage throws StateError after free', () {
    final arena = FfiArenaHandle.allocate()..free();
    expect(arena.readErrorMessage, throwsStateError);
  });

  test('free is idempotent', () {
    final arena = FfiArenaHandle.allocate()..free();
    expect(arena.free, returnsNormally);
  });
});
