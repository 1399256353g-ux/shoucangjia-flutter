import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/video_layout.dart';

void main() {
  group('B videoFitFor', () {
    test('竖屏源（9:16 < 0.8）自动铺满', () {
      expect(videoFitFor(aspect: 9 / 16), VideoFit.fill);
      expect(videoFitFor(aspect: 0.7), VideoFit.fill);
    });

    test('竖屏边界 0.8 仍铺满，刚好等于阈值不上浮', () {
      expect(videoFitFor(aspect: 0.8), VideoFit.fill);
    });

    test('横板/方形保持完整画面，不裁不拉伸', () {
      // 9:16 舞台里 cover 16:9 要左右各裁 ~68%，会毁掉画面
      expect(videoFitFor(aspect: 16 / 9), VideoFit.contain);
      expect(videoFitFor(aspect: 21 / 9), VideoFit.contain);
      expect(videoFitFor(aspect: 4 / 3), VideoFit.contain);
      expect(videoFitFor(aspect: 1.0), VideoFit.contain);
      expect(videoFitFor(aspect: 0.81), VideoFit.contain);
    });

    test('宽高比缺失/非法时退回适应，不强行放大裁切', () {
      // 横板视频在首帧前若按铺满渲染，会被裁掉大半，观感像强行拉伸。
      expect(videoFitFor(aspect: null), VideoFit.contain);
      expect(videoFitFor(aspect: 0), VideoFit.contain);
      expect(videoFitFor(aspect: -1.5), VideoFit.contain);
    });

    test('竖屏视频放进宽窗口必须保原比例（不裁成横板）', () {
      // 9:16 源 + 16:9 容器：cover 要裁掉约 68% 高度，会只剩中间一条
      expect(
        videoFitFor(aspect: 9 / 16, containerAspect: 16 / 9),
        VideoFit.contain,
      );
    });

    test('竖屏视频在竖屏舞台内仍铺满（裁切极小）', () {
      expect(
        videoFitFor(aspect: 9 / 16, containerAspect: 9 / 16),
        VideoFit.fill,
      );
      expect(
        videoFitFor(aspect: 0.56, containerAspect: 0.5625),
        VideoFit.fill,
      );
    });

    test('竖屏源 + 竖屏容器：不论裁切多少都铺满（对齐抖音观感）', () {
      // iPhone 9:19.5 屏放 9:16 视频：铺满只横向裁约 15%，观感是满屏；
      // 改适应会上下留黑边、被灵动岛切一块，所以这里必须仍为铺满。
      expect(
        videoFitFor(aspect: 0.60, containerAspect: 0.5625),
        VideoFit.fill,
      );
      expect(
        videoFitFor(aspect: 0.70, containerAspect: 0.5625),
        VideoFit.fill,
      );
      expect(
        videoFitFor(aspect: 9 / 16, containerAspect: 0.478),
        VideoFit.fill,
      );
    });

    test('手动覆盖优先于自动判定', () {
      expect(videoFitFor(aspect: 16 / 9, mode: VideoFit.fill), VideoFit.fill);
      expect(
        videoFitFor(aspect: 9 / 16, mode: VideoFit.contain),
        VideoFit.contain,
      );
    });
  });

  group('B videoViewportHeight', () {
    test('视口高度 = 屏幕高 − 底栏高', () {
      expect(videoViewportHeight(screenHeight: 800, taskbarHeight: 96), 704);
      expect(videoViewportHeight(screenHeight: 800, taskbarHeight: 0), 800);
    });

    test('底栏异常时夹在屏幕范围内', () {
      expect(videoViewportHeight(screenHeight: 800, taskbarHeight: -20), 800);
      expect(videoViewportHeight(screenHeight: 800, taskbarHeight: 900), 0);
      expect(videoViewportHeight(screenHeight: 0, taskbarHeight: 96), 0);
    });

    test('底栏预留高度含安全区', () {
      expect(taskbarReservedHeight(contentHeight: 78, safeBottom: 0), 78);
      expect(taskbarReservedHeight(contentHeight: 78, safeBottom: 34), 112);
      expect(taskbarReservedHeight(contentHeight: -5, safeBottom: -3), 0);
    });
  });
}
