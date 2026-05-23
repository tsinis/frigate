import 'dart:typed_data' show Float64x2, Float64x2List;

import 'package:frigatebird/frigatebird.dart';
import 'package:test/test.dart';

void main() => group(PolygonElement, () {
  final triangle = Float64x2List.fromList([Float64x2(0, 0), Float64x2(100, 0), Float64x2(50, 100)]);

  test('instantiation and properties', () {
    final poly = PolygonElement(
      blur: 5,
      fillColor: const FfiColor(0xFFFF0000),
      height: 100,
      outlineColor: const FfiColor(0xFF00FF00),
      rotation: 45,
      vertices: triangle,
      width: 100,
      x: 0,
      y: 0,
    );

    expect(poly.vertices, triangle);
    expect(poly.x, isZero);
    expect(poly.y, isZero);
    expect(poly.width, 100);
    expect(poly.height, 100);
    expect(poly.fillColor.argb, 0xFFFF0000);
    expect(poly.outlineColor.argb, 0xFF00FF00);
    expect(poly.outlineThickness, 2);
    expect(poly.rotation, 45);
    expect(poly.blur, 5);
  });

  test('requires at least 3 vertices', () {
    expect(
      () => PolygonElement(
        height: 10,
        vertices: Float64x2List.fromList([Float64x2(0, 0), Float64x2(10, 10)]),
        width: 10,
        x: 0,
        y: 0,
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('boundingBoxOf', () {
    final verts = Float64x2List.fromList([
      Float64x2(10, 50),
      Float64x2(100, 20),
      Float64x2(50, 150),
    ]);
    final box = PolygonElement.boundingBoxOf(verts);
    expect(box.x, 10);
    expect(box.y, 20);
    expect(box.width, 90);
    expect(box.height, 130);
  });

  test('copyWith', () {
    final poly = PolygonElement(height: 100, vertices: triangle, width: 100, x: 0, y: 0);

    final updated = poly.copyWith(blur: 10, height: 300, rotation: 90, width: 200, x: 10, y: 20);

    expect(updated.x, 10);
    expect(updated.y, 20);
    expect(updated.width, 200);
    expect(updated.height, 300);
    expect(updated.blur, 10);
    expect(updated.rotation, 90);
    expect(updated.vertices, triangle);
  });

  test('outlineThickness must be in 0..255 range', () {
    final poly = PolygonElement(
      height: 100,
      outlineThickness: 255,
      vertices: triangle,
      width: 100,
      x: 0,
      y: 0,
    );
    expect(poly.outlineThickness, 255);

    expect(
      () => PolygonElement(
        height: 100,
        outlineThickness: 256,
        vertices: triangle,
        width: 100,
        x: 0,
        y: 0,
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('boundingBoxOf clamps zero dimensions to 1.0', () {
    final verts = Float64x2List.fromList([Float64x2(10, 20), Float64x2(10, 20), Float64x2(10, 20)]);
    final box = PolygonElement.boundingBoxOf(verts);
    expect(box.x, 10);
    expect(box.y, 20);
    expect(box.width, 1.0);
    expect(box.height, 1.0);
  });
});
