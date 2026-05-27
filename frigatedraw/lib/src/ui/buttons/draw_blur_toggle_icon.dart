import 'package:flutter/foundation.dart';
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
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<DrawController>('_controller', _controller))
      ..add(IntProperty('_minValue', _minValue))
      ..add(DiagnosticsProperty<Duration>('_duration', _duration))
      ..add(DiagnosticsProperty<Duration?>('_reverseDuration', _reverseDuration))
      ..add(DiagnosticsProperty<Curve>('_switchInCurve', _switchInCurve))
      ..add(DiagnosticsProperty<Curve>('_switchOutCurve', _switchOutCurve))
      ..add(
        ObjectFlagProperty.has(
          '_transitionBuilder',
          _transitionBuilder != AnimatedSwitcher.defaultTransitionBuilder,
        ),
      )
      ..add(
        ObjectFlagProperty.has(
          '_layoutBuilder',
          _layoutBuilder != AnimatedSwitcher.defaultLayoutBuilder,
        ),
      );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    builder: (bc, _) {
      final selected = _controller.selectedElement;
      final isBlurOn = selected == null ? null : selected.blur > _minValue;
      final iconData = switch (isBlurOn) {
        null => Icons.blur_circular,
        false => Icons.blur_off,
        true => Icons.blur_on,
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
