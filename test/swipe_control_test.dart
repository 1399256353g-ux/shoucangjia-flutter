import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/swipe_control.dart';

void main() {
  group('swipeZoneAt', () {
    test('左边缘是亮度，右边缘是音量，中间为翻页', () {
      expect(swipeZoneAt(10, 390), SwipeZone.brightness);
      expect(swipeZoneAt(195, 390), isNull);
      expect(swipeZoneAt(385, 390), SwipeZone.volume);
    });

    test('窄屏与宽屏的边缘宽度都被夹紧', () {
      expect(swipeEdgeWidth(240), 48);
      expect(swipeEdgeWidth(390), closeTo(70.2, 0.01));
      expect(swipeEdgeWidth(1200), 96);
    });

    test('非法宽度不产生作用区', () {
      expect(swipeZoneAt(0, 0), isNull);
    });
  });

  group('swipeValueFromDrag', () {
    test('向上滑增大，向下滑减小', () {
      final up = swipeValueFromDrag(start: 50, dy: -100, height: 500);
      final down = swipeValueFromDrag(start: 50, dy: 100, height: 500);
      expect(up, closeTo(70, 0.001));
      expect(down, closeTo(30, 0.001));
    });

    test('结果夹在 0–100', () {
      expect(swipeValueFromDrag(start: 90, dy: -1000, height: 500), 100);
      expect(swipeValueFromDrag(start: 10, dy: 1000, height: 500), 0);
    });

    test('高度非法时保持原值', () {
      expect(swipeValueFromDrag(start: 42, dy: -80, height: 0), 42);
    });
  });

  group('O1 edgeGestureIntent', () {
    test('左右各 1/4 屏宽：左亮度、右音量、中间让给翻页', () {
      expect(edgeGestureIntent(dx: 2, dy: -40, width: 400, startX: 20),
          EdgeGestureIntent.brightness);
      expect(edgeGestureIntent(dx: -2, dy: -40, width: 400, startX: 390),
          EdgeGestureIntent.volume);
      expect(edgeGestureIntent(dx: 2, dy: -40, width: 400, startX: 200),
          EdgeGestureIntent.none);
      // 25% 边界属于左区，75% 边界属于右区。
      expect(edgeGestureIntent(dx: 0, dy: 40, width: 400, startX: 100),
          EdgeGestureIntent.brightness);
      expect(edgeGestureIntent(dx: 0, dy: 40, width: 400, startX: 300),
          EdgeGestureIntent.volume);
    });

    test('竖向不足 12px 不接管', () {
      expect(edgeGestureIntent(dx: 0, dy: 12, width: 400, startX: 10),
          EdgeGestureIntent.none);
      expect(edgeGestureIntent(dx: 0, dy: 13, width: 400, startX: 10),
          EdgeGestureIntent.brightness);
    });

    test('斜向拖动（横向 ≥ 竖向 0.6）交给 PageView', () {
      // dy=100, dx=60 → 恰好 0.6，让位。
      expect(edgeGestureIntent(dx: 60, dy: -100, width: 400, startX: 10),
          EdgeGestureIntent.none);
      expect(edgeGestureIntent(dx: 50, dy: -100, width: 400, startX: 10),
          EdgeGestureIntent.brightness);
    });

    test('横屏或桌面（portrait=false）不启用', () {
      expect(
          edgeGestureIntent(
              dx: 0, dy: 80, width: 800, startX: 10, portrait: false),
          EdgeGestureIntent.none);
    });

    test('热区宽度为 1/4 屏宽', () {
      expect(edgeHotZoneWidth(400), 100);
      expect(edgeHotZoneWidth(0), 0);
    });
  });

  group('亮度遮罩与提示', () {
    test('亮度 100 不压暗，0 时最大压暗', () {
      expect(dimOpacityForBrightness(100), 0);
      expect(dimOpacityForBrightness(0), closeTo(0.78, 0.001));
      expect(dimOpacityForBrightness(50), closeTo(0.39, 0.001));
      expect(dimOpacityForBrightness(140), 0);
    });

    test('标签与震动档位', () {
      expect(swipeLabel(SwipeZone.brightness), '亮度');
      expect(swipeLabel(SwipeZone.volume), '音量');
      expect(swipeHapticStep(9.9), 0);
      expect(swipeHapticStep(10), 1);
      expect(swipeHapticStep(100), 10);
    });

    test('仅 Android/iOS 启用', () {
      expect(swipeEnabledFor(isAndroid: true, isIOS: false), isTrue);
      expect(swipeEnabledFor(isAndroid: false, isIOS: true), isTrue);
      expect(swipeEnabledFor(isAndroid: false, isIOS: false), isFalse);
      expect(
          swipeEnabledFor(isAndroid: true, isIOS: false, isWeb: true), isFalse);
    });
  });
}
