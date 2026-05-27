import 'package:flutter/material.dart';
import 'draw_icon_button.dart';

/// An icon button that deletes the currently selected element via `DrawController`.
class DrawDeleteButton extends DrawIconButton {
  const DrawDeleteButton(
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
    super.icon = const Icon(Icons.delete_outline),
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
  VoidCallback? get callback =>
      controller.selectedIndex == null ? null : controller.deleteSelectedElement;
}
