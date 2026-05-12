# frigatebird

Pure Dart FFI core for geometric image annotation with Rust-powered export.

## Overview

`frigatebird` is the platform-independent core of the [frigatedraw](../frigatedraw/) workspace.
It provides:

- **Domain models** — `DrawElement`, `RectElement`, `FfiColor`, `HandlePosition`
- **Command pattern** — `CommandStack` for undo/redo
- **FFI export backend** — renders rectangle overlays onto images via Rust (native)
- **Build hook** — auto-compiles the Rust crate via `native_toolchain_rust`

## Usage

```dart
import 'package:frigatebird/frigatebird.dart';

// Create elements
const rect = RectElement(height: 100, width: 200, x: 10, y: 20);

// Export with overlays baked in
final backend = ExportBackendNative();
backend.loadImage(imageBytes, height: 600, width: 800);
final jpeg = await backend.export(rects: [rect]);
backend.dispose();
```

## Architecture

- **Zero Flutter dependency** — uses `Isolate.run()` instead of `compute()`
- **Zero-copy export** — `NativeImage` stores bytes in `malloc`'d memory; stable `int address` crosses isolate boundaries
- **Pixel coordinates** — coordinates cross the FFI boundary as pixel values end-to-end; no normalization occurs in Dart or Rust
- **`@pragma('vm:deeply-immutable')`** — element types are shared across isolates by reference, not copied

## Rust Toolchain Notes

The build hook uses `native_toolchain_rust`, which invokes Rust through `rustup run ... cargo build`.
That means Homebrew Rust is not the preferred source of truth for this package's native builds.

If an iOS simulator build fails with `can't find crate for 'std'` even though the target appears in
`rustup target list --installed`, treat that as a broken or incomplete rustup toolchain install for
the pinned version in `rust-toolchain.toml`, not as a normal Flutter cache issue.

<!-- keep specific version in sync with rust/rust-toolchain.toml + hook/build.dart, for example: -->

## Testing

To run tests in `frigatebird/`, you must enable FFI debug features and symbols. This is handled via the `NIX_FRIGATE_DEBUG_FFI` environment variable, which is passed through the hermetic build hook:

```bash
NIX_FRIGATE_DEBUG_FFI=true fvm dart test
```

The build hook detects this variable and compiles the Rust crate with `ffi-echo` and `ffi-test-helpers` enabled, providing the necessary native symbols.

The Rust backend in `frigatebird/rust` follows a "Maximum Strictness" philosophy for FFI safety and performance:

- **`safer_ffi` Migration** — The FFI boundary uses `safer_ffi` to eliminate manual `unsafe` blocks while maintaining perfect C ABI compatibility with Dart.
- **Miri Safety Audit** — All Rust code is verified for Undefined Behavior (UB) using `cargo miri`.
- **Comprehensive Linting** — Strict Clippy groups (`all`, `pedantic`, `cargo`) and targeted FFI lints are enforced.
- **Advanced Auditing** — Includes `cargo-deny` (license/security), `cargo-audit` (vulnerabilities), `cargo-mutants` (test quality), and `cargo-llvm-lines` (binary size optimization).
- **Fuzzing & ASan** — FFI entry points are stress-tested with `cargo-fuzz` and monitored via AddressSanitizer.
