import 'dart:io';

import 'package:frigatebird/src/ffi/image_info.dart';
import 'package:test/test.dart';

void main() {
  group('Isolate Behavior', () {
    const imagePath = 'test/assets/paint.jpg';

    test('Concurrent ImageInformation.probe across 10 isolates', () async {
      if (!File(imagePath).existsSync()) {
        fail('fixture missing: $imagePath');
      }

      final futures = <Future<ImageInformation>>[];
      for (int i = 0; i < 10; i += 1) {
        futures.add(ImageInformation.probe(imagePath));
      }

      final results = await Future.wait(futures);

      final isPositive = greaterThan(0);
      for (final info in results) {
        expect(info.width, isPositive);
        expect(info.height, isPositive);
      }
    });

    test('ImageInformation.probe handles non-existent file gracefully', () async {
      // ignore: avoid-ignoring-return-values, description: verifying exception.
      await expectLater(ImageInformation.probe('non_existent.jpg'), throwsException);
    });
  });
}
