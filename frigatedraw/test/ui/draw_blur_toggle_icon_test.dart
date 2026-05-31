import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group(DrawBlurToggleIcon, () {
  test('debugFillProperties includes all configurable diagnostics', () {
    final widget = DrawBlurToggleIcon(
      DrawController(),
      duration: const Duration(milliseconds: 123),
      layoutBuilder: (currentChild, previousChildren) => currentChild ?? const SizedBox.shrink(),
      minValue: 1,
      reverseDuration: const Duration(milliseconds: 321),
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
    );

    final properties = DiagnosticPropertiesBuilder();
    widget.debugFillProperties(properties);
    final names = properties.properties.map((e) => e.name).toSet();

    expect(
      names,
      containsAll(<String>{
        '_controller',
        '_minValue',
        '_duration',
        '_reverseDuration',
        '_switchInCurve',
        '_switchOutCurve',
        '_transitionBuilder',
        '_layoutBuilder',
      }),
    );
  });
});
