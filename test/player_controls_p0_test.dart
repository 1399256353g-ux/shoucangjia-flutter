import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_controls.dart';

/// P0：非全屏抖音式手感（数值见 DOUYIN_VISUAL_SPEC.md §3/§5）。
void main() {
  group('§5 单击/双击仲裁', () {
    test('单击延迟固定为 250ms', () {
      expect(kStageSingleTapDelayMs, 250);
      expect(kStageDoubleTapWindowMs, 250);
    });

    test('第一次点击不立即构成双击，记入 pending', () {
      final a = StageTapArbiter();
      expect(a.registerTap(nowMs: 1000, pos: const Offset(10, 10)), isFalse);
      expect(a.hasPending, isTrue);
    });

    test('250ms 内相近位置第二次点击 => 双击并清空 pending', () {
      final a = StageTapArbiter();
      a.registerTap(nowMs: 1000, pos: const Offset(10, 10));
      expect(a.registerTap(nowMs: 1200, pos: const Offset(20, 12)), isTrue);
      expect(a.hasPending, isFalse);
    });

    test('超过窗口不构成双击（视为新的单击）', () {
      final a = StageTapArbiter();
      a.registerTap(nowMs: 1000, pos: const Offset(10, 10));
      expect(a.registerTap(nowMs: 1300, pos: const Offset(10, 10)), isFalse);
      expect(a.hasPending, isTrue);
    });

    test('位移超过 80px 不构成双击', () {
      final a = StageTapArbiter();
      a.registerTap(nowMs: 1000, pos: const Offset(0, 0));
      expect(a.registerTap(nowMs: 1100, pos: const Offset(100, 0)), isFalse);
    });

    test('clear 取消待定单击（拖动/翻页时调用）', () {
      final a = StageTapArbiter();
      a.registerTap(nowMs: 1000, pos: Offset.zero);
      a.clear();
      expect(a.hasPending, isFalse);
    });
  });

  group('§5 双击爱心参数', () {
    test('时长 700ms、尺寸 58dp、颜色 #FFFF3B5C、上浮 60dp', () {
      expect(kHeartAnimDuration, const Duration(milliseconds: 700));
      expect(kHeartSize, 58);
      expect(kHeartColor, const Color(0xFFFF3B5C));
      expect(kHeartRiseDistance, 60);
    });

    test('前 40% easeOut：0.6 → 1.15', () {
      expect(heartScaleAt(0), closeTo(0.6, 1e-9));
      expect(heartScaleAt(0.4), closeTo(1.15, 1e-9));
      final mid = heartScaleAt(0.2);
      expect(mid, greaterThan(0.6));
      expect(mid, lessThan(1.15));
    });

    test('后 60% elasticOut 回弹并收在 1.0', () {
      expect(heartScaleAt(1.0), closeTo(1.0, 1e-9));
      // elasticOut 会先冲过 1.0 再回落：0.4~1.0 之间应出现 <1.0 的回弹。
      var minV = 1.0;
      for (var i = 40; i <= 100; i++) {
        final v = heartScaleAt(i / 100);
        if (v < minV) minV = v;
      }
      expect(minV, lessThan(1.0));
    });

    test('opacity 1→0、位移 0→-60dp', () {
      expect(heartOpacityAt(0), 1);
      expect(heartOpacityAt(1), 0);
      expect(heartOpacityAt(0.5), closeTo(0.5, 1e-9));
      expect(heartRiseOffsetAt(0), 0);
      expect(heartRiseOffsetAt(1), -60);
      expect(heartRiseOffsetAt(0.5), closeTo(-30, 1e-9));
    });
  });

  group('§5 暂停播放图标淡出', () {
    test('0.8s easeOut，从 1 淡到 0', () {
      expect(kPlayHintFadeMs, 800);
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
