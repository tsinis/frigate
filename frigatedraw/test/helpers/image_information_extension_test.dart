import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frigatedraw/frigatedraw.dart';

void main() => group('ImageInformationNullableExtension', () {
  test('returns Size.zero if ImageInformation is null', () {
    // ignore: avoid-explicit-type-declaration, description: Required to resolve nullable extension.
    const ImageInformation? info = null;
    expect(info.size, equals(Size.zero));
  });

  test('returns correct Size if ImageInformation is not null', () {
    const info = ImageInformation(height: 1080, width: 1920);
    expect(info.size, equals(const Size(1920, 1080)));
  });
});
