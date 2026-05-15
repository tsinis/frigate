import 'package:flutter/material.dart';
import 'draw_icon_button.dart';

/// An icon button that triggers `DrawController.redo`.
class DrawRedoButton extends DrawIconButton {
  const DrawRedoButton(
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
    super.icon = const Icon(Icons.redo_outlined),
  });

  @override
  VoidCallback? get callback => controller.commandStack.canRedo ? controller.redo : null;
}
