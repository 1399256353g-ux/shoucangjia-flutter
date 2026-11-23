import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/ui_fade.dart';

void main() {
  group('ChromeFade.opacity', () {
    test('静止且功能区可见时为全不透明', () {
      expect(
        ChromeFade.opacity(uiVisible: true, fullscreen: false, swiping: false),
        1.0,
      );
    });

    test('非全屏滑动时不淡化（owner 2026-11-20）', () {
      expect(
        ChromeFade.opacity(uiVisible: true, fullscreen: false, swiping: true),
        1.0,
      );
    });

    test('滑动结束后恢复全不透明', () {
      final during =
          ChromeFade.opacity(uiVisible: true, fullscreen: false, swiping: true);
      final after = ChromeFade.opacity(
          uiVisible: true, fullscreen: false, swiping: false);
      expect(during, 1.0);
      expect(after, 1.0);
    });

    test('全屏不淡化：维持 M4 的显示逻辑', () {
      expect(
        ChromeFade.opacity(uiVisible: true, fullscreen: true, swiping: true),
        1.0,
      );
    });

    test('滑动不会把已隐藏的功能区重新点亮', () {
      expect(
        ChromeFade.opacity(uiVisible: false, fullscreen: false, swiping: true),
        0.0,
      );
    });

    test('淡化值足够低但仍可见（不遮挡画面）', () {
      expect(ChromeFade.dimmedOpacity, lessThan(0.35));
      expect(ChromeFade.dimmedOpacity, greaterThan(0.1));
    });
  });

  group('ChromeFade.durationMs', () {
    test('淡出快于恢复', () {
      expect(ChromeFade.durationMs(swiping: true), ChromeFade.fadeOutMs);
      expect(ChromeFade.durationMs(swiping: false), ChromeFade.fadeInMs);
      expect(ChromeFade.fadeOutMs, lessThan(ChromeFade.fadeInMs));
    });
  });

  group('ChromeFade.infoOpacity（信息区 + 进度条，owner 2026-11-22）', () {
    test('非全屏滑动时淡到 dimmedOpacity', () {
      expect(
          ChromeFade.infoOpacity(
              uiVisible: true, fullscreen: false, swiping: true),
          ChromeFade.dimmedOpacity);
    });

    test('非全屏静止时全不透明', () {
      expect(
          ChromeFade.infoOpacity(
              uiVisible: true, fullscreen: false, swiping: false),
          1.0);
    });

    test('全屏滑动不淡化', () {
      expect(
          ChromeFade.infoOpacity(
              uiVisible: true, fullscreen: true, swiping: true),
          1.0);
    });

    test('功能区隐藏时为 0（与顶部/任务栏一致）', () {
      expect(
          ChromeFade.infoOpacity(
              uiVisible: false, fullscreen: false, swiping: true),
          0.0);
    });

    test('比顶部/任务栏（恒为 1）更暗，两套不共用同一个值', () {
      final chrome = ChromeFade.opacity(
          uiVisible: true, fullscreen: false, swiping: true);
      final info = ChromeFade.infoOpacity(
          uiVisible: true, fullscreen: false, swiping: true);
      expect(info, lessThan(chrome));
    });
  });
}
