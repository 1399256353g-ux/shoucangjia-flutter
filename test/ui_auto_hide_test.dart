import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/ui_auto_hide.dart';

void main() {
  group('UiAutoHidePolicy.shouldSchedule', () {
    test('全屏且功能区可见时排定计时器', () {
      expect(
        UiAutoHidePolicy.shouldSchedule(fullscreen: true, uiVisible: true),
        isTrue,
      );
    });

    test('非全屏不排定（M4：退出全屏后不得自动隐藏）', () {
      expect(
        UiAutoHidePolicy.shouldSchedule(fullscreen: false, uiVisible: true),
        isFalse,
      );
    });

    test('功能区已隐藏时不重复排定', () {
      expect(
        UiAutoHidePolicy.shouldSchedule(fullscreen: true, uiVisible: false),
        isFalse,
      );
    });
  });

  group('UiAutoHidePolicy.shouldHide', () {
    test('全屏、存活、未拖拽未悬停时隐藏', () {
      expect(
        UiAutoHidePolicy.shouldHide(
          fullscreen: true,
          mounted: true,
          dragging: false,
          barHover: false,
        ),
        isTrue,
      );
    });

    test('退出全屏后到期不隐藏（M4 回归点）', () {
      expect(
        UiAutoHidePolicy.shouldHide(
          fullscreen: false,
          mounted: true,
          dragging: false,
          barHover: false,
        ),
        isFalse,
      );
    });

    test('页面已销毁不隐藏', () {
      expect(
        UiAutoHidePolicy.shouldHide(
          fullscreen: true,
          mounted: false,
          dragging: false,
          barHover: false,
        ),
        isFalse,
      );
    });

    test('拖动进度条时不隐藏', () {
      expect(
        UiAutoHidePolicy.shouldHide(
          fullscreen: true,
          mounted: true,
          dragging: true,
          barHover: false,
        ),
        isFalse,
      );
    });

    test('鼠标悬停进度条时不隐藏', () {
      expect(
        UiAutoHidePolicy.shouldHide(
          fullscreen: true,
          mounted: true,
          dragging: false,
          barHover: true,
        ),
        isFalse,
      );
    });
  });
}
