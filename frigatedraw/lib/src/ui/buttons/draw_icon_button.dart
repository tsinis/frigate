import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../draw_controller.dart';

/// Base class for icon buttons that interact with a [DrawController].
///
/// Inherits from [IconButton] to maintain the expected API surface while
/// providing reactive state management via [ListenableBuilder].
abstract class DrawIconButton extends IconButton {
  const DrawIconButton(
    this.controller, {
    required super.icon,
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
  }) : super(onPressed: null);

  /// Provides access to the [DrawController] for subclasses.
  @protected
  final DrawController controller;

  /// The callback to be executed when the button is pressed.
  ///
  /// Subclasses should return `null` if the button should be disabled.
  @protected
  VoidCallback? get callback;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<DrawController>('controller', controller))
      ..add(ObjectFlagProperty<VoidCallback>.has('callback', callback));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    builder: (_, _) => IconButton(
      alignment: alignment,
      autofocus: autofocus,
      color: color,
      constraints: constraints,
      disabledColor: disabledColor,
      enableFeedback: enableFeedback,
      focusColor: focusColor,
      focusNode: focusNode,
      highlightColor: highlightColor,
      hoverColor: hoverColor,
      icon: icon,
      iconSize: iconSize,
      isSelected: isSelected,
      mouseCursor: mouseCursor,
      onHover: onHover,
      onLongPress: onLongPress,
      onPressed: callback,
      padding: padding,
      selectedIcon: selectedIcon,
      splashColor: splashColor,
      splashRadius: splashRadius,
      statesController: statesController,
      style: style,
      tooltip: tooltip,
      visualDensity: visualDensity,
    ),
    listenable: controller,
  );
}
