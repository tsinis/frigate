// ignore_for_file: prefer-extracting-function-callbacks
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
  // Use orientation 6 (rotate 90 CW) which swaps width and height.
  final exifRotatedPath = '$assetsDir/paint_orient_6.jpg';
  final fontPath = '$assetsDir/RobotoMono-VariableFont_wght.ttf';

  group('Golden Integration', () {
    test(
      'renders same DrawElement list twice via RenderImage; assert byte-identical output',
      () async {
        final pathAlpha = _tempPath('frigate_golden_alpha.png');
        addTearDown(() {
          if (File(pathAlpha).existsSync()) File(pathAlpha).deleteSync();
        });
        final pathBeta = _tempPath('frigate_golden_beta.png');
        addTearDown(() {
          if (File(pathBeta).existsSync()) File(pathBeta).deleteSync();
        });

        final elements = [
          const RectElement(fillColor: FfiColor(0xFFFF0000), height: 100, width: 200, x: 10, y: 10),
          const TextElement(fontSize: 40, text: 'Deterministic', x: 20, y: 120),
        ];

        await RenderImage.run(
          backgroundPath: imagePath,
          elements: elements,
          fontPath: fontPath,
          outputPath: pathAlpha,
        );

        await RenderImage.run(
          backgroundPath: imagePath,
          elements: elements,
          fontPath: fontPath,
          outputPath: pathBeta,
        );

        final bytesAlpha = File(pathAlpha).readAsBytesSync();
        final bytesBeta = File(pathBeta).readAsBytesSync();

        final hashAlpha = sha256.convert(bytesAlpha).toString();
        final hashBeta = sha256.convert(bytesBeta).toString();

        expect(
          hashAlpha,
          hashBeta,
          reason: 'Consecutive renders with same inputs must be byte-identical',
        );
      },
    );

    test(
      'renders against an EXIF-rotated source image; output dims match ImageInformation.probe',
      () async {
        final baseInfo = await ImageInformation.probe(imagePath);
        final rotatedInfo = await ImageInformation.probe(exifRotatedPath);

        // Verify probe itself swaps width/height for orientation 6.
        expect(
          rotatedInfo.width,
          baseInfo.height,
          reason: 'Probe should swap dimensions for orientation 6',
        );
        expect(
          rotatedInfo.height,
          baseInfo.width,
          reason: 'Probe should swap dimensions for orientation 6',
        );

        final outPathFinal = _tempPath('frigate_exif_test_final.png');
        addTearDown(() {
          if (File(outPathFinal).existsSync()) File(outPathFinal).deleteSync();
        });

        // Now run RenderImage against the rotated fixture.
        await RenderImage.run(
          backgroundPath: exifRotatedPath,
          elements: [],
          outputPath: outPathFinal,
        );

        final outInfo = await ImageInformation.probe(outPathFinal);

        // Output image should have the swapped dimensions baked in.
        expect(outInfo.width, rotatedInfo.width, reason: 'Output should match the oriented width');
        expect(
          outInfo.height,
          rotatedInfo.height,
          reason: 'Output should match the oriented height',
        );
      },
    );
  });
}

String _tempPath(String name) {
  final path = '${Directory.systemTemp.path}/$name';
  final file = File(path);
  if (file.existsSync()) file.deleteSync();

  return path;
}
