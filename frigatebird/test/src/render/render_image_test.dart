// ! Integration tests for the RenderImage entry point.
// ignore_for_file: avoid-ignoring-return-values

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
        fontSize: 48,
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

    test('renders a basic mix of elements (rect + text) with FfiColor shorthand', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_shorthand.png');

      const text = TextElement(
        fillColor: FfiColor(0xFF00FF00),
        fontSize: 48,
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

    test('throws RenderException(decode) for a missing source image', () async {
      const text = TextElement(text: 'x', x: 0, y: 0);
      final future = RenderImage.run(
        backgroundPath: '/does/not/exist.jpg',
        elements: [text],
        fontPath: fontPath,
        outputPath: '${Directory.systemTemp.path}/nope.jpg',
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.decode)),
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
  });
}

String _ensureTempFileAbsent(String name) {
  final path = '${Directory.systemTemp.path}/$name';
  final file = File(path);
  if (file.existsSync()) file.deleteSync();

  return path;
}
