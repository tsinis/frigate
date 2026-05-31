import 'package:flutter/material.dart';
import 'draw_icon_button.dart';

/// An icon button that triggers `DrawController.undo`.
class DrawUndoButton extends DrawIconButton {
  const DrawUndoButton(
    super.controller, {
    super.alignment,
    super.autofocus,
    super.color,
    super.constraints,
    super.disabledColor,
    super.enableFeedback,
    super.focusColor,
    super.focusNode,
    super.highlightColor,
    super.hoverColor,
    super.icon = const Icon(Icons.undo_outlined),
    super.iconSize,
    super.isSelected,
    super.key,
    super.mouseCursor,
    super.onHover,
    super.onLongPress,
    super.padding,
    super.selectedIcon,
    super.splashColor,
    super.splashRadius,
    super.statesController,
    super.style,
    super.tooltip,
    super.visualDensity,
  });

  @override
  VoidCallback? get callback => controller.canUndo ? controller.undo : null;
}
