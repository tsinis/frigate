# frigatedraw

Flutter widget layer for geometric image annotation.

## Overview

`frigatedraw` provides the Flutter UI for the [frigatedraw workspace](../). It depends on
[frigatebird](../frigatebird/) for the pure Dart core (models, commands, FFI export).

## Widgets

- **`DrawEditor`** — interactive canvas with zoom/pan (via `InteractiveViewer`) and rectangle manipulation (move, resize via 8 handles)
- **`DrawPainter`** — `CustomPainter` that renders rectangle overlays and selection handles
- **`DrawController`** — `ChangeNotifier` managing element state, selection, and undo/redo

## Usage

```dart
import 'package:frigatedraw/frigatedraw.dart';

final controller = DrawController();
controller.addElement(
  const RectElement(height: 100, width: 200, x: 10, y: 20),
);

// In your widget tree:
DrawEditor(
  controller: controller,
  image: const AssetImage('assets/sample.png'),
  imageHeight: 600,
  imageWidth: 800,
);
```

## Extensions

- `DrawElementExtension` — converts `FfiColor` to `dart:ui` `Color`
- `RectElementExtension` — converts `RectElement` to `dart:ui` `Rect`
