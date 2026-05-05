// ignore_for_file: avoid-ignoring-return-values, avoid-async-call-in-sync-function

import 'dart:typed_data';

import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() => group(ExportBackendNative, () {
  test('returns a non-null instance on the native VM', () {
    const backend = ExportBackendNative();
    expect(backend, isA<ExportBackendNative>(), reason: 'should instantiate backend');
  });

  group('merge validation', () {
    const backend = ExportBackendNative();
    const dummyBg = 'not_a_real_file.jpg';
    final emptyFg = Uint8List(0);
    // ignore: avoid-duplicate-collection-elements, it is a binary header
    final validFg = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]); // Fake PNG header.

    test('throws StateError for empty foreground PNG', () async {
      await expectLater(
        () => backend.merge(backgroundPath: dummyBg, foregroundPng: emptyFg),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Missing foreground bytes'),
          ),
        ),
      );
    });

    test('throws StateError for missing background image', () async {
      await expectLater(
        () => backend.merge(backgroundPath: dummyBg, foregroundPng: validFg),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Failed to decode background image'),
          ),
        ),
      );
    });

    test('throws StateError for empty background image path', () async {
      await expectLater(
        // ignore: no-empty-string, intentional for testing empty path
        () => backend.merge(backgroundPath: '', foregroundPng: validFg),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('backgroundPath cannot be empty'),
          ),
        ),
      );
    });
  });
});
