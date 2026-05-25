// ignore_for_file: prefer-static-class
import 'dart:io';
import 'package:flutter/services.dart';

const fontAsset = 'assets/RobotoMono.ttf';
const sampleAsset = 'assets/sample.png';

/// Copies an asset from the bundle to the local disk.
Future<File> copyAssetToDisk(String assetKey, String destPath) async {
  final bytes = await rootBundle.load(assetKey);

  return File(destPath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
}
