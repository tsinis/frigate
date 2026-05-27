import 'package:flutter/material.dart';
import '../draw_controller.dart';
import 'draw_blur_toggle_button.dart';

/// Animated icon for the [DrawBlurToggleButton].
class DrawBlurToggleIcon extends StatelessWidget {
  const DrawBlurToggleIcon(
    this._controller, {
    this._duration = kThemeChangeDuration,
    this._layoutBuilder = AnimatedSwitcher.defaultLayoutBuilder,
    this._minValue = 0,
    this._reverseDuration,
    this._switchInCurve = Curves.linear,
    this._switchOutCurve = Curves.linear,
    this._transitionBuilder = AnimatedSwitcher.defaultTransitionBuilder,
    super.key,
  });

  final DrawController _controller;
  final int _minValue;
  final Duration _duration;
  final Duration? _reverseDuration;
  final Curve _switchInCurve;
  final Curve _switchOutCurve;
  final AnimatedSwitcherTransitionBuilder _transitionBuilder;
  final AnimatedSwitcherLayoutBuilder _layoutBuilder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    builder: (bc, _) {
      final selected = _controller.selectedElement;
      final isBlurOn = selected == null ? null : selected.blur > _minValue;
      final iconData = switch (isBlurOn) {
        true => Icons.blur_on,
        false => Icons.blur_off,
        null => Icons.blur_circular,
      };

      return AnimatedSwitcher(
        duration: _duration,
        layoutBuilder: _layoutBuilder,
        reverseDuration: _reverseDuration,
        switchInCurve: _switchInCurve,
        switchOutCurve: _switchOutCurve,
        transitionBuilder: _transitionBuilder,
        child: Icon(iconData, key: ValueKey(isBlurOn)),
      );
    },
    listenable: _controller,
  );
}
