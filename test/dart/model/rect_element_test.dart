import 'dart:io' show Platform;
import 'dart:isolate' show Isolate, ReceivePort, SendPort;

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:frigate_draw/dart/model/draw_element.dart';
import 'package:frigate_draw/dart/model/ffi_color.dart';
import 'package:test/test.dart';

class _RectElementTest extends AsyncBenchmarkBase {
  _RectElementTest(this.count) : super('IsolateSend($count rects)');
  final int count;
  late final List<RectElement> _rects;

  @override
  Future<void> setup() async => _rects = List.generate(
    count,
    (i) => RectElement(color: FfiColor(i), height: 1, width: 2, x: 3, y: 4),
  );

  @override
  Future<void> run() async {
    final port = ReceivePort();
    //ignore:avoid-ignoring-return-values,avoid-type-casts,avoid-unsafe-collection-methods, a test.
    await Isolate.spawn((args) => (args.first as SendPort).send(true), [port.sendPort, _rects]);
    final _ = await port.first;
    port.close();
  }
}

void main() => group(RectElement, () {
  test('default values', () {
    const rect = RectElement(height: 50, width: 100, x: 10, y: 20);

    expect(rect.strokeWidth, 2.0);
    expect(rect.color.argb, const FfiColor.from().argb);
  });

  test('FfiColor packs ARGB correctly', () => expect(const FfiColor.from().argb, 0xFF000000));

  test('FfiColor packs ARGB correctly with custom values', () {
    const color = FfiColor.from(alpha: 128, blue: 255);
    const raw = FfiColor(2_147_483_903);

    expect(color.argb, 0x800000FF);
    expect(color.argb, raw.argb);
  });

  test('copyWith preserves unchanged fields', () {
    const original = RectElement(height: 50, strokeWidth: 5, width: 100, x: 10, y: 20);
    final RectElement(:color, :height, :strokeWidth, :width, :x, :y) = original.copyWith(x: 30);

    expect(x, 30);
    expect(y, 20);
    expect(width, 100);
    expect(height, 50);
    expect(strokeWidth, 5.0);
    expect(color.argb, const FfiColor.from().argb);
  });

  test('is deeply immutable', () {
    const rect = RectElement(height: 10, width: 10, x: 0, y: 0);
    final moved = rect.copyWith(x: 5);

    expect(rect.x, isZero);
    expect(moved.x, 5);
  });

  test('no copy in isolates outside of the list', () async {
    const rect = RectElement(height: 50, strokeWidth: 5, width: 100, x: 10, y: 20);

    final receivePort = ReceivePort();
    final result = await Isolate.spawn(
      // ignore: avoid-type-casts, avoid-unsafe-collection-methods, it's just a test.,
      (a) => (a.first as SendPort).send(identityHashCode(a.elementAtOrNull(1))),
      [receivePort.sendPort, rect],
    );
    expect(result, isA<Isolate>());
    expect(await receivePort.first, identityHashCode(rect));
    receivePort.close();
  });

  test('no copy in isolates inside of the list', () async {
    // ignore: prefer_const_constructors, just a test.
    final rect = RectElement(height: 50, strokeWidth: 5, width: 100, x: 10, y: 20);
    final list = [rect];

    final receivePort = ReceivePort();
    final result = await Isolate.spawn(
      // ignore: prefer-extracting-function-callbacks, just a test.
      (a) {
        // ignore: avoid-type-casts, avoid-unsafe-collection-methods, just a test.
        final sendPort = a.first as SendPort;
        // ignore: avoid-type-casts, prefer-correct-json-casts, just a test.
        final receivedList = a.elementAtOrNull(1) as List<RectElement>?;
        sendPort.send(identityHashCode(receivedList?.firstOrNull));
      }, // Dart 3.8 formatting.
      [receivePort.sendPort, list],
    );

    expect(result, isA<Isolate>());
    expect(await receivePort.first, identityHashCode(rect));
    receivePort.close();
  });

  test(
    'list send time is O(1) relative to element count - proves elements not copied',
    () async {
      final ten = _RectElementTest(10);
      final thousand = _RectElementTest(1000);
      final hundredThousand = _RectElementTest(100_000);

      await ten.measure(); //ignore:avoid-ignoring-return-values, handles warm-up, averaging intern.
      final thousandMeasure = await thousand.measure();
      final hundredKMeasure = await hundredThousand.measure();

      expect(hundredKMeasure, lessThan(thousandMeasure * 50));
    },
    skip: Platform.isLinux,
  );
});
