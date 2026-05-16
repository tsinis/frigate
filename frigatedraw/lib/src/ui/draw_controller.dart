// ChangeNotifier-backed controller: the whole class is built around mutating an internal
// `_elements` list and notifying listeners. External reads return an unmodifiable view.
// ignore_for_file: avoid-collection-mutating-methods, avoid-ignoring-return-values

import 'dart:collection' show UnmodifiableListView;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:frigatebird/frigatebird.dart';

class DrawController extends ChangeNotifier {
  final commandStack = CommandStack();
  final _elements = <DrawElement>[];
  DrawElement? _creationTemplate;
  int? _selectedIndex;

  List<DrawElement> get elements => UnmodifiableListView(_elements);

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

  /// Removes an element at [index] without pushing a command to the stack.
  ///
  /// Used primarily for tearing down temporary preview elements. Updates [_selectedIndex]
  /// to remain consistent with the new list size.
  void dropElementAt(int index) {
    if (index < 0 || index >= _elements.length) return;
    _elements.removeAt(index);

    final selected = _selectedIndex;
    if (selected != null) {
      if (selected == index) {
        _selectedIndex = null;
      } else if (selected > index) {
        _selectedIndex = selected - 1;
      }
    }
    notifyListeners();
  }

  /// Removes the temporary preview element and commits it as an undoable action in a single transaction.
  void replacePreviewAndCommit(DrawElement element, int index) {
    if (index >= 0 && index < _elements.length) _elements.removeAt(index);

    final insertIndex = index.clamp(0, _elements.length);
    commandStack.execute(
      AddElementCommand(
        _elements,
        element: element,
        index: insertIndex,
        onExecute: () => selectedIndex = insertIndex,
        onUndo: () => selectedIndex = null,
      ),
    );
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
