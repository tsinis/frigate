import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:frigatebird/frigatebird.dart';

import 'draw_controller.dart';

/// A high-level Material 2023+ styled slider that integrates directly with a [DrawController].
///
/// If an element is selected in the controller, this slider binds to that element's blur
/// value and handles real-time updates and proper undo/redo integration automatically.
/// Otherwise, it acts as a standard stateless slider.
class DrawBlurSlider extends Slider {
  const DrawBlurSlider(
    this._controller, {
    required super.value,
    this._minColor,
    super.activeColor,
    super.allowedInteraction,
    super.autofocus,
    super.divisions,
    super.focusNode,
    super.inactiveColor,
    super.key,
    super.label,
    super.max = 255,
    super.min,
    super.mouseCursor,
    super.onChangeEnd,
    super.onChangeStart,
    super.onChanged,
    super.overlayColor,
    super.padding,
    super.secondaryActiveColor,
    super.secondaryTrackValue,
    super.semanticFormatterCallback,
    super.showValueIndicator,
    super.thumbColor,
  }) : assert(min >= 0, 'min must be >= 0'),
       assert(max <= 255, 'max must be <= 255');

  final DrawController _controller;
  final FfiColor? _minColor;

  @override
  State<DrawBlurSlider> createState() => _DrawBlurSliderState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final minCol = _minColor;
    properties
      ..add(DiagnosticsProperty<DrawController>('_controller', _controller))
      ..add(ColorProperty('_minColor', minCol == null ? null : Color(minCol.argb)));
  }
}

class _DrawBlurSliderState extends State<DrawBlurSlider> {
  DrawElement? _sliderDragSnapshot;

  DrawController get _controller => widget._controller;

  void _handleBlurChanged(double value) {
    final element = _controller.selectedElement;
    final index = _controller.selectedIndex;
    if (index != null && element != null) {
      final blurVal = value.round();
      _controller.updateElement(
        element.copyWith(
          blur: blurVal,
          fillColor: blurVal <= widget.min ? widget._minColor : .transparent,
          outlineColor: .transparent,
          outlineThickness: 0,
        ),
        index,
      );
    }
    widget.onChanged?.call(value);
  }

  void _handleBlurChangeEnd(double value) {
    final current = _controller.selectedElement;
    final index = _controller.selectedIndex;
    final snapshot = _sliderDragSnapshot;
    if (index != null && current != null && snapshot != null) {
      _controller.commitCommand(index, after: current, before: snapshot);
    }
    _sliderDragSnapshot = null;
    widget.onChangeEnd?.call(value);
  }

  void _handleBlurChangeStart(double value) {
    _sliderDragSnapshot = _controller.selectedElement;
    widget.onChangeStart?.call(value);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    builder: (bc, _) {
      final selected = _controller.selectedElement;
      final sliderValue = (selected?.blur.toDouble() ?? widget.value).clamp(widget.min, widget.max);

      return SliderTheme(
        data: SliderTheme.of(bc).copyWith(year2023: false),
        child: Slider(
          activeColor: widget.activeColor,
          allowedInteraction: widget.allowedInteraction,
          autofocus: widget.autofocus,
          divisions: widget.divisions ?? (widget.max - widget.min).round(),
          focusNode: widget.focusNode,
          inactiveColor: widget.inactiveColor,
          label: widget.label ?? sliderValue.round().toString(),
          max: widget.max,
          min: widget.min,
          mouseCursor: widget.mouseCursor,
          onChangeEnd: _handleBlurChangeEnd,
          onChangeStart: _handleBlurChangeStart,
          onChanged: _handleBlurChanged,
          overlayColor: widget.overlayColor,
          padding: widget.padding,
          secondaryActiveColor: widget.secondaryActiveColor,
          secondaryTrackValue: widget.secondaryTrackValue,
          semanticFormatterCallback: widget.semanticFormatterCallback,
          showValueIndicator: widget.showValueIndicator,
          thumbColor: widget.thumbColor,
          value: sliderValue,
        ),
      );
    },
    listenable: _controller,
  );
}
