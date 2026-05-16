// ChangeNotifier-backed controller: the whole class is built around mutating an internal
// `_elements` list and notifying listeners. External reads return an unmodifiable view.
// ignore_for_file: avoid-collection-mutating-methods

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:frigatebird/frigatebird.dart';

class DrawController extends ChangeNotifier {
  final commandStack = CommandStack();
  final _elements = <DrawElement>[];
  DrawElement? _creationTemplate;
  int? _selectedIndex;

  List<DrawElement> get elements => List<DrawElement>.unmodifiable(_elements);

  int? get selectedIndex => _selectedIndex;

  set selectedIndex(int? value) {
    if (_selectedIndex == value) return;
    _selectedIndex = value;
    notifyListeners();
  }

  DrawElement? get creationTemplate => _creationTemplate;

  set creationTemplate(DrawElement? value) {
    if (_creationTemplate == value) return;
    _creationTemplate = value;
    notifyListeners();
  }

  DrawElement? get selectedElement {
    final index = _selectedIndex;

    return index == null ? null : _elements.elementAtOrNull(index);
  }

  void addElement(DrawElement element) {
    _elements.add(element);
    _selectedIndex = _elements.length - 1;
    notifyListeners();
  }

  void removeLastElement() {
    if (_elements.isEmpty) return;
    _elements.removeLast(); // ignore: avoid-ignoring-return-values, we don't need it's result.
    notifyListeners();
  }

  void commitAdd(DrawElement element) {
    final index = _elements.length;
    commandStack.execute(
      AddElementCommand(
        _elements,
        element: element,
        index: index,
        onExecute: () => selectedIndex = index,
        onUndo: () => selectedIndex = null,
      ),
    );
    notifyListeners();
  }

  void updateElement(DrawElement element, int index) {
    _elements[index] = element;
    notifyListeners();
  }

  void deleteSelectedElement() {
    final index = _selectedIndex;
    if (index == null) return;

    final element = _elements.elementAtOrNull(index);
    if (element == null) return;

    commandStack.execute(
      DeleteElementCommand(
        _elements,
        element: element,
        index: index,
        onExecute: () => selectedIndex = null,
        onUndo: () => selectedIndex = index,
      ),
    );
    notifyListeners();
  }

  void commitCommand(int index, {required DrawElement after, required DrawElement before}) {
    // Tap-without-drag produces `after === before` because `_handlePointerMove` never fired a
    // `copyWith` to swap the list slot. Pushing a no-op command would silently eat a Ctrl-Z.
    if (identical(before, after)) return;
    commandStack.execute(ElementCommand(_elements, after: after, before: before, index: index));
    notifyListeners();
  }

  void undo() {
    if (!commandStack.canUndo) return;
    commandStack.undo();
    notifyListeners();
  }

  void redo() {
    if (!commandStack.canRedo) return;
    commandStack.redo();
    notifyListeners();
  }
}
