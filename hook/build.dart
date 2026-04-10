import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await RustBuilder(
      assetName: 'src/bindings.dart',
      cratePath: 'rust',
    ).run(input: input, output: output);
  });
}
