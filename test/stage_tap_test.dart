import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/stage_tap.dart';

void main() {
  group('M1 全屏单击语义', () {
    test('全屏功能区显示时单击只收起，不暂停', () {
      expect(
        stageTapAction(
            uiVisible: true, fullscreen: true, zoomed: false, doubleTap: false),
        StageTapAction.hideUi,
      );
    });

    test('全屏功能区隐藏时第一次单击只呼出', () {
      expect(
        stageTapAction(
            uiVisible: false,
            fullscreen: true,
            zoomed: false,
            doubleTap: false),
        StageTapAction.showUi,
      );
    });

    test('非全屏保持单击暂停/继续', () {
      expect(
        stageTapAction(
            uiVisible: true,
            fullscreen: false,
            zoomed: false,
            doubleTap: false),
        StageTapAction.togglePause,
      );
    });

    test('非全屏功能区隐藏时单击呼出而不暂停', () {
      expect(
        stageTapAction(
            uiVisible: false,
            fullscreen: false,
            zoomed: false,
            doubleTap: false),
        StageTapAction.showUi,
      );
    });

    test('双击点赞已移除：doubleTap 传 true 也不再返回 like', () {
      // 函数已忽略 doubleTap；任何组合都不应再产生点赞动作。
      for (final fs in [true, false]) {
        for (final ui in [true, false]) {
          expect(
            stageTapAction(
                uiVisible: ui,
                fullscreen: fs,
                zoomed: false,
                doubleTap: true),
            isNot(StageTapAction.like),
          );
        }
      }
    });

    test('图片放大时单击只复位缩放', () {
      expect(
        stageTapAction(
            uiVisible: true, fullscreen: true, zoomed: true, doubleTap: false),
        StageTapAction.resetZoom,
      );
      expect(
        stageTapAction(
            uiVisible: false, fullscreen: true, zoomed: true, doubleTap: false),
        StageTapAction.resetZoom,
      );
    });
  });
}
