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

  // 0.9.72：桌面端鼠标移动高频调用 showUi，只推进截止时刻、不重建 Timer。
  group('HideDeadline', () {
    final t0 = DateTime(2026, 11, 18, 11, 0, 0);

    test('未排定时剩余为零、不可排定', () {
      final d = HideDeadline();
      expect(d.at, isNull);
      expect(d.remaining(t0), Duration.zero);
    });

    test('extend 从给定时刻顺延指定秒数', () {
      final d = HideDeadline()..extend(t0, 3);
      expect(d.at, t0.add(const Duration(seconds: 3)));
      expect(d.remaining(t0), const Duration(seconds: 3));
      expect(d.remaining(t0.add(const Duration(seconds: 1))),
          const Duration(seconds: 2));
    });

    test('连续 extend 只把截止时刻往后推（高频鼠标移动）', () {
      final d = HideDeadline()..extend(t0, 3);
      d.extend(t0.add(const Duration(milliseconds: 500)), 3);
      expect(d.at, t0.add(const Duration(milliseconds: 3500)));
      expect(d.remaining(t0.add(const Duration(seconds: 1))),
          const Duration(milliseconds: 2500));
    });

    test('过了截止时刻剩余钳到零（计时器到点即可隐藏）', () {
      final d = HideDeadline()..extend(t0, 3);
      expect(d.remaining(t0.add(const Duration(seconds: 5))), Duration.zero);
    });

    test('clear 后不再排定', () {
      final d = HideDeadline()..extend(t0, 3);
      d.clear();
      expect(d.at, isNull);
      expect(d.remaining(t0), Duration.zero);
    });
  });
}
