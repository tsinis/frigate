// ignore_for_file: prefer-correct-identifier-length, prefer-moving-to-variable

import 'dart:io';

import 'package:frigatebird/src/ffi/image_info.dart';
import 'package:frigatebird/src/ffi/image_info_exception.dart';
import 'package:test/test.dart';

void main() {
  group('ImageInformation.probeSync', () {
    test('throws ImageInfoException for non-existent file', () {
      expect(
        () => ImageInformation.probeSync('definitely_not_here.jpg'),
        throwsA(
          isA<ImageInfoException>().having(
            (e) => e.message,
            'message',
            contains('Failed to open image for info'),
          ),
        ),
      );
    });

    test('reads info from generated fixtures (if they exist)', () {
      // We know where we generated them in Phase 2.
      // But in Dart test they might be relative to the package root.
      final fixtureDir = Directory('rust/tests/fixtures/orientation');
      if (!fixtureDir.existsSync()) {
        fail('required test fixtures missing: rust/tests/fixtures/orientation');
      }

      for (int tag = 1; tag <= 8; tag += 1) {
        final path = '${fixtureDir.path}/exif_$tag.jpg';
        final info = ImageInformation.probeSync(path);

        expect(info.orientation, equals(tag));

        if (tag <= 4) {
          expect(info.width, equals(128));
          expect(info.height, equals(64));
        } else {
          expect(info.width, equals(64));
          expect(info.height, equals(128));
        }
      }
    });
  });

  group('ImageInfoException', () {
    test('toString contains code and message', () {
      const ex = ImageInfoException(code: 42, message: 'some error');
      expect(ex.toString(), contains('42'));
      expect(ex.toString(), contains('some error'));
    });
  });
}
