import 'package:frigatebird/src/ffi/ffi_error.dart';
import 'package:frigatebird/src/render/render_exception.dart';
import 'package:test/test.dart';

void main() {
  group(RenderException, () {
    test(
      'implements Exception',
      () => expect(const RenderException(.decode), isA<Exception>(), reason: 'Exception interface'),
    );

    test(
      'toString includes description from FfiErrorCode',
      () => expect(
        const RenderException(.decode).toString(),
        contains('image decode failed'),
        reason: 'description comes from FfiErrorCode.description',
      ),
    );

    test(
      'toString includes Rust message when non-empty',
      () => expect(
        const RenderException(.io, 'file not found').toString(),
        contains('file not found'),
        reason: 'Rust arena message is included',
      ),
    );

    test('toString omits colon when message is empty', () {
      final str = const RenderException(.font).toString();
      expect(str, isNot(contains(': ')), reason: 'no colon when message is empty');
    });

    test(
      'code is accessible',
      () => expect(
        const RenderException(.utf8).code,
        FfiErrorCode.utf8,
        reason: 'code field is preserved',
      ),
    );
  });

  group(FfiErrorCode, () {
    test(
      'fromCode(0) returns success',
      () => expect(FfiErrorCode.fromCode(0), FfiErrorCode.success),
    );

    test(
      'fromCode returns panic for out-of-range code',
      () => expect(
        FfiErrorCode.fromCode(999),
        FfiErrorCode.panic,
        reason: 'unknown code falls back to panic',
      ),
    );

    test('fromCode round-trips all known codes', () {
      for (final code in FfiErrorCode.values) {
        expect(
          FfiErrorCode.fromCode(code.index),
          code,
          reason: 'fromCode(${code.index}) should return $code',
        );
      }
    });

    test('description is non-empty for every value', () {
      for (final code in FfiErrorCode.values) {
        expect(code.description, isNotEmpty, reason: '$code.description must not be empty');
      }
    });
  });
}
