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

  group('pageSwipeTarget（Q 阈值）', () {
    test('轻拖 1/5 页即翻页', () {
      expect(pageSwipeTarget(page: 1.2, fromPage: 1, velocity: 0), 2);
      expect(pageSwipeTarget(page: 0.8, fromPage: 1, velocity: 0), 0);
    });

    test('拖 1/10 页回弹到起点页', () {
      expect(pageSwipeTarget(page: 1.1, fromPage: 1, velocity: 0), 1);
      expect(pageSwipeTarget(page: 0.9, fromPage: 1, velocity: 0), 1);
    });

    test('速度 >120 且方向一致才翻页', () {
      expect(pageSwipeTarget(page: 1.1, fromPage: 1, velocity: 600), 2);
      expect(pageSwipeTarget(page: 1.0, fromPage: 1, velocity: 600), 2);
      // 方向相反：回弹
      expect(pageSwipeTarget(page: 1.1, fromPage: 1, velocity: -600), 1);
      // 速度不够：回弹
      expect(pageSwipeTarget(page: 1.1, fromPage: 1, velocity: 80), 1);
    });

    test('快滑也只翻一页，不连翻两条', () {
      expect(pageSwipeTarget(page: 1.1, fromPage: 1, velocity: 4000), 2);
      expect(pageSwipeTarget(page: 1.6, fromPage: 1, velocity: 4000), 2);
    });

    test('目标页夹在 0–末页之间', () {
      expect(pageSwipeTarget(page: 0.1, fromPage: 0, velocity: -600), 0);
      expect(pageSwipeTarget(page: 4.9, fromPage: 4, velocity: 600, maxPage: 4), 4);
    });
  });

  group('DiziPageScrollPhysics', () {
    test('applyTo 保留自定义弹簧参数', () {
      const p = DiziPageScrollPhysics(stiffness: 500, dampingRatio: 0.9, fromPage: 3);
      final q = p.applyTo(const ClampingScrollPhysics());
      expect(q, isA<DiziPageScrollPhysics>());
      expect(q.stiffness, 500);
      expect(q.dampingRatio, 0.9);
      expect(q.fromPage, 3);
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

    test('落位收敛不超过 150ms（抖音手感基线）', () {
      const physics = DiziPageScrollPhysics();
      final m = _Metrics(pixels: 450, max: 800);
      final sim = physics.createBallisticSimulation(m, 0)!;
      var t = 0.0;
      while (!sim.isDone(t) && t < 1.0) {
        t += 0.008;
      }
      expect(t, lessThan(0.15), reason: '收敛 ${(t * 1000).round()}ms，太拖沓');
    });

    test('已在整页且静止时不产生多余动画', () {
      const physics = DiziPageScrollPhysics(fromPage: 2);
      final m = _Metrics(pixels: 800, max: 800);
      expect(physics.createBallisticSimulation(m, 0), isNull);
    });
  });

  test('程序化翻页使用更短时长', () {
    expect(pageTurnDuration.inMilliseconds, lessThan(180));
    expect(pageTurnCurve, Curves.easeOutCubic);
  });
}
