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
      // 进度条就是视频/任务栏分界线：默认不再上浮
      expect(stageProgressBottomOffset(), 0);
      expect(stageProgressBottomOffset(safeBottom: 34), 34);
      expect(stageProgressBottomOffset(safeBottom: -3), 0);
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

  group('T stageInfoBottom（信息区必须让开进度条命中条带）', () {
    test('非全屏视频：让开 kScrubHotZoneHeight 条带，而非 2.5dp 细线', () {
      final bottom = stageInfoBottom(
        fullscreen: false,
        hasProgressLayer: true,
        hasChapter: false,
        progressBottom: 0,
        hitStripHeight: 28,
      );
      // 38 = 28 条带 + 10 间距；必须严格大于条带本身，否则头像会落进热区。
      expect(bottom, 38);
      expect(bottom, greaterThan(28));
    });

    test('安全区/内边距叠加，非法值退化为 0', () {
      expect(
          stageInfoBottom(
            fullscreen: false,
            hasProgressLayer: true,
            hasChapter: false,
            progressBottom: 34,
            hitStripHeight: 28,
          ),
          72);
      expect(
          stageInfoBottom(
            fullscreen: false,
            hasProgressLayer: true,
            hasChapter: false,
            progressBottom: -5,
            hitStripHeight: -1,
          ),
          10);
    });

    test('全屏按进度层实际高度让位（含集数标签）', () {
      expect(
          stageInfoBottom(
            fullscreen: true,
            hasProgressLayer: true,
            hasChapter: false,
            progressBottom: 0,
            hitStripHeight: 28,
          ),
          40);
      expect(
          stageInfoBottom(
            fullscreen: true,
            hasProgressLayer: true,
            hasChapter: true,
            progressBottom: 0,
            hitStripHeight: 28,
          ),
          58);
    });

    test('单图图文没有进度层：只留 10dp 间距', () {
      expect(
          stageInfoBottom(
            fullscreen: false,
            hasProgressLayer: false,
            hasChapter: false,
            progressBottom: 0,
            hitStripHeight: 28,
          ),
          10);
    });
  });

  group('视频基准尺寸保持原比例', () {
    test('普通竖屏 9:16', () {
      final s = videoBaseSize(aspect: 9 / 16, referenceHeight: 720);
      expect(s.height, closeTo(720, 0.001));
      expect(s.width / s.height, closeTo(9 / 16, 0.0001));
    });

    test('极宽/极窄比例不再被 clamp 拉变形', () {
      for (final a in <double>[0.12, 0.3, 1.0, 4.0, 12.0]) {
        final s = videoBaseSize(aspect: a, referenceHeight: 720, maxSide: 4096);
        expect(s.width / s.height, closeTo(a, 0.0001));
        expect(s.width, lessThanOrEqualTo(4096.0001));
        expect(s.height, lessThanOrEqualTo(4096.0001));
      }
    });

    test('比例未知时退化为方形，不抛异常', () {
      expect(videoBaseSize(aspect: null), const Size(720, 720));
      expect(videoBaseSize(aspect: 0), const Size(720, 720));
      expect(videoBaseSize(aspect: double.nan), const Size(720, 720));
    });
  });

  group('parseVideoParams（视频参数解释统一）', () {
    test('dw/dh 推导比例，displayWidth 用于判定是否就绪', () {
      final i = parseVideoParams(dw: 1920, dh: 1080);
      expect(i.displayWidth, 1920);
      expect(i.aspect, closeTo(16 / 9, 1e-9));
    });

    test('aspect 优先于 dw/dh 推导', () {
      final i = parseVideoParams(dw: 1920, dh: 1080, aspect: 1.5);
      expect(i.aspect, 1.5);
    });

    test('参数缺失/非法时 displayWidth=0、aspect=null（未就绪）', () {
      expect(parseVideoParams(), (displayWidth: 0.0, aspect: null));
      final bad = parseVideoParams(dw: 1920, dh: 0, aspect: double.nan);
      expect(bad.displayWidth, 1920);
      expect(bad.aspect, isNull);
    });

    test('旋转 90/270：纹理宽高交换，比例取倒数（竖拍 .mov）', () {
      final i = parseVideoParams(dw: 1920, dh: 1080, rotate: -90);
      expect(i.displayWidth, 1080);
      expect(i.aspect, closeTo(9 / 16, 1e-9));
      final j = parseVideoParams(dw: 1920, dh: 1080, rotate: 270);
      expect(j.displayWidth, 1080);
      expect(j.aspect, closeTo(9 / 16, 1e-9));
    });

    test('旋转 0/180 不改变比例', () {
      for (final r in [0, 180, -180, null]) {
        final i = parseVideoParams(dw: 1920, dh: 1080, rotate: r);
        expect(i.displayWidth, 1920, reason: 'rotate=$r');
        expect(i.aspect, closeTo(16 / 9, 1e-9), reason: 'rotate=$r');
      }
    });
  });
}
