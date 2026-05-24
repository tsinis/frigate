// ignore_for_file: prefer-static-class, prefer-single-declaration-per-file, prefer-single-widget-per-file, diagnostic_describe_all_properties
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:path_provider_dart/path_provider_dart.dart';

import 'drawing_screen.dart';
import 'utils.dart';

Future<void> main() async {
  final _ = WidgetsFlutterBinding.ensureInitialized();
  final directory = _exportDestination;

  if (directory == null) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Failed to initialize local directories'))),
      ),
    );

    return;
  }

  final tempDir = await Directory.systemTemp.createTemp('frigate_');
  final imageFile = await copyAssetToDisk(sampleAsset, '${tempDir.path}/frigate_bg.png');
  final fontFile = await copyAssetToDisk(fontAsset, '${tempDir.path}/frigate_font.ttf');

  runApp(DrawingApp(directory, fontFile: fontFile, imageFile: imageFile, tempDir: tempDir));
}

Directory? get _exportDestination {
  if (Platform.isIOS || Platform.isAndroid) {
    final documents = getApplicationDocumentsDirectory();

    return Directory('${documents.path}/Frigatedraw');
  }

  final downloads = getDownloadsDirectory();
  if (downloads == null) return null;

  return Directory('${downloads.path}/Frigatedraw');
}

class DrawingApp extends StatelessWidget {
  const DrawingApp(
    this.directory, {
    required this.fontFile,
    required this.imageFile,
    required this.tempDir,
    super.key,
  });

  final Directory directory;
  final File fontFile;
  final File imageFile;
  final Directory tempDir;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: DrawingScreen(
      destination: directory,
      fontFile: fontFile,
      imageFile: imageFile,
      tempDir: tempDir,
    ),
    theme: ThemeData.dark(useMaterial3: true),
  );
}
