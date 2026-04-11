// ignore_for_file: prefer-extracting-callbacks
// ignore_for_file: prefer-extracting-function-callbacks
// ignore_for_file: prefer-class-destructuring

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:frigate_draw/frigate_draw.dart';

void main() {
  group('RectElement', () {
    test('default values', () {
      const rect = RectElement(height: 50, width: 100, x: 10, y: 20);

      expect(rect.strokeWidth, 2.0);
      expect(rect.color.argb, const FfiColor.fromARGB().argb);
    });

    test('rect getter returns correct Rect', () {
      const element = RectElement(height: 50, width: 100, x: 10, y: 20);

      expect(element.rect, const Rect.fromLTWH(10, 20, 100, 50));
    });

    test('FfiColor packs ARGB correctly', () {
      const color = FfiColor.fromARGB();

      expect(color.red, 0);
      expect(color.green, 0);
      expect(color.blue, 0);
      expect(color.alpha, 255);
      expect(color.argb, 0xFF000000);
    });

    test('FfiColor.fromARGB packs correctly', () {
      const color = FfiColor.fromARGB(alpha: 128, blue: 255);

      expect(color.argb, 0x800000FF);
    });

    test('copyWith preserves unchanged fields', () {
      const original = RectElement(height: 50, width: 100, x: 10, y: 20, strokeWidth: 5);
      final RectElement(:color, :height, :strokeWidth, :width, :x, :y) = original.copyWith(x: 30);

      expect(x, 30);
      expect(y, 20);
      expect(width, 100);
      expect(height, 50);
      expect(strokeWidth, 5.0);
      expect(color.argb, const FfiColor.fromARGB().argb);
    });

    test('is deeply immutable', () {
      const rect = RectElement(height: 10, width: 10, x: 0, y: 0);
      final moved = rect.copyWith(x: 5);

      expect(rect.x, 0);
      expect(moved.x, 5);
    });
  });
}
