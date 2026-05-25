import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../draw_controller.dart';
import '../draw_tool.dart';

/// A modern segmented control bar for selecting active [DrawTool]s.
///
/// Fully configurable, defaulting to [DrawTool.values], and rendered as icon-only.
class DrawToolSegmentedButton extends StatelessWidget {
  const DrawToolSegmentedButton(
    this._controller, {
    this._expandedInsets,
    this._onSelectionChanged,
    this._selectedIcon,
    this._style,
    super.key,
    this._direction = .horizontal,
    this._isEmptySelectionAllowed = true,
    this._shouldShowSelectedIcon = true,
    this._tools = defaultTools,
  });

  /// Default icon mapping for each drawing tool.
  static const defaultTools = <DrawTool, IconData?>{
    .select: Icons.pan_tool_alt_outlined,
    .rectangle: Icons.crop_square_outlined,
    .oval: Icons.circle_outlined,
    .polygon: Icons.hexagon_outlined,
    .text: Icons.text_fields_outlined,
  };

  final DrawController _controller;
  final ValueChanged<DrawTool?>? _onSelectionChanged;
  final Axis _direction;
  final bool _isEmptySelectionAllowed;
  final EdgeInsets? _expandedInsets;
  final Widget? _selectedIcon;
  final bool _shouldShowSelectedIcon;
  final ButtonStyle? _style;
  final Map<DrawTool, IconData?> _tools;

  /// Builds the [ButtonSegment] list for each drawing tool.
  List<ButtonSegment<DrawTool>> get _segments => _tools.keys
      .map((tool) {
        final icon = _tools[tool] ?? defaultTools[tool];

        return ButtonSegment(enabled: icon != null, icon: Icon(icon), value: tool);
      })
      .toList(growable: false);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<DrawController>('_controller', _controller))
      ..add(EnumProperty<Axis>('_direction', _direction))
      ..add(DiagnosticsProperty<bool>('_isEmptySelectionAllowed', _isEmptySelectionAllowed))
      ..add(DiagnosticsProperty<EdgeInsets>('_expandedInsets', _expandedInsets))
      ..add(DiagnosticsProperty<Widget>('_selectedIcon', _selectedIcon))
      ..add(DiagnosticsProperty<bool>('_shouldShowSelectedIcon', _shouldShowSelectedIcon))
      ..add(DiagnosticsProperty<ButtonStyle>('_style', _style))
      ..add(DiagnosticsProperty<Map<DrawTool, IconData?>>('_tools', _tools))
      ..add(
        ObjectFlagProperty<ValueChanged<DrawTool?>>.has('_onSelectionChanged', _onSelectionChanged),
      );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    builder: (_, _) => SegmentedButton<DrawTool>(
      direction: _direction,
      emptySelectionAllowed: _isEmptySelectionAllowed || _controller.activeTool == null,
      expandedInsets: _expandedInsets,
      onSelectionChanged: (select) => _onSelectionChanged?.call(select.firstOrNull),
      segments: _segments,
      selected: {?_controller.activeTool},
      selectedIcon: _selectedIcon,
      showSelectedIcon: _shouldShowSelectedIcon,
      style: _style,
    ),
    listenable: _controller,
  );
}
