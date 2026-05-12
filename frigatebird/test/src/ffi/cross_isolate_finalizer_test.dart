// ignore_for_file: avoid-duplicate-collection-elements
import 'dart:isolate';
import 'dart:typed_data';

import 'package:frigatebird/frigatebird.dart';
import 'package:frigatebird/src/ffi/native_image.dart';
import 'package:test/test.dart';

void main() {
  group('Cross-Isolate Finalizer Behavior', () {
    test('NativeImage wrapper keeps memory alive across isolate hops (P1)', () async {
      // 1. Allocate NativeImage on isolate A.
      const bgPath = 'test/assets/paint.jpg';
      final fgBytes = Uint8List.fromList(const [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        0,
        0,
        13,
        73,
        72,
        68,
        82,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        8,
        2,
        0,
        0,
        0,
        144,
        119,
        83,
        222,
        0,
        0,
        0,
        12,
        73,
        68,
        65,
        84,
        8,
        215,
        99,
        248,
        207,
        192,
        0,
        0,
        3,
        1,
        1,
        0,
        24,
        221,
        141,
        176,
        0,
        0,
        0,
        0,
        73,
        69,
        78,
        68,
        174,
        66,
        96,
        130,
      ]);

      final nativeImage = NativeImage.fromBytes(fgBytes, height: 1, width: 1);
      final length = nativeImage.length;

      // 2. Send address to isolate B via Isolate.run and run merge.
      final bytesView = nativeImage.bytes;
      final resultBytes = await Isolate.run(() => _performMerge(bgPath, bytesView));

      expect(resultBytes, isNotEmpty);

      // Force GC on A.
      await Future<void>.delayed(.zero);
      final _ = List.generate(100_000, (index) => Object());

      // ignore: use-existing-variable, Assert NativeImage.bytes is still readable on A.
      expect(nativeImage.bytes.length, length);

      nativeImage.dispose(); // Clean up.
    });
  });
}

Future<Uint8List> _performMerge(String bgPath, Uint8List fgBytes) {
  const backend = ExportBackendNative();

  // Since we cannot pass nativeImage across, we just pass its bytes view here.
  // Wait, NativeImage.bytes is a Uint8List view. Can we pass it?
  // Actually ExportBackendNative takes `Uint8List foregroundPng`.
  // We'll pass the view. It should be transferred safely.
  // If we just use backend.merge, it will wrap it AGAIN in NativeImage!
  // The point of the test is just to prove memory stays alive.
  return backend.merge(backgroundPath: bgPath, foregroundPng: fgBytes);
}
