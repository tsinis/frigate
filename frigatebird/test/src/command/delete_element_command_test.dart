import 'package:frigatebird/src/command/delete_element_command.dart';
import 'package:frigatebird/src/model/draw_element.dart';
import 'package:frigatebird/src/model/ffi_color.dart';
import 'package:test/test.dart';

void main() => group(DeleteElementCommand, () {
  final elements = <DrawElement>[];
  const firstElement = RectElement(
    height: 10,
    outlineColor: FfiColor(0xFFFF0000),
    width: 10,
    x: 0,
    y: 0,
  );
  const lastElement = RectElement(
    height: 10,
    outlineColor: FfiColor(0xFF00FF00),
    width: 10,
    x: 20,
    y: 20,
  );

  setUp(
    () => elements
      ..clear() // Dart 3.8 formatting.
      ..addAll([firstElement, lastElement]),
  );

  test('execute removes the element at index', () {
    DeleteElementCommand(elements, element: firstElement, index: 0).execute();
    expect(elements.singleOrNull, lastElement);
  });

  test('undo restores the element at original index', () {
    DeleteElementCommand(elements, element: firstElement, index: 0)
      ..execute()
      ..undo();
    expect(elements, [firstElement, lastElement]);
  });

  test('works for element in the middle/end', () {
    final command = DeleteElementCommand(elements, element: lastElement, index: 1)..execute();
    expect(elements.singleOrNull, firstElement);
    command.undo();
    expect(elements, [firstElement, lastElement]);
  });
});
