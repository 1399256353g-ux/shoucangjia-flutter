import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/gesture_verdict.dart';

void main() {
  group('gestureVerdict', () {
    test('原地短按 = tap', () {
      expect(
        gestureVerdict(
          down: const Offset(500, 900),
          up: const Offset(502, 901),
          held: const Duration(milliseconds: 80),
        ),
        GestureVerdict.tap,
      );
    });

    test('竖向上滑 = swipe（不是点击）', () {
      // 上一轮真机日志：pos 535,44 → 535,-299
      expect(
        gestureVerdict(
          down: const Offset(535, 44),
          up: const Offset(535, -299),
          held: const Duration(milliseconds: 260),
        ),
        GestureVerdict.swipe,
      );
    });

    test('横向拖动 = swipe', () {
      expect(
        gestureVerdict(
          down: const Offset(100, 500),
          up: const Offset(400, 505),
          held: const Duration(milliseconds: 300),
        ),
        GestureVerdict.swipe,
      );
    });

    test('按住不动超过长按门槛 = hold', () {
      expect(
        gestureVerdict(
          down: const Offset(200, 700),
          up: const Offset(203, 702),
          held: const Duration(milliseconds: 700),
        ),
        GestureVerdict.hold,
      );
    });

    test('slop 边界：恰好等于阈值仍算 tap', () {
      expect(
        gestureVerdict(
          down: Offset.zero,
          up: const Offset(kGestureTapSlop, 0),
          held: const Duration(milliseconds: 50),
        ),
        GestureVerdict.tap,
      );
    });

    test('短距离慢按（未到长按）仍算 tap', () {
      expect(
        gestureVerdict(
          down: const Offset(10, 10),
          up: const Offset(20, 18),
          held: const Duration(milliseconds: 480),
        ),
        GestureVerdict.tap,
      );
    });

    test('日志短名固定', () {
      expect(gestureVerdictName(GestureVerdict.tap), 'tap');
      expect(gestureVerdictName(GestureVerdict.swipe), 'swipe');
      expect(gestureVerdictName(GestureVerdict.hold), 'hold');
    });
  });
}
