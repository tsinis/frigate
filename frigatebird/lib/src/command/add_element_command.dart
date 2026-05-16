// ignore_for_file: avoid-collection-mutating-methods
//
import '../model/draw_element.dart';
import 'command.dart';

/// Command to add a [DrawElement] to a list.
class AddElementCommand extends Command {
  AddElementCommand(
    this._elements, {
    required this.element,
    required this.index,
    this.onExecute,
    this.onUndo,
  });

  final DrawElement element;
  final int index;
  final void Function()? onExecute;

  final void Function()? onUndo;
  final List<DrawElement> _elements;

  @override
  void execute() {
    _elements.insert(index, element);
    onExecute?.call();
  }

  @override
  void undo() {
    _elements.removeAt(index); // ignore: avoid-ignoring-return-values, we don't need it.
    onUndo?.call();
  }
}
