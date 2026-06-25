import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() => group(BackgroundCommand, () {
  test('execute applies the after value, undo applies the before value', () {
    const before = BackgroundElement(blur: 10, height: 80, width: 100, x: 0, y: 0);
    const after = BackgroundElement(blur: 40, height: 80, width: 100, x: 0, y: 0);
    final applied = <BackgroundElement?>[];

    BackgroundCommand(after: after, before: before, onApply: applied.add)
      ..execute()
      ..undo();

    expect(applied, [after, before], reason: 'execute writes after, undo restores before');
  });

  test('carries null treatments through onApply', () {
    final applied = <BackgroundElement?>[];

    BackgroundCommand(after: null, before: null, onApply: applied.add)
      ..execute()
      ..undo();

    expect(applied, hasLength(2));
    expect(applied, everyElement(isNull), reason: 'both execute and undo carry the null treatment');
  });
});
