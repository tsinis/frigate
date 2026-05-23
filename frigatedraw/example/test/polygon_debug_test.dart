// ignore_for_file: prefer-moving-to-variable

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';
import 'package:frigatedraw_example/main.dart';

void main() {
  testWidgets('Debug Polygon taps', (tester) async {
    final file = File('test.jpg');
    final fontFile = File('font.ttf');
    final tempDir = Directory.systemTemp;
    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(
          destination: tempDir,
          fontFile: fontFile,
          imageFile: file,
          tempDir: tempDir,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editorFinder = find.byType(DrawEditor);
    expect(editorFinder, findsOneWidget);

    // Tap the Polygon button and wait for animation to settle.
    await tester.tap(find.text('Polygon'));
    await tester.pumpAndSettle();

    final controller = tester.widget<DrawEditor>(editorFinder).controller;
    expect(controller.pendingVertices, isEmpty, reason: 'No vertices before any tap');

    final topLeft = tester.getTopLeft(find.byType(InteractiveViewer));
    final pendingVertices = controller.pendingVertices;

    await tester.tapAt(topLeft + const Offset(100, 100));
    await tester.pump();
    expect(pendingVertices.length, 1);

    await tester.tapAt(topLeft + const Offset(150, 100));
    await tester.pump();
    expect(pendingVertices.length, 2);

    await tester.tapAt(topLeft + const Offset(125, 150));
    await tester.pump();
    expect(pendingVertices.length, 3);

    await tester.tapAt(topLeft + const Offset(100, 100));
    await tester.pump();
    expect(controller.elements.length, 1);
  });
}
