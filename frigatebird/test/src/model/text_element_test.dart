import 'dart:isolate' show Isolate, ReceivePort, SendPort;

import 'package:frigatebird/src/model/draw_element.dart';
import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

void main() => group(TextElement, () {
  test('default values', () {
    const text = TextElement(text: 'hi', x: 10, y: 20);
    expect(text.text, 'hi', reason: 'text preserved');
    expect(text.fontSize, TextElement.defaultFontSize, reason: 'default font size');
    expect((text.rotation, text.blur), (0, 0), reason: 'int defaults');
    expect(text.fillColor.argb, FfiColor.black.argb, reason: 'default fill color');
  });

  test('copyWith preserves unchanged fields', () {
    const original = TextElement(height: 32, rotation: 15, text: 'hello', x: 10, y: 20);
    final TextElement(:fontSize, :rotation, :text, :x, :y) = original.copyWith(x: 30);
    expect(text, 'hello', reason: 'text untouched');
    expect((x, y), (30.0, 20.0), reason: 'x replaced, y untouched');
    expect((fontSize, rotation), (32.0, 15), reason: 'style untouched');
  });

  test('copyWith changes text', () {
    const original = TextElement(text: 'a', x: 0, y: 0);
    final copied = original.copyWith(text: 'b');
    expect(original.text, 'a', reason: 'original unchanged');
    expect(copied.text, 'b', reason: 'copy updated');
  });

  test('is deeply immutable (copyWith produces distinct instances)', () {
    const text = TextElement(text: 'hi', x: 0, y: 0);
    final moved = text.copyWith(x: 5);
    expect(text.x, isZero, reason: 'original unchanged');
    expect(moved.x, 5, reason: 'copy has new x');
  });

  test('no copy in isolates outside of the list', () async {
    const element = TextElement(height: 32, text: 'hi', x: 10, y: 20);

    final receivePort = ReceivePort();
    final result = await Isolate.spawn(
      _sendElementIdentity,
      _TextElementTest(payload: element, sendPort: receivePort.sendPort),
    );
    expect(result, isA<Isolate>(), reason: 'spawn returned an Isolate handle');
    expect(
      await receivePort.first,
      identityHashCode(element),
      reason: 'same identity across isolate boundary',
    );
    receivePort.close();
  });

  test('no copy in isolates inside of the list', () async {
    const element = TextElement(height: 32, text: 'hi', x: 10, y: 20);
    final list = [element];

    final receivePort = ReceivePort();
    final result = await Isolate.spawn(
      _sendElementIdentity,
      _TextElementTest(payload: list, sendPort: receivePort.sendPort),
    );
    expect(result, isA<Isolate>(), reason: 'spawn returned an Isolate handle');
    expect(
      await receivePort.first,
      identityHashCode(element),
      reason: 'first list element has same identity across isolate boundary',
    );
    receivePort.close();
  });

  test('toString mentions text content and type', () {
    const text = TextElement(text: 'hi', x: 0, y: 0);
    final rendered = text.toString();
    expect(rendered, contains('TextElement'), reason: 'type name');
    expect(rendered, contains('hi'), reason: 'text content');
  });
});

/// Strongly-typed isolate message — keeps the spawn callback free of unsafe casts. Lives in this
/// file to colocate with the only test that uses it.
final class _TextElementTest {
  const _TextElementTest({required this.payload, required this.sendPort});

  /// Payload deliberately accepts either a [TextElement] or a `List<TextElement>` so a single
  /// isolate-helper covers both transfer-shape tests.
  // ignore: no-object-declaration, see doc comment above.
  final Object? payload;
  final SendPort sendPort;
}

void _sendElementIdentity(_TextElementTest args) {
  final payload = args.payload;
  // ignore: avoid-unsafe-collection-methods, isNotEmpty guards .first.
  final identityTarget = payload is List<Object?> && payload.isNotEmpty ? payload.first : payload;
  args.sendPort.send(identityHashCode(identityTarget));
}
