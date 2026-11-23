import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_controls.dart';
import 'package:shoucangjia/stage_tap.dart';

/// P0：非全屏抖音式手感（数值见 DOUYIN_VISUAL_SPEC.md §3/§5）。
void main() {
  group('§5 舞台点击：双击点赞移除后只剩单一路径', () {
    test('暂停提示固定 0.8s', () {
      expect(kPlayHintFadeMs, 800);
    });

    test('stageTapAction 无双击：单击即呼出/收起/暂停', () {
      expect(
        stageTapAction(
            uiVisible: true, fullscreen: true, zoomed: false, doubleTap: false),
        StageTapAction.hideUi,
      );
      expect(
        stageTapAction(
            uiVisible: false,
            fullscreen: false,
            zoomed: false,
            doubleTap: false),
        StageTapAction.showUi,
      );
      expect(
        stageTapAction(
            uiVisible: true,
            fullscreen: false,
            zoomed: false,
            doubleTap: false),
        StageTapAction.togglePause,
      );
    });
  });

  group('§5 暂停播放图标淡出', () {
    test('0.8s easeOut，从 1 淡到 0', () {
      expect(playHintOpacityAt(0), 1);
      expect(playHintOpacityAt(1), 0);
      // easeOut 前段下降更快：t=0.5 时剩余不透明度 < 0.5（线性剩余 0.5）。
      expect(playHintOpacityAt(0.5), lessThan(0.5));
    });
  });

  group('§3 进度条视觉参数', () {
    test('常态 2dp / 60% 白 / 圆角 1dp', () {
      final m = stageProgressMetrics(pressed: false);
      expect(m.height, 2);
      expect(m.radius, 1);
      expect(m.trackColor, const Color(0x99FFFFFF));
      expect(m.playedColor, Colors.white);
    });

    test('按住/拖动 4dp / 全白 / 圆角 2dp', () {
      final m = stageProgressMetrics(pressed: true);
      expect(m.height, 4);
      expect(m.radius, 2);
      expect(m.trackColor, Colors.white);
      expect(m.playedColor, Colors.white);
    });

    test('时间 11px tabular / 白 90%', () {
      expect(kProgressTimeFontSize, 11);
      expect(kProgressTimeColor, const Color(0xE6FFFFFF));
      expect(kProgressTimeStyle.fontSize, 11);
      expect(kProgressTimeStyle.color, const Color(0xE6FFFFFF));
      expect(kProgressTimeStyle.fontFeatures, isNotEmpty);
    });

    test('气泡 12px / #CC000000 / 圆角 6dp', () {
      expect(kSeekBubbleFontSize, 12);
      expect(kSeekBubbleColor, const Color(0xCC000000));
      expect(kSeekBubbleRadius, 6);
      expect(kSeekBubbleTextStyle.fontSize, 12);
    });

    test('左右边距 12dp、距任务栏 8dp', () {
      expect(kProgressSideMargin, 12);
      expect(kProgressBottomGap, 8);
    });
  });

  group('§6 左上角图标按钮', () {
    test('规格常量：24dp / 间距 12dp / 按压 scale 0.92 / 120ms / white24', () {
      expect(kStageIconSize, 24);
      expect(kStageIconSpacing, 12);
      expect(kPressScaleTo, 0.92);
      expect(kPressScaleMs, 120);
      expect(kPressOverlayColor, const Color(0x24FFFFFF));
    });

    testWidgets('图标 24dp、热区 40dp、常态无圆底', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: StageIconButton(
                icon: Icons.arrow_back, onPressed: () {}),
          ),
        ),
      ));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 24);
      final box = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(box.width, 40);
      expect(box.height, 40);
      final deco = tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer))
          .decoration as BoxDecoration;
      expect(deco.color, Colors.transparent);
    });

    testWidgets('按下时 white24 圆底 + scale 0.92，松手恢复', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: StageIconButton(
                icon: Icons.arrow_back, onPressed: () => tapped = true),
          ),
        ),
      ));
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(Icon)));
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        (tester.widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration as BoxDecoration)
            .color,
        kPressOverlayColor,
      );
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        0.92,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
      expect(
        (tester.widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration as BoxDecoration)
            .color,
        Colors.transparent,
      );
    });
  });
}
