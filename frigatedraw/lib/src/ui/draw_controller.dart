// ChangeNotifier-backed controller: the whole class is built around mutating an internal
// `_elements` list and notifying listeners. External reads return an unmodifiable view.
// ignore_for_file: avoid-collection-mutating-methods, avoid-ignoring-return-values

import 'dart:collection' show UnmodifiableListView;
import 'dart:typed_data' show Float64x2;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/painting.dart' show Offset, Size;
import 'package:frigatebird/frigatebird.dart';

import '../helpers/draw_element_extension.dart';
import 'draw_tool.dart';

class DrawController extends ChangeNotifier {
  final commandStack = CommandStack();
  final _elements = <DrawElement>[];
  final _pendingVertices = <Float64x2>[];

  UnmodifiableListView<DrawElement>? _cachedElements;
  UnmodifiableListView<Float64x2>? _cachedPendingVertices;

  DrawElement? _creationTemplate;
  int? _selectedIndex;
  Offset? _cursorPosition;
  BackgroundElement? _backgroundTreatment;
  bool _isBackgroundMode = false;

  List<DrawElement> get elements => _cachedElements ??= UnmodifiableListView(_elements);

  int? get selectedIndex => _selectedIndex;

  set selectedIndex(int? value) {
    if (_selectedIndex == value) return;
    _selectedIndex = value;
    notifyListeners();
  }

  DrawElement? get creationTemplate => _creationTemplate;

  set creationTemplate(DrawElement? value) {
    if (_creationTemplate == value && !_isBackgroundMode) return;
    _isBackgroundMode = false;
    _creationTemplate = value;
    _pendingVertices.clear();
    _cursorPosition = null;
    if (value != null) _selectedIndex = null;
    notifyListeners();
  }

  void selectTool(DrawTool? tool, {DrawElement? template}) {
    // The background tool has no drag-template; arm background mode instead. Sizing of the
    // full-image treatment is deferred to [enterBackgroundMode] (the editor supplies the size).
    if (tool == .background && template == null) return _enterBackgroundMode(null);
    creationTemplate = template ?? _defaultTemplateForTool(tool);
  }

  /// The single background-treatment slot (crop rect + background blur + tint). `null` means no
  /// treatment is applied. Replaced live during cropping; persists across tool changes so the
  /// treatment keeps rendering even when a shape tool is active.
  BackgroundElement? get backgroundTreatment => _backgroundTreatment;

  set backgroundTreatment(BackgroundElement? value) {
    if (_backgroundTreatment == value) return;
    _backgroundTreatment = value;
    notifyListeners();
  }

  /// Whether the background tool is armed (shows crop handles + routes gestures to the
  /// background slot). Distinct from [backgroundTreatment] being non-null: the treatment keeps
  /// rendering after the tool is switched away.
  bool get isBackgroundMode => _isBackgroundMode;

  /// Arms the background tool, instantiating a full-image [BackgroundElement] covering
  /// [imageSize] when the slot is still empty. Clears any shape selection / creation template.
  void enterBackgroundMode(Size imageSize) => _enterBackgroundMode(imageSize);

  void _enterBackgroundMode(Size? imageSize) {
    _isBackgroundMode = true;
    _creationTemplate = null;
    _pendingVertices.clear();
    _cursorPosition = null;
    _selectedIndex = null;
    if (imageSize != null) {
      _backgroundTreatment ??= BackgroundElement.cover(
        height: imageSize.height,
        width: imageSize.width,
      );
    }
    notifyListeners();
  }

  /// Disarms the background tool (the treatment, if any, keeps rendering).
  void exitBackgroundMode() {
    if (!_isBackgroundMode) return;
    _isBackgroundMode = false;
    notifyListeners();
  }

  /// Live, non-undoable update of the background treatment (used during a crop drag).
  void updateBackgroundTreatment(BackgroundElement next) {
    _backgroundTreatment = next;
    notifyListeners();
  }

  // Tear-off used as the BackgroundCommand onApply callback, so it must stay a method (not a setter).
  // ignore: use_setters_to_change_properties
  void _handleBackgroundTreatment(BackgroundElement? value) => _backgroundTreatment = value;

  /// Commits a background-treatment change as a single undoable action.
  void commitBackgroundTreatment({
    required BackgroundElement after,
    required BackgroundElement before,
  }) {
    if (before == after) return;
    commandStack.execute(
      BackgroundCommand(after: after, before: before, onApply: _handleBackgroundTreatment),
    );
    notifyListeners();
  }

  static DrawElement? _defaultTemplateForTool(DrawTool? tool) => switch (tool) {
    .rectangle => RectElement.zero,
    .oval => OvalElement.zero,
    .polygon => PolygonElement.zero,
    // The background treatment is not drag-created; `enterBackgroundMode` instantiates a
    // full-image element and the editor edits it via the background-mode gesture path.
    .background || .select || .text || null => null,
  };

  DrawTool? get activeTool {
    if (_isBackgroundMode) return .background;
    final template = _creationTemplate;
    if (template != null) return template.tool;

    return _selectedIndex == null ? null : .select;
  }

  Offset? get cursorPosition => _cursorPosition;
  List<Float64x2> get pendingVertices =>
      _cachedPendingVertices ??= UnmodifiableListView(_pendingVertices);

  void addPendingVertex(Offset point) {
    _pendingVertices.add(Float64x2(point.dx, point.dy));
    notifyListeners();
  }

  void updateCursorPosition(Offset? point) {
    _cursorPosition = point;
    notifyListeners();
  }

  void resetPolygonCreation() {
    _pendingVertices.clear();
    _cursorPosition = null;
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
    if (index.isNegative || index >= _elements.length) return;
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
    if (!index.isNegative && index < _elements.length) _elements.removeAt(index);

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

  bool get canUndo =>
      commandStack.canUndo || (activeTool == .polygon && _pendingVertices.isNotEmpty);

  void undo() {
    if (activeTool == .polygon && _pendingVertices.isNotEmpty) {
      _pendingVertices.removeLast();
      _cursorPosition = null;

      return notifyListeners();
    }
    if (!commandStack.canUndo) return;
    commandStack.undo();
    notifyListeners();
  }

  void redo() {
    if (!commandStack.canRedo) return;
    commandStack.redo();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    _cachedElements = null;
    _cachedPendingVertices = null;
    super.notifyListeners();
  }
}
