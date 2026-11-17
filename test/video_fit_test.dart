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

    test('宽高比缺失/非法时同样铺满', () {
      expect(videoFitFor(aspect: null), VideoFit.fill);
      expect(videoFitFor(aspect: 0), VideoFit.fill);
      expect(videoFitFor(aspect: -1.5), VideoFit.fill);
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
