// ignore_for_file: avoid-collection-mutating-methods

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'package:frigatebird/frigatebird.dart';

class DrawController extends ChangeNotifier {
  final commandStack = CommandStack();
  final _elements = <DrawElement>[];
  int? _selectedIndex;

  List<DrawElement> get elements => List<DrawElement>.unmodifiable(_elements);

  int? get selectedIndex => _selectedIndex;

  set selectedIndex(int? value) {
    if (_selectedIndex == value) return;
    _selectedIndex = value;
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

  void updateElement(DrawElement element, int index) {
    _elements[index] = element;
    notifyListeners();
  }

  void commitCommand(int index, {required DrawElement after, required DrawElement before}) {
    commandStack.execute(ElementCommand(_elements, after: after, before: before, index: index));
    notifyListeners();
  }

  void undo() {
    commandStack.undo();
    notifyListeners();
  }

  void redo() {
    commandStack.redo();
    notifyListeners();
  }
}
