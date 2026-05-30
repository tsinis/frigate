import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show ColorProperty, Widget;
import 'package:frigatebird/frigatebird.dart';
import 'draw_blur_toggle_icon.dart';
import 'draw_icon_button.dart';

/// An icon button that sets the selected element's blur to [_minColor] (default to `0`).
class DrawBlurToggleButton extends DrawIconButton {
  DrawBlurToggleButton(
    super.controller, {
    this._minColor,
    Widget? icon,
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
  }) : super(icon: icon ?? DrawBlurToggleIcon(controller));

  final FfiColor? _minColor;

  @override
  VoidCallback? get callback {
    final index = controller.selectedIndex;
    final selected = controller.selectedElement;
    if (selected == null || index == null || selected.blur == 0) return null;

    return () {
      final snapshot = selected;
      final updated = snapshot.copyWith(blur: 0, fillColor: _minColor);
      controller.updateElement(updated, index);
      final after = controller.elements.elementAtOrNull(index);
      if (after != null) controller.commitCommand(index, after: after, before: snapshot);
    };
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final minColor = _minColor;
    properties.add(ColorProperty('minColor', minColor == null ? null : Color(minColor.argb)));
  }
}
