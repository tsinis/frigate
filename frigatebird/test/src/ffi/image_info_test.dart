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
        fail('required test fixtures missing: ${fixtureDir.absolute.path}');
      }

      for (int tag = 1; tag <= 8; tag += 1) {
        final path = '${fixtureDir.path}/exif_$tag.jpg';
        final info = ImageInformation.probeSync(path);

        expect(info.orientation, equals(ExifOrientation.fromWire(tag)));

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

  group('ImageInformation enum fallbacks and toString', () {
    test(
      'ImageFormat.fromWire unknown fallback',
      () => expect(ImageFormat.fromWire(999), equals(ImageFormat.unknown)),
    );

    test('ImageFormat.fromWire maps all known wire values', () {
      expect(ImageFormat.fromWire(0), ImageFormat.png);
      expect(ImageFormat.fromWire(1), ImageFormat.jpg);
      expect(ImageFormat.fromWire(255), ImageFormat.unknown);
    });

    test(
      'ExifOrientation.fromWire unknown fallback',
      () => expect(ExifOrientation.fromWire(999), equals(ExifOrientation.normal)),
    );

    test('ExifOrientation.fromWire maps all known wire values', () {
      expect(ExifOrientation.fromWire(1), ExifOrientation.normal);
      expect(ExifOrientation.fromWire(2), ExifOrientation.flipH);
      expect(ExifOrientation.fromWire(3), ExifOrientation.rotate180);
      expect(ExifOrientation.fromWire(4), ExifOrientation.flipV);
      expect(ExifOrientation.fromWire(5), ExifOrientation.transpose);
      expect(ExifOrientation.fromWire(6), ExifOrientation.rotate90);
      expect(ExifOrientation.fromWire(7), ExifOrientation.transverse);
      expect(ExifOrientation.fromWire(8), ExifOrientation.rotate270);
    });

    test('ExifOrientation.fromWire returns normal for zero', () {
      expect(ExifOrientation.fromWire(0), ExifOrientation.normal);
    });

    test('toString formats correctly', () {
      final info = ImageInformation.from(
        format: .jpg,
        height: 200,
        orientation: .rotate90,
        width: 100,
      );
      expect(
        info.toString(),
        equals(
          'ImageInformation(width: 100, height: 200, format: ImageFormat.jpg, orientation: ExifOrientation.rotate90)',
        ),
      );
    });

    test('equality and hashCode work as expected', () {
      final firstInfo = ImageInformation.from(
        format: .jpg,
        height: 200,
        orientation: .rotate90,
        width: 100,
      );
      final secondInfo = ImageInformation.from(
        format: .jpg,
        height: 200,
        orientation: .rotate90,
        width: 100,
      );
      final thirdInfo = ImageInformation.from(
        format: .png,
        height: 200,
        orientation: .rotate90,
        width: 100,
      );

      expect(firstInfo, equals(secondInfo));
      expect(firstInfo.hashCode, equals(secondInfo.hashCode));
      expect(firstInfo, isNot(equals(thirdInfo)));
      expect(firstInfo.hashCode, isNot(equals(thirdInfo.hashCode)));
    });
  });

  group('ImageInfoException', () {
    test('toString contains code and message', () {
      // Wire code 10 is 'unknown' (out of the 0–9 known range); wire code 9 is 'truncated'.
      const ex = ImageInfoException(codeWire: 10, message: 'some error');
      expect(ex.toString(), contains('unknown'));
      expect(ex.toString(), contains('some error'));
    });
  });
}
