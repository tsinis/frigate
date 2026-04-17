import 'package:frigatebird/src/render/render_exception.dart';
import 'package:test/test.dart';

void main() {
  group(RenderException, () {
    test(
      'all subclasses implement Exception',
      () => expect(const ImageDecodeException(), isA<Exception>(), reason: 'Exception interface'),
    );

    test('toString labels code + description for every known subclass', () {
      for (final entry in _subclassDescriptions.entries) {
        expect(
          entry.key.toString(),
          contains(entry.value),
          reason: 'code ${entry.key.code} toString must mention "${entry.value}"',
        );
      }
    });

    test('each subclass exposes its own wire code', () {
      for (final entry in _codeByType.entries) {
        expect(entry.key.code, entry.value, reason: 'code for ${entry.key.runtimeType}');
      }
    });
  });

  group(RenderException.fromCode, () {
    test('dispatches known codes to specific subtypes', () {
      for (final entry in _subtypeByCode.entries) {
        expect(
          RenderException.fromCode(entry.key),
          isA<RenderException>().having((e) => e.runtimeType, 'runtimeType', entry.value),
          reason: 'code ${entry.key} -> ${entry.value}',
        );
      }
    });

    test(
      'unknown code falls back to UnknownRenderException with the passed code',
      () => expect(
        RenderException.fromCode(1234),
        isA<UnknownRenderException>().having((e) => e.code, 'code', 1234),
      ),
    );
  });
}

const _subclassDescriptions = <RenderException, String>{
  ImageDecodeException(): 'image decode failed',
  FontReadException(): 'font read failed',
  FontParseException(): 'font parse failed',
  TextNotUtf8Exception(): 'text not valid UTF-8',
  PathNotUtf8Exception(): 'path not valid UTF-8',
  ImageWriteException(): 'image write failed',
  NullPointerException(): 'null pointer argument',
  MissingFontException(): 'text element present',
  RustPanicException(): 'Rust panic',
};

const _codeByType = <RenderException, int>{
  ImageDecodeException(): 1,
  FontReadException(): 2,
  FontParseException(): 3,
  TextNotUtf8Exception(): 4,
  PathNotUtf8Exception(): 5,
  ImageWriteException(): 6,
  NullPointerException(): 7,
  MissingFontException(): 8,
  RustPanicException(): 99,
};

const _subtypeByCode = <int, Type>{
  1: ImageDecodeException,
  2: FontReadException,
  3: FontParseException,
  4: TextNotUtf8Exception,
  5: PathNotUtf8Exception,
  6: ImageWriteException,
  7: NullPointerException,
  8: MissingFontException,
  99: RustPanicException,
};
