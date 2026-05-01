// `expectLater` returns Future<void> which we always `await`; the lint can't tell that
// awaiting a void Future counts as "using" the return value.
// ignore_for_file: avoid-ignoring-return-values

import 'dart:io';

import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

// ignore: avoid-duplicate-collection-elements, PNG magic literally has 0x0A twice.
const _pngSignature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

const _jpegStartOfImage = <int>[0xFF, 0xD8];

String _ensureTempFileAbsent(String name) {
  final path = '${Directory.systemTemp.path}/$name';
  final file = File(path);
  if (file.existsSync()) file.deleteSync();

  return path;
}

void main() {
  final cwd = Directory.current.path;
  final assetsDir = cwd.endsWith('frigatebird')
      ? '$cwd/test/assets'
      : '$cwd/frigatebird/test/assets';
  final imagePath = '$assetsDir/paint.jpg';
  final fontPath = '$assetsDir/RobotoMono-VariableFont_wght.ttf';

  group(RenderImage, () {
    test('writes a JPEG with a single text overlay', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_text.jpg');

      const text = TextElement(
        fillColor: FfiColor(0xFF_FF_00_00),
        fontSize: 40,
        text: 'Frigate',
        x: 50,
        y: 250,
      );
      await RenderImage.run(
        elements: [text],
        fontPath: fontPath,
        imagePath: imagePath,
        outputPath: outPath,
      );

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue, reason: 'output file created');
      final prefix = outFile.readAsBytesSync().take(_jpegStartOfImage.length).toList();
      expect(prefix, _jpegStartOfImage, reason: 'JPEG Start-Of-Image marker');
      outFile.deleteSync();
    });

    test('writes a PNG with a mixed rectangle + text list', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_mixed.png');

      const rect = RectElement(
        height: 200,
        outlineColor: FfiColor(0xFF_00_FF_00),
        outlineThickness: 8,
        width: 300,
        x: 100,
        y: 100,
      );
      const text = TextElement(
        fillColor: FfiColor(0xFF_FF_FF_FF),
        fontSize: 50,
        text: 'Hi',
        x: 150,
        y: 250,
      );
      await RenderImage.run(
        elements: [rect, text],
        fontPath: fontPath,
        imagePath: imagePath,
        outputPath: outPath,
      );

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue, reason: 'output file created');
      final prefix = outFile.readAsBytesSync().take(_pngSignature.length).toList();
      expect(prefix, _pngSignature, reason: 'PNG magic signature');
      outFile.deleteSync();
    });

    test('rectangle-only list does not require a fontPath', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_rect_only.jpg');

      const rect = RectElement(
        height: 100,
        outlineColor: FfiColor(0xFF_FF_00_00),
        outlineThickness: 4,
        width: 100,
        x: 10,
        y: 10,
      );
      await RenderImage.run(elements: [rect], imagePath: imagePath, outputPath: outPath);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue, reason: 'rect-only output file created');
      outFile.deleteSync();
    });

    test('empty element list still produces a valid file', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_empty.jpg');

      await RenderImage.run(elements: const [], imagePath: imagePath, outputPath: outPath);

      final outFile = File(outPath);
      expect(outFile.existsSync(), isTrue, reason: 'empty-overlay output file created');
      outFile.deleteSync();
    });

    test('throws RenderException(decode) for a missing source image', () async {
      const text = TextElement(text: 'x', x: 0, y: 0);
      final future = RenderImage.run(
        elements: [text],
        fontPath: fontPath,
        imagePath: '/does/not/exist.jpg',
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
        elements: [rect],
        imagePath: imagePath,
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
        elements: [text],
        fontPath: '/definitely/not/a/font.ttf',
        imagePath: imagePath,
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
        elements: [text],
        fontPath: imagePath,
        imagePath: imagePath,
        outputPath: '${Directory.systemTemp.path}/nope.jpg',
      );
      await expectLater(
        future,
        throwsA(isA<RenderException>().having((e) => e.code, 'code', FfiErrorCode.font)),
      );
    });

    test('max quality clamps to itself (release-mode path)', () async {
      final outPath = _ensureTempFileAbsent('frigate_render_clamp.jpg');

      const rect = RectElement(
        height: 50,
        outlineColor: FfiColor(0xFF_FF_FF_FF),
        width: 50,
        x: 5,
        y: 5,
      );
      await RenderImage.run(
        elements: [rect],
        imagePath: imagePath,
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
