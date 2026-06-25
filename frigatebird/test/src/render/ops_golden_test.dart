// Golden tests for rotate, toJpg, and resize ops.
// ignore_for_file: prefer-extracting-function-callbacks, avoid-similar-names
// ignore_for_file: avoid-non-ascii-symbols, avoid-unsafe-collection-methods
// ignore_for_file: prefer-first

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() {
  final cwd = Directory.current.path;
  final assetsDir = cwd.endsWith('frigatebird')
      ? '$cwd/test/assets'
      : '$cwd/frigatebird/test/assets';
  final imagePath = '$assetsDir/paint.jpg';

  group('Rotate golden', () {
    test('rotate 90 CW is deterministic (byte-identical across two runs)', () async {
      final pathAlpha = _tempPath('frigate_rotate_golden_a.png');
      final pathBeta = _tempPath('frigate_rotate_golden_b.png');
      addTearDown(() => _cleanup([pathAlpha, pathBeta]));

      await RenderImage.rotate(imagePath: imagePath, outputPath: pathAlpha, quarterTurns: 1);
      await RenderImage.rotate(imagePath: imagePath, outputPath: pathBeta, quarterTurns: 1);

      expect(
        _hashFile(pathAlpha),
        _hashFile(pathBeta),
        reason: 'Rotate 90 CW must produce byte-identical output across runs.',
      );
    });

    test('rotate 90 CW swaps width and height', () async {
      final outPath = _tempPath('frigate_rotate_dims.png');
      addTearDown(() => _cleanup([outPath]));

      final original = await ImageInformation.probe(imagePath);
      await RenderImage.rotate(imagePath: imagePath, outputPath: outPath, quarterTurns: 1);
      final rotated = await ImageInformation.probe(outPath);

      expect(rotated.width, original.height, reason: 'Width should become original height.');
      expect(rotated.height, original.width, reason: 'Height should become original width.');
    });

    test('rotate 180 preserves dimensions', () async {
      final outPath = _tempPath('frigate_rotate_180_dims.png');
      addTearDown(() => _cleanup([outPath]));

      final original = await ImageInformation.probe(imagePath);
      await RenderImage.rotate(imagePath: imagePath, outputPath: outPath, quarterTurns: 2);
      final rotated = await ImageInformation.probe(outPath);

      expect(rotated.width, original.width, reason: '180 rotation preserves width.');
      expect(rotated.height, original.height, reason: '180 rotation preserves height.');
    });

    test('rotate 270 CW swaps width and height same as 90', () async {
      final outPath = _tempPath('frigate_rotate_270_dims.png');
      addTearDown(() => _cleanup([outPath]));

      final original = await ImageInformation.probe(imagePath);
      await RenderImage.rotate(imagePath: imagePath, outputPath: outPath, quarterTurns: 3);
      final rotated = await ImageInformation.probe(outPath);

      expect(rotated.width, original.height, reason: '270 CW swaps dims like 90.');
      expect(rotated.height, original.width, reason: '270 CW swaps dims like 90.');
    });

    test('rotate 360 (4 quarter turns) is no-op — produces no output', () async {
      final outPath = _tempPath('frigate_rotate_360_noop.png');
      addTearDown(() => _cleanup([outPath]));

      await RenderImage.rotate(imagePath: imagePath, outputPath: outPath, quarterTurns: 4);

      expect(File(outPath).existsSync(), isFalse, reason: 'No-op rotation should skip I/O.');
    });

    test('rotate 90 CW then 270 CW round-trips to original hash', () async {
      final afterCw = _tempPath('frigate_rotate_rt_cw.png');
      final afterCcw = _tempPath('frigate_rotate_rt_ccw.png');
      final originalAsPng = _tempPath('frigate_rotate_rt_orig.png');
      addTearDown(() => _cleanup([afterCw, afterCcw, originalAsPng]));

      // Produce a lossless PNG baseline from the original via a 1:1 resize (since rotate(4) is a no-op).
      final original = await ImageInformation.probe(imagePath);
      await RenderImage.resize(
        height: original.height,
        imagePath: imagePath,
        outputPath: originalAsPng,
        width: original.width,
      );

      await RenderImage.rotate(imagePath: originalAsPng, outputPath: afterCw, quarterTurns: 1);
      await RenderImage.rotate(imagePath: afterCw, outputPath: afterCcw, quarterTurns: 3);

      expect(
        _hashFile(originalAsPng),
        _hashFile(afterCcw),
        reason: 'Rotate 90 CW + 270 CW should produce identity (round-trip).',
      );
    });
  });

  group('toJpg golden', () {
    test('toJpg is deterministic (byte-identical across two runs)', () async {
      final pathAlpha = _tempPath('frigate_tojpg_golden_a.jpg');
      final pathBeta = _tempPath('frigate_tojpg_golden_b.jpg');
      addTearDown(() => _cleanup([pathAlpha, pathBeta]));

      await RenderImage.toJpg(imagePath: imagePath, imageQuality: 80, outputPath: pathAlpha);
      await RenderImage.toJpg(imagePath: imagePath, imageQuality: 80, outputPath: pathBeta);

      expect(
        _hashFile(pathAlpha),
        _hashFile(pathBeta),
        reason: 'toJpg must produce byte-identical output across runs.',
      );
    });

    test('toJpg preserves dimensions', () async {
      final outPath = _tempPath('frigate_tojpg_dims.jpg');
      addTearDown(() => _cleanup([outPath]));

      final original = await ImageInformation.probe(imagePath);
      await RenderImage.toJpg(imagePath: imagePath, outputPath: outPath);
      final converted = await ImageInformation.probe(outPath);

      expect(converted.width, original.width, reason: 'toJpg preserves width.');
      expect(converted.height, original.height, reason: 'toJpg preserves height.');
    });

    test('higher quality produces larger file than lower quality', () async {
      final highPath = _tempPath('frigate_tojpg_q100.jpg');
      final lowPath = _tempPath('frigate_tojpg_q10.jpg');
      addTearDown(() => _cleanup([highPath, lowPath]));

      await RenderImage.toJpg(imagePath: imagePath, imageQuality: 100, outputPath: highPath);
      await RenderImage.toJpg(imagePath: imagePath, imageQuality: 10, outputPath: lowPath);

      final highSize = File(highPath).lengthSync();
      final lowSize = File(lowPath).lengthSync();
      expect(lowSize, lessThan(highSize), reason: 'Lower quality = smaller file.');
    });

    test('toJpg output starts with JPEG magic bytes', () async {
      final outPath = _tempPath('frigate_tojpg_magic.jpg');
      addTearDown(() => _cleanup([outPath]));

      await RenderImage.toJpg(imagePath: imagePath, outputPath: outPath);

      final bytes = File(outPath).readAsBytesSync();
      expect(bytes.length, greaterThan(2));
      // JPEG magic: FF D8.
      expect(bytes[0], 0xFF, reason: 'First byte must be 0xFF (JPEG SOI).');
      expect(bytes[1], 0xD8, reason: 'Second byte must be 0xD8 (JPEG SOI).');
    });
  });

  group('Resize golden', () {
    test('resize is deterministic (byte-identical across two runs)', () async {
      final pathAlpha = _tempPath('frigate_resize_golden_a.png');
      final pathBeta = _tempPath('frigate_resize_golden_b.png');
      addTearDown(() => _cleanup([pathAlpha, pathBeta]));

      await RenderImage.resize(height: 64, imagePath: imagePath, outputPath: pathAlpha, width: 48);
      await RenderImage.resize(height: 64, imagePath: imagePath, outputPath: pathBeta, width: 48);

      expect(
        _hashFile(pathAlpha),
        _hashFile(pathBeta),
        reason: 'Resize must produce byte-identical output across runs.',
      );
    });

    test('resize produces exact requested dimensions', () async {
      final outPath = _tempPath('frigate_resize_exact_dims.png');
      addTearDown(() => _cleanup([outPath]));

      await RenderImage.resize(height: 37, imagePath: imagePath, outputPath: outPath, width: 53);
      final info = await ImageInformation.probe(outPath);

      expect(info.width, 53, reason: 'Output width should match requested.');
      expect(info.height, 37, reason: 'Output height should match requested.');
    });

    test('each filter produces deterministic output', () async {
      final paths = <String>[];
      addTearDown(() => _cleanup(paths));

      for (final filter in ResizeFilter.values) {
        final pathA = _tempPath('frigate_resize_${filter.name}_a.png');
        final pathB = _tempPath('frigate_resize_${filter.name}_b.png');
        paths.addAll([pathA, pathB]);

        await RenderImage.resize(
          filter: filter,
          height: 32,
          imagePath: imagePath,
          outputPath: pathA,
          width: 32,
        );
        await RenderImage.resize(
          filter: filter,
          height: 32,
          imagePath: imagePath,
          outputPath: pathB,
          width: 32,
        );

        expect(_hashFile(pathA), _hashFile(pathB), reason: '${filter.name} must be deterministic.');
      }
    });

    test('different filters produce different output (not all identical)', () async {
      final paths = <String>[];
      addTearDown(() => _cleanup(paths));

      final hashes = <String>{};
      for (final filter in ResizeFilter.values) {
        final path = _tempPath('frigate_resize_diff_${filter.name}.png');
        paths.add(path);

        await RenderImage.resize(
          filter: filter,
          height: 32,
          imagePath: imagePath,
          outputPath: path,
          width: 32,
        );
        hashes.add(_hashFile(path));
      }

      expect(
        hashes.length,
        greaterThan(1),
        reason: 'Different filters should produce at least some different results.',
      );
    });

    test('upscale preserves requested dimensions', () async {
      final outPath = _tempPath('frigate_resize_upscale.png');
      addTearDown(() => _cleanup([outPath]));

      // Source paint.jpg is much larger, but let's request bigger than some reference.
      await RenderImage.resize(height: 800, imagePath: imagePath, outputPath: outPath, width: 1000);
      final info = await ImageInformation.probe(outPath);

      expect(info.width, 1000, reason: 'Upscale width should match.');
      expect(info.height, 800, reason: 'Upscale height should match.');
    });
  });

  group('Compose full-image blur golden', () {
    test('blur is deterministic (byte-identical across two runs)', () async {
      final pathAlpha = _tempPath('frigate_blur_golden_a.jpg');
      final pathBeta = _tempPath('frigate_blur_golden_b.jpg');
      addTearDown(() => _cleanup([pathAlpha, pathBeta]));

      final treatment = await _coverBlur(imagePath, 10);
      await RenderImage.compose(
        backgroundPath: imagePath,
        backgroundTreatment: treatment,
        outputPath: pathAlpha,
      );
      await RenderImage.compose(
        backgroundPath: imagePath,
        backgroundTreatment: treatment,
        outputPath: pathBeta,
      );

      expect(
        _hashFile(pathAlpha),
        _hashFile(pathBeta),
        reason: 'compose must produce byte-identical output across runs.',
      );
    });

    test('blur produces output with same dimensions as input', () async {
      final outPath = _tempPath('frigate_blur_golden_dims.jpg');
      addTearDown(() => _cleanup([outPath]));

      final original = await ImageInformation.probe(imagePath);
      await RenderImage.compose(
        backgroundPath: imagePath,
        backgroundTreatment: await _coverBlur(imagePath, 5),
        outputPath: outPath,
      );
      final blurred = await ImageInformation.probe(outPath);

      expect(blurred.width, original.width, reason: 'Full-image blur preserves width.');
      expect(blurred.height, original.height, reason: 'Full-image blur preserves height.');
    });

    test('blur output differs from original (not a no-op)', () async {
      final outPath = _tempPath('frigate_blur_golden_differs.jpg');
      final origCopy = _tempPath('frigate_blur_golden_orig_copy.jpg');
      addTearDown(() => _cleanup([outPath, origCopy]));

      // Make a copy at same quality for fair comparison.
      await RenderImage.toJpg(imagePath: imagePath, imageQuality: 80, outputPath: origCopy);
      await RenderImage.compose(
        backgroundPath: imagePath,
        backgroundTreatment: await _coverBlur(imagePath, 15),
        imageQuality: 80,
        outputPath: outPath,
      );

      expect(
        _hashFile(outPath),
        isNot(_hashFile(origCopy)),
        reason: 'Blurred image must differ from unblurred.',
      );
    });
  });
}

Future<BackgroundElement> _coverBlur(String imagePath, int radius) async {
  final info = await ImageInformation.probe(imagePath);

  return BackgroundElement.cover(
    height: info.height.toDouble(),
    width: info.width.toDouble(),
  ).copyWith(blur: radius);
}

String _hashFile(String path) => sha256.convert(File(path).readAsBytesSync()).toString();

String _tempPath(String name) {
  final path = '${Directory.systemTemp.path}/$name';
  final file = File(path);
  if (file.existsSync()) file.deleteSync();

  return path;
}

void _cleanup(List<String> paths) {
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}
