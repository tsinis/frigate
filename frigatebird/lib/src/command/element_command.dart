// Command-pattern execute/undo intentionally mutate the controller's `_elements` list in
// place — that's the contract this class implements.
// ignore_for_file: avoid-collection-mutating-methods

import '../model/draw_element.dart';
import 'command.dart';

class ElementCommand extends Command {
  ElementCommand(this._elements, {required this.after, required this.before, required this.index});

  final DrawElement after;
  final DrawElement before;
  final int index;

  final List<DrawElement> _elements;

  @override
  void execute() => _elements[index] = after;

  @override
  void undo() => _elements[index] = before;
}
