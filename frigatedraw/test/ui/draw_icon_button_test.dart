import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group(DrawIconButton, () {
  testWidgets('debugFillProperties adds controller and callback', (tester) async {
    final controller = DrawController();
    final button = DrawDeleteButton(controller);

    final builder = DiagnosticPropertiesBuilder();
    button.debugFillProperties(builder);

    final properties = builder.properties.map((i) => i.name).toList(growable: false);
    expect(properties, contains('controller'));
    expect(properties, contains('callback'));
  });
});
