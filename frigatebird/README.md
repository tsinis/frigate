# frigatebird

Pure Dart FFI core for geometric image annotation with Rust-powered export.

## Overview

`frigatebird` is the platform-independent core of the [frigatedraw](../frigatedraw/) workspace.
It provides:

- **Domain models** — `DrawElement`, `RectElement`, `FfiColor`, `HandlePosition`
- **Command pattern** — `CommandStack` for undo/redo
- **FFI export backend** — renders rectangle overlays onto images via Rust (native) or WASM (web)
- **Build hook** — auto-compiles the Rust crate via `native_toolchain_rust`

## Usage

```dart
import 'package:frigatebird/frigatebird.dart';

// Create elements
const rect = RectElement(height: 100, width: 200, x: 10, y: 20);

// Export with overlays baked in
final backend = createExportBackend();
await backend.loadImage(imageBytes, height: 600, width: 800);
final jpeg = await backend.export(rects: [rect]);
backend.dispose();
```

## Architecture

- **Zero Flutter dependency** — uses `Isolate.run()` instead of `compute()`
- **Zero-copy export** — `NativeImage` stores bytes in `malloc`'d memory; stable `int address` crosses isolate boundaries
- **Normalized coordinates** — Dart normalizes rects to 0.0-1.0; Rust denormalizes using decoded image dimensions
- **`@pragma('vm:deeply-immutable')`** — element types are shared across isolates by reference, not copied
