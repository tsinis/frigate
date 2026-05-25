import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../draw_controller.dart';
import 'draw_icon_button.dart';

/// An icon button that triggers an export callback.
///
/// Automatically disabled when the [DrawController] contains no elements.
class DrawExportButton extends DrawIconButton {
  const DrawExportButton(
    super.controller, {
    this._onExport,
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
    super.visualDensity,
    super.icon = const Icon(Icons.save_alt),
    super.tooltip = 'Export',
  });

  /// The callback to be executed when the button is pressed.
  final VoidCallback? _onExport;

  @override
  VoidCallback? get callback => controller.elements.isEmpty ? null : _onExport;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<VoidCallback>.has('onExport', _onExport));
  }
}
