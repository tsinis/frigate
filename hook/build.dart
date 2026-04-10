import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async => await build(
  args,
  (input, output) => const RustBuilder(
    assetName: 'src/bindings.dart',
    cratePath: 'rust',
  ).run(input: input, output: output),
);
