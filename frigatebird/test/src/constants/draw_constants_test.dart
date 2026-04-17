import 'package:frigatebird/src/constants/draw_constants.dart';
import 'package:test/test.dart';

void main() => group(DrawConstants, () {
  test('min quality is 0', () => expect(DrawConstants.minImageQuality, 0, reason: 'lower bound'));

  test(
    'max quality is 100',
    () => expect(DrawConstants.maxImageQuality, 100, reason: 'upper bound'),
  );

  test(
    'default quality sits inside the bounds',
    () => expect(
      DrawConstants.defaultImageQuality,
      inInclusiveRange(DrawConstants.minImageQuality, DrawConstants.maxImageQuality),
      reason: 'default must be a legal value',
    ),
  );

  test(
    'default quality is 90 (guards against accidental drift)',
    () => expect(DrawConstants.defaultImageQuality, 90),
  );
});
