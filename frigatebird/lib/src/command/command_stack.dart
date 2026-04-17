// Undo/redo stack — push/pop on internal lists is the entire job of this class.
// ignore_for_file: avoid-collection-mutating-methods

import 'command.dart';

class CommandStack {
  final _undoStack = <Command>[];
  final _redoStack = <Command>[];

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  void execute(Command command) {
    command.execute();
    _undoStack.add(command);
    _redoStack.clear();
  }

  void undo() {
    if (!canUndo) return;
    final command = _undoStack.removeLast()..undo();
    _redoStack.add(command);
  }

  void redo() {
    if (!canRedo) return;
    final command = _redoStack.removeLast()..execute();
    _undoStack.add(command);
  }
}
