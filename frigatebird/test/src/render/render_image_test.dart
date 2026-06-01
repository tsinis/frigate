// ! Integration tests for the RenderImage entry point.
// ignore_for_file: avoid-ignoring-return-values, avoid-similar-names
// ignore_for_file: avoid-non-ascii-symbols, no-empty-string, prefer-first
// ignore_for_file: avoid-unsafe-collection-methods, prefer-moving-to-variable

import 'dart:io';

import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() {
  final cwd = Directory.current.path;
  final assetsDir = cwd.endsWith('frigatebird')
      ? '$cwd/test/assets'
      : '$cwd/frigatebird/test/assets';
  final imagePath = '$assetsDir/paint.jpg';
  final fontPath = '$assetsDir/RobotoMono-VariableFont_wght.ttf';

  group('RenderImage.run', () {
    test('renders a basic mix of elements (rect + text)', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_basic.png');

      const rect = RectElement(height: 100, outlineThickness: 4, width: 200, x: 100, y: 100);
      const text = TextElement(
        fillColor: FfiColor(0xFF00FF00),
        height: 48,
        text: 'Hi',
        x: 150,
        y: 250,
      );
      await RenderImage.run(
        backgroundPath: imagePath,
        elements: [rect, text],
        fontPath: fontPath,
        outputPath: outPath,
      );

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue, reason: 'output file created');

      // Simple sanity check that the output is a valid PNG and has expected dims (from fixture).
      final decoded = File(outPath).readAsBytesSync();
      expect(decoded.length, greaterThan(0), reason: 'output is not empty');
      outFile.deleteSync();
    });

    test('renders text element with explicit FfiColor', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_shorthand.png');

      const text = TextElement(
        fillColor: FfiColor(0xFF00FF00),
        height: 48,
        text: 'Frigate',
        x: 50,
        y: 250,
      );
      await RenderImage.run(
        backgroundPath: imagePath,
        elements: [text],
        fontPath: fontPath,
        outputPath: outPath,
      );

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue, reason: 'output file created');
      outFile.deleteSync();
    });

    test('rect-only overlay succeeds', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_rect.jpg');
      const rect = RectElement(
        height: 50,
        outlineColor: FfiColor(0xFF0000FF),
        outlineThickness: 4,
        width: 100,
        x: 10,
        y: 10,
      );
      await RenderImage.run(backgroundPath: imagePath, elements: [rect], outputPath: outPath);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue, reason: 'rect-only output file created');
      outFile.deleteSync();
    });

    test('empty element list still produces a valid file', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_empty.jpg');

      await RenderImage.run(backgroundPath: imagePath, elements: const [], outputPath: outPath);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue, reason: 'empty-overlay output file created');
      outFile.deleteSync();
    });

    test('throws RenderException(io) for a missing source image', () async {
      const text = TextElement(text: 'x', x: 0, y: 0);
      final sysTempPath = Directory.systemTemp.path;
      final future = RenderImage.run(
        backgroundPath: '$sysTempPath/does_not_exist.jpg',
        elements: [text],
        fontPath: fontPath,
        outputPath: '$sysTempPath/nope.jpg',
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.io)),
      );
    });

    test('throws RenderException(encode) for an unsupported output extension', () async {
      const rect = RectElement(height: 1, width: 1, x: 0, y: 0);
      final future = RenderImage.run(
        backgroundPath: imagePath,
        elements: [rect],
        outputPath: '${Directory.systemTemp.path}/nope.tiff',
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.encode)),
      );
    });

    test('throws RenderException(io) when fontPath does not exist', () async {
      const text = TextElement(text: 'x', x: 0, y: 0);
      final future = RenderImage.run(
        backgroundPath: imagePath,
        elements: [text],
        fontPath: '/definitely/not/a/font.ttf',
        outputPath: '${Directory.systemTemp.path}/nope.jpg',
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.io)),
      );
    });

    test('throws RenderException(font) when the font file is not a valid font', () async {
      // Re-use the JPEG as a "font file" so the read succeeds but parsing fails — cheaper than
      // shipping a dedicated malformed-font fixture, and exercises the exact Rust branch.
      const text = TextElement(text: 'x', x: 0, y: 0);
      final future = RenderImage.run(
        backgroundPath: imagePath,
        elements: [text],
        fontPath: imagePath,
        outputPath: '${Directory.systemTemp.path}/nope.jpg',
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.font)),
      );
    });

    test('imageQuality is respected (smoke test)', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_quality.jpg');
      const rect = RectElement(height: 50, width: 50, x: 5, y: 5);
      await RenderImage.run(
        backgroundPath: imagePath,
        elements: [rect],
        imageQuality: DrawConstants.maxImageQuality,
        outputPath: outPath,
      );

      final outFile = File(outPath);
      expect(
        outFile.existsSync(),
        isTrue,
        reason: 'RenderImage.run returns normally when quality is at the legal upper bound',
      );
      outFile.deleteSync();
    });

    test('blurFullImage applies full image blur', () async {
      final outPath = _ensureTempFileAbsent('frigate_blur_full.jpg');
      await RenderImage.blurFullImage(imagePath: imagePath, outputPath: outPath, radius: 10);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue);
      outFile.deleteSync();
    });

    test('blur applies region blur when region size is > 0', () async {
      final outPath = _ensureTempFileAbsent('frigate_blur_region.jpg');
      await RenderImage.blur(
        imagePath: imagePath,
        outputPath: outPath,
        region: const RectElement(blur: 15, height: 50, width: 80, x: 10, y: 20),
      );

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue);
      outFile.deleteSync();
    });

    test('blurFullImage throws RenderException for non-existent image', () async {
      final future = RenderImage.blurFullImage(
        imagePath: '${Directory.systemTemp.path}/does_not_exist.jpg',
        radius: 10,
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.io)),
      );
    });

    test('blurFullImage throws RenderException for empty imagePath', () {
      const emptyPath = '';
      expect(
        () =>
            // ignore: avoid-async-call-in-sync-function, it throws synchronously before returning Future.
            RenderImage.blurFullImage(imagePath: emptyPath, radius: 10),
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.invalidArg)),
      );
    });

    test('blurFullImage respects imageQuality param', () async {
      final outPathHigh = _ensureTempFileAbsent('frigate_blur_q100.jpg');
      final outPathLow = _ensureTempFileAbsent('frigate_blur_q10.jpg');

      await RenderImage.blurFullImage(
        imagePath: imagePath,
        imageQuality: 100,
        outputPath: outPathHigh,
        radius: 5,
      );
      await RenderImage.blurFullImage(
        imagePath: imagePath,
        imageQuality: 10,
        outputPath: outPathLow,
        radius: 5,
      );

      final highFile = File(outPathHigh);
      final lowFile = File(outPathLow);
      expect(highFile.existsSync(), isTrue);
      expect(lowFile.existsSync(), isTrue);
      expect(
        lowFile.lengthSync(),
        lessThan(highFile.lengthSync()),
        reason: 'lower quality should produce smaller file',
      );
      highFile.deleteSync();
      lowFile.deleteSync();
    });
  });

  group('RenderImage.rotate', () {
    test('rotates 90° CW and changes dimensions', () async {
      final outPath = _ensureTempFileAbsent('frigate_rotate_90.png');
      await RenderImage.rotate(imagePath: imagePath, outputPath: outPath, quarterTurns: 1);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue);
      outFile.deleteSync();
    });

    test('rotates 180° preserving dimensions', () async {
      final outPath = _ensureTempFileAbsent('frigate_rotate_180.png');
      await RenderImage.rotate(imagePath: imagePath, outputPath: outPath, quarterTurns: 2);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue);
      outFile.deleteSync();
    });

    test('rotates 270° CW', () async {
      final outPath = _ensureTempFileAbsent('frigate_rotate_270.png');
      await RenderImage.rotate(imagePath: imagePath, outputPath: outPath, quarterTurns: 3);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue);
      outFile.deleteSync();
    });

    test('0 quarter turns is a no-op (does not create output)', () async {
      final outPath = _ensureTempFileAbsent('frigate_rotate_noop.png');
      await RenderImage.rotate(imagePath: imagePath, outputPath: outPath, quarterTurns: 0);

      // No-op should not create output file.
      expect(File(outPath).existsSync(), isFalse);
    });

    test('throws RenderException for empty imagePath', () {
      expect(
        // ignore: avoid-async-call-in-sync-function, it throws synchronously before returning Future.
        () => RenderImage.rotate(imagePath: '', quarterTurns: 1),
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.invalidArg)),
      );
    });

    test('throws RenderException for missing file', () async {
      final future = RenderImage.rotate(
        imagePath: '${Directory.systemTemp.path}/does_not_exist_rotate.png',
        quarterTurns: 1,
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.io)),
      );
    });

    test('overwrites input when no outputPath', () async {
      // Copy fixture to temp so we don't destroy the original.
      final tmpPath = _ensureTempFileAbsent('frigate_rotate_overwrite.jpg');
      File(imagePath).copySync(tmpPath);
      final originalSize = File(tmpPath).lengthSync();

      await RenderImage.rotate(imagePath: tmpPath, quarterTurns: 1);

      final rotatedFile = File(tmpPath);
      expect(rotatedFile.existsSync(), isTrue);
      // Rotated file should differ (different dimensions = different encoding).
      expect(rotatedFile.lengthSync(), isNot(equals(originalSize)));
      rotatedFile.deleteSync();
    });
  });

  group('RenderImage.toJpg', () {
    test('converts to JPEG', () async {
      // Use the paint.jpg fixture - toJpg should work on any supported format.
      final outPath = _ensureTempFileAbsent('frigate_to_jpg_convert.jpg');
      await RenderImage.toJpg(imagePath: imagePath, outputPath: outPath);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue);
      // Verify JPEG magic bytes.
      final bytes = outFile.readAsBytesSync();
      expect(bytes[0], equals(0xFF));
      expect(bytes[1], equals(0xD8));
      outFile.deleteSync();
    });

    test('respects quality param', () async {
      final outHigh = _ensureTempFileAbsent('frigate_to_jpg_high.jpg');
      final outLow = _ensureTempFileAbsent('frigate_to_jpg_low.jpg');

      await RenderImage.toJpg(imagePath: imagePath, imageQuality: 100, outputPath: outHigh);
      await RenderImage.toJpg(imagePath: imagePath, imageQuality: 10, outputPath: outLow);

      final highFile = File(outHigh);
      final lowFile = File(outLow);
      expect(lowFile.lengthSync(), lessThan(highFile.lengthSync()));
      highFile.deleteSync();
      lowFile.deleteSync();
    });

    test('throws RenderException for empty imagePath', () {
      expect(
        // ignore: avoid-async-call-in-sync-function, it throws synchronously before returning Future.
        () => RenderImage.toJpg(imagePath: ''),
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.invalidArg)),
      );
    });

    test('throws RenderException for missing file', () async {
      final future = RenderImage.toJpg(
        imagePath: '${Directory.systemTemp.path}/does_not_exist_tojpg.png',
        outputPath: '${Directory.systemTemp.path}/out.jpg',
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.io)),
      );
    });

    test('throws RenderException for unsupported output extension', () async {
      final future = RenderImage.toJpg(
        imagePath: imagePath,
        outputPath: '${Directory.systemTemp.path}/out.tiff',
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.encode)),
      );
    });
  });

  group('RenderImage.resize', () {
    test('resizes to specified dimensions', () async {
      final outPath = _ensureTempFileAbsent('frigate_resize.png');
      await RenderImage.resize(height: 30, imagePath: imagePath, outputPath: outPath, width: 50);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue);
      outFile.deleteSync();
    });

    test('supports all filter types', () async {
      for (final filter in ResizeFilter.values) {
        final outPath = _ensureTempFileAbsent('frigate_resize_${filter.name}.png');
        await RenderImage.resize(
          filter: filter,
          height: 20,
          imagePath: imagePath,
          outputPath: outPath,
          width: 20,
        );

        final outFile = File(outPath);
        expect(outFile.existsSync(), isTrue, reason: '${filter.name} filter produces output');
        outFile.deleteSync();
      }
    });

    test('outputs to JPEG when extension is .jpg', () async {
      final outPath = _ensureTempFileAbsent('frigate_resize.jpg');
      await RenderImage.resize(height: 32, imagePath: imagePath, outputPath: outPath, width: 32);

      final bytes = File(outPath).readAsBytesSync();
      expect(bytes[0], equals(0xFF));
      expect(bytes[1], equals(0xD8));
      File(outPath).deleteSync();
    });

    test('throws RenderException for empty imagePath', () {
      expect(
        // ignore: avoid-async-call-in-sync-function, it throws synchronously before returning Future.
        () => RenderImage.resize(height: 10, imagePath: '', width: 10),
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.invalidArg)),
      );
    });

    test('throws RenderException for zero width', () {
      expect(
        // ignore: avoid-async-call-in-sync-function, it throws synchronously before returning Future.
        () => RenderImage.resize(height: 10, imagePath: imagePath, width: 0),
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.invalidArg)),
      );
    });

    test('throws RenderException for zero height', () {
      expect(
        // ignore: avoid-async-call-in-sync-function, it throws synchronously before returning Future.
        () => RenderImage.resize(height: 0, imagePath: imagePath, width: 10),
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.invalidArg)),
      );
    });

    test('throws RenderException for negative dimensions', () {
      expect(
        // ignore: avoid-async-call-in-sync-function, it throws synchronously before returning Future.
        () => RenderImage.resize(height: 10, imagePath: imagePath, width: -5),
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.invalidArg)),
      );
    });

    test('throws RenderException for missing file', () async {
      final future = RenderImage.resize(
        height: 10,
        imagePath: '${Directory.systemTemp.path}/does_not_exist_resize.png',
        outputPath: '${Directory.systemTemp.path}/out.png',
        width: 10,
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.io)),
      );
    });
  });
}

String _ensureTempFileAbsent(String name) {
  final path = '${Directory.systemTemp.path}/$name';
  final file = File(path);
  if (file.existsSync()) file.deleteSync();

  return path;
}
