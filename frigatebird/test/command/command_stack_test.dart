import 'package:frigatebird/src/command/command_stack.dart';
import 'package:frigatebird/src/command/element_command.dart';
import 'package:frigatebird/src/model/draw_element.dart';
import 'package:test/test.dart';

void main() => group(CommandStack, () {
  late CommandStack stack;
  late List<DrawElement> elements;
  const original = RectElement(height: 50, width: 100, x: 0, y: 0);
  const moved = RectElement(height: 50, width: 100, x: 10, y: 20);

  // ignore: prefer-extracting-function-callbacks, it's just a test.
  setUp(() {
    stack = CommandStack();
    elements = <DrawElement>[original];
  });

  test('starts empty', () {
    expect(stack.canUndo, isFalse);
    expect(stack.canRedo, isFalse);
  });

  test('execute replaces element', () {
    stack.execute(ElementCommand(elements, after: moved, before: original, index: 0));

    expect(stack.canUndo, isTrue);
    expect(stack.canRedo, isFalse);
    expect(elements.firstOrNull, moved);
  });

  test('undo restores previous element', () {
    final cmd = ElementCommand(elements, after: moved, before: original, index: 0);
    stack
      ..execute(cmd)
      ..undo();

    expect(elements.firstOrNull, original);
    expect(stack.canUndo, isFalse);
    expect(stack.canRedo, isTrue);
  });

  test('redo re-applies undone command', () {
    final cmd = ElementCommand(elements, after: moved, before: original, index: 0);
    stack
      ..execute(cmd)
      ..undo()
      ..redo();

    expect(elements.firstOrNull, moved);
    expect(stack.canUndo, isTrue);
    expect(stack.canRedo, isFalse);
  });

  test('new execute clears redo stack', () {
    const second = RectElement(height: 50, width: 100, x: 30, y: 40);
    stack
      ..execute(ElementCommand(elements, after: moved, before: original, index: 0))
      ..undo()
      ..execute(ElementCommand(elements, after: second, before: original, index: 0));

    expect(stack.canRedo, isFalse);
    expect(elements.firstOrNull, second);
  });
});
