import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/video_layout.dart';

void main() {
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
      // 36 = 28 条带 + 8 紧凑间距（owner 2026-11-22 要求往下挪）；
      // 必须严格大于条带本身，否则头像会落进热区。
      expect(bottom, 36);
      expect(bottom, greaterThan(28));
      expect(bottom, lessThanOrEqualTo(40));
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
          70);
      expect(
          stageInfoBottom(
            fullscreen: false,
            hasProgressLayer: true,
            hasChapter: false,
            progressBottom: -5,
            hitStripHeight: -1,
          ),
          8);
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

    test('非全屏位置不随进度层变化（固定预留，owner 2026-11-22）', () {
      final withLayer = stageInfoBottom(
        fullscreen: false,
        hasProgressLayer: true,
        hasChapter: false,
        progressBottom: 0,
        hitStripHeight: 28,
      );
      final withoutLayer = stageInfoBottom(
        fullscreen: false,
        hasProgressLayer: false,
        hasChapter: false,
        progressBottom: 0,
        hitStripHeight: 28,
      );
      expect(withLayer, withoutLayer);
      expect(withLayer, 36);
    });

    test('全屏单图（无进度层）仍只留默认间距', () {
      expect(
          stageInfoBottom(
            fullscreen: true,
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

  group('拉伸判据（不看画面，只看渲染框比例）', () {
    test('基准框按源比例生成 → 失真恒为 0', () {
      for (final a in [9 / 16, 16 / 9, 3 / 4, 1.0, 21 / 9]) {
        final base = videoBaseSize(aspect: a);
        expect(videoDistortion(sourceAspect: a, base: base), closeTo(0, 1e-9),
            reason: 'aspect=$a');
      }
    });

    test('极宽/极窄也不失真（旧的宽度 clamp 一定会失败）', () {
      for (final a in [0.15, 0.25, 8.0, 12.0]) {
        final base = videoBaseSize(aspect: a);
        expect(videoDistortion(sourceAspect: a, base: base),
            lessThan(kStretchTolerance),
            reason: 'aspect=$a 拉伸判据应通过');
      }
    });

    test('框被夹住时能报出具体偏差（判据本身有效）', () {
      // 9:16 的画面被塞进 16:9 的框：0.5625 → 1.7778，偏差 216%
      final bad = videoDistortion(
          sourceAspect: 9 / 16, base: const Size(1280, 720));
      expect(bad, greaterThan(kStretchTolerance));
      expect(bad, closeTo((16 / 9) / (9 / 16) - 1, 1e-9));
      // 2% 边界两侧
      final ok = videoDistortion(
          sourceAspect: 1.0, base: const Size(1000, 1000 * 1.02));
      expect(ok, closeTo(0.0196, 1e-3));
      expect(ok, lessThan(kStretchTolerance));
    });

    test('比例缺失或框尺寸非法时返回 0，不误报', () {
      expect(videoDistortion(sourceAspect: null, base: const Size(10, 10)), 0);
      expect(videoDistortion(sourceAspect: 0.5, base: Size.zero), 0);
      expect(
          videoDistortion(sourceAspect: double.nan, base: const Size(9, 16)), 0);
    });
  });
}
