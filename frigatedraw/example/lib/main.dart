import 'package:flutter/material.dart';
import 'drawing_screen.dart';

void main() => runApp(const DrawingApp());

class DrawingApp extends StatelessWidget {
  const DrawingApp({super.key});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: const DrawingScreen(), theme: ThemeData.dark(useMaterial3: true));
}
