import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/video_layout.dart';

void main() {
  group('O4 videoContentRect', () {
    test('竖屏框内播放 16:9 → 上下黑边，画面水平撑满', () {
      final r = videoContentRect(const Size(400, 800), 16 / 9);
      expect(r.left, 0);
      expect(r.width, 400);
      expect(r.height, closeTo(225, 0.001));
      expect(r.top, closeTo((800 - 225) / 2, 0.001));
    });

    test('横屏框内播放 16:9 → 左右黑边，画面高度撑满', () {
      final r = videoContentRect(const Size(1200, 600), 16 / 9);
      expect(r.top, 0);
      expect(r.height, 600);
      expect(r.width, closeTo(600 * 16 / 9, 0.001));
    });

    test('宽高比缺失/非法时退回整个容器', () {
      expect(videoContentRect(const Size(100, 200), null).height, 200);
      expect(videoContentRect(const Size(100, 200), 0).height, 200);
      expect(videoContentRect(Size.zero, 1.5), Rect.zero);
    });
  });

  group('O4 taskbarBottomInset', () {
    test('竖屏宽屏视频：任务栏上移到画面下沿', () {
      final inset = taskbarBottomInset(
          box: const Size(400, 800), aspect: 16 / 9);
      expect(inset, closeTo((800 - 225) / 2, 0.001));
    });

    test('画面撑满、全屏或拿不到宽高比时贴屏幕底', () {
      expect(taskbarBottomInset(box: const Size(400, 400), aspect: 1),
          closeTo(0, 0.001));
      expect(
          taskbarBottomInset(
              box: const Size(400, 800), aspect: 16 / 9, fullscreen: true),
          0);
      expect(taskbarBottomInset(box: const Size(400, 800), aspect: null), 0);
    });

    test('异常宽高比时内缩量最多 45% 屏高', () {
      final inset =
          taskbarBottomInset(box: const Size(400, 800), aspect: 20);
      expect(inset, lessThanOrEqualTo(800 * 0.45));
    });
  });

  group('T stageBottomInset', () {
    test('正常态舞台按任务栏高度内缩', () {
      expect(
          stageBottomInset(screenHeight: 800, taskbarHeight: 96), 96);
      expect(stageBottomInset(screenHeight: 800, taskbarHeight: 0), 0);
      expect(stageBottomInset(screenHeight: 800, taskbarHeight: -20), 0);
    });

    test('全屏时舞台铺满，不因任务栏残留高度内缩', () {
      expect(
          stageBottomInset(
              screenHeight: 800, taskbarHeight: 96, fullscreen: true),
          0);
    });

    test('栏高超过屏高或屏高非法时退化，不产生负高度', () {
      expect(stageBottomInset(screenHeight: 800, taskbarHeight: 900), 800);
      expect(stageBottomInset(screenHeight: 0, taskbarHeight: 96), 0);
    });
  });

  group('T stageProgressBottomOffset', () {
    test('默认只留内边距；有安全区时叠加', () {
      expect(stageProgressBottomOffset(), 10);
      expect(stageProgressBottomOffset(safeBottom: 34), 44);
      expect(stageProgressBottomOffset(safeBottom: -3), 10);
      expect(stageProgressBottomOffset(safeBottom: 20, padding: 0), 20);
    });

    test('内边距非法时退化为 0', () {
      expect(stageProgressBottomOffset(padding: -4), 0);
    });
  });

  group('T stageProgressOverlayHeight', () {
    test('有集数标签时更高，供信息行避让', () {
      expect(stageProgressOverlayHeight(), 30);
      expect(stageProgressOverlayHeight(hasChapter: true), 48);
      expect(stageProgressOverlayHeight(hasChapter: true),
          greaterThan(stageProgressOverlayHeight()));
    });
  });
}
