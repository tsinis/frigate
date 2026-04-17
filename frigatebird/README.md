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

## Rust Toolchain Notes

The build hook uses `native_toolchain_rust`, which invokes Rust through `rustup run ... cargo build`.
That means Homebrew Rust is not the preferred source of truth for this package's native builds.

If an iOS simulator build fails with `can't find crate for 'std'` even though the target appears in
`rustup target list --installed`, treat that as a broken or incomplete rustup toolchain install for
the pinned version in `rust-toolchain.toml`, not as a normal Flutter cache issue.

<!-- keep specific version in sync with rust/rust-toolchain.toml + hook/build.dart, for example: -->
```sh
export PATH="$HOME/.cargo/bin:$PATH"
rustup toolchain install 1.94.1
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios --toolchain 1.94.1-aarch64-apple-darwin
rm -rf frigatebird/rust/target
```
