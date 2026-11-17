import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_controls.dart';

void main() {
  group('呼出式进度条几何', () {
    test('滑块按比例落在轨道内', () {
      expect(scrubKnobX(trackWidth: 100, fraction: 0.5), 50);
      expect(scrubKnobX(trackWidth: 300, fraction: 0.25), 75);
    });

    test('两端夹住半径，半个圆不出界', () {
      final r = kScrubKnobRadius;
      expect(scrubKnobX(trackWidth: 400, fraction: 0), r);
      expect(scrubKnobX(trackWidth: 400, fraction: 1), 400 - r);
    });

    test('越界比例被夹紧，不会画出轨道', () {
      expect(scrubKnobX(trackWidth: 400, fraction: -3), kScrubKnobRadius);
      expect(scrubKnobX(trackWidth: 400, fraction: 9), 400 - kScrubKnobRadius);
    });

    test('宽度非法时退化，不崩', () {
      expect(scrubKnobX(trackWidth: 0, fraction: 0.5), 0);
      expect(scrubKnobX(trackWidth: -10, fraction: 0.5), 0);
    });

    test('细条比放大态更细，且贴合任务栏上缘的高度常量', () {
      expect(kScrubThinHeight, lessThan(kScrubActiveHeight));
      expect(kScrubThinHeight, lessThanOrEqualTo(3));
      expect(kScrubThinHoldMs, greaterThanOrEqualTo(2000));
    });
  });
}
