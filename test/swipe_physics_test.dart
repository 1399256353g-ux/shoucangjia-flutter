import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/swipe_physics.dart';

class _Metrics extends FixedScrollMetrics {
  _Metrics({
    required double pixels,
    required double max,
    double viewport = 400,
  }) : super(
          minScrollExtent: 0,
          maxScrollExtent: max,
          pixels: pixels,
          viewportDimension: viewport,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1,
        );
}

void main() {
  group('dampedDragOffset', () {
    test('正常范围内 1:1 跟手', () {
      expect(dampedDragOffset(12, outOfRange: false), 12);
      expect(dampedDragOffset(-40, outOfRange: false), -40);
    });

    test('越界拖动按 28% 衰减', () {
      expect(dampedDragOffset(100, outOfRange: true), closeTo(28, 0.001));
      expect(dampedDragOffset(-100, outOfRange: true), closeTo(-28, 0.001));
    });

    test('非法阻尼系数被夹紧', () {
      expect(dampedDragOffset(10, outOfRange: true, overscrollFactor: 2),
          closeTo(10, 0.001));
      expect(dampedDragOffset(10, outOfRange: true, overscrollFactor: -1),
          closeTo(0, 0.001));
    });
  });

  group('snapTargetPage', () {
    test('无速度时吸附最近整页', () {
      expect(snapTargetPage(page: 1.2, velocity: 0), 1);
      expect(snapTargetPage(page: 1.7, velocity: 0), 2);
    });

    test('向上甩动加半页后吸附到下一页', () {
      // velocity 为负表示向下一页（放大 page？）——按惯性方向加半页
      expect(snapTargetPage(page: 1.1, velocity: 600), 2);
      expect(snapTargetPage(page: 1.9, velocity: -600), 1);
    });

    test('速度不足阈值时不额外推进', () {
      expect(snapTargetPage(page: 1.1, velocity: 0.2), 1);
    });

    test('目标页夹在 0–末页之间', () {
      expect(snapTargetPage(page: 0.1, velocity: -600), 0);
      expect(snapTargetPage(page: 4.9, velocity: 600, maxPage: 4), 4);
      expect(snapTargetPage(page: 2.2, velocity: 0, maxPage: 1), 1);
    });
  });

  group('DiziPageScrollPhysics', () {
    test('applyTo 保留自定义弹簧参数', () {
      const p = DiziPageScrollPhysics(stiffness: 500, dampingRatio: 0.9);
      final q = p.applyTo(const ClampingScrollPhysics());
      expect(q, isA<DiziPageScrollPhysics>());
      expect(q.stiffness, 500);
      expect(q.dampingRatio, 0.9);
      expect(q.parent, isA<ClampingScrollPhysics>());
    });

    test('越界拖动被阻尼', () {
      const physics = DiziPageScrollPhysics();
      final m = _Metrics(pixels: -30, max: 800);
      expect(physics.applyPhysicsToUserOffset(m, 100), closeTo(28, 0.001));
    });

    test('松手后吸附到最近页并收敛', () {
      const physics = DiziPageScrollPhysics();
      final m = _Metrics(pixels: 450, max: 800); // 1.125 页
      final sim = physics.createBallisticSimulation(m, 0);
      expect(sim, isNotNull);
      expect(sim!.x(0), closeTo(450, 0.001));
      expect(sim.x(1), closeTo(400, 1));
      expect(sim.isDone(1), isTrue);
    });

    test('已在整页且静止时不产生多余动画', () {
      const physics = DiziPageScrollPhysics();
      final m = _Metrics(pixels: 800, max: 800);
      expect(physics.createBallisticSimulation(m, 0), isNull);
    });
  });

  test('程序化翻页使用更短时长', () {
    expect(pageTurnDuration.inMilliseconds, lessThan(180));
    expect(pageTurnCurve, Curves.easeOutCubic);
  });
}
