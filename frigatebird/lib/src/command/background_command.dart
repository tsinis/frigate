import '../model/draw_element.dart';
import 'command.dart';

/// Undoable change to the editor's single background-treatment slot.
///
/// Unlike the element commands this does not mutate a list — the background treatment lives in a
/// dedicated controller slot, so the command carries an [onApply] callback that writes the slot.
class BackgroundCommand extends Command {
  BackgroundCommand({required this.after, required this.before, required this.onApply});

  final BackgroundElement? after;
  final BackgroundElement? before;
  final void Function(BackgroundElement? value) onApply;

  @override
  void execute() => onApply(after);

  @override
  void undo() => onApply(before);
}
