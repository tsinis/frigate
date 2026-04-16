import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

Future<void> main(List<String> args) => build(args, _buildRust);

// ignore: prefer-static-class, it's a convention for build hooks to export a top-level function.
Future<void> _buildRust(BuildInput input, BuildOutputBuilder output) => const RustBuilder(
  assetName: 'src/ffi/bindings.dart',
  cratePath: 'rust',
  // TODO(tsinis): run proper build mod.
).run(input: input, output: output);
