import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() => group(AddElementCommand, () {
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
      ..addAll([firstElement]),
  );
  test('execute inserts the element at index', () {
    AddElementCommand(elements, element: lastElement, index: 1).execute();
    expect(elements, [firstElement, lastElement]);
  });

  test('undo removes the element at original index', () {
    AddElementCommand(elements, element: lastElement, index: 1)
      ..execute()
      ..undo();
    expect(elements.singleOrNull, firstElement);
  });

  test('works for inserting at the beginning', () {
    final command = AddElementCommand(elements, element: lastElement, index: 0)..execute();
    expect(elements, [lastElement, firstElement]);
    command.undo();
    expect(elements.singleOrNull, firstElement);
  });
});
