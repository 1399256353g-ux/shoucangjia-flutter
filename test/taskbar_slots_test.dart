import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/taskbar_layout.dart';

/// 任务栏排布：owner 2026-11-22 规格的可执行版本。
///
/// 核心断言是「不靠缩放掩盖溢出」：放不下时必须真的把低优先级槽位
/// 收进「更多」，而不是把按钮整体缩小到点不中。
void main() {
  double w(TaskbarSlot s) => switch (s) {
        TaskbarSlot.play => 48,
        TaskbarSlot.episodes => 44,
        TaskbarSlot.settings => 44,
        TaskbarSlot.autoplay => 44,
        TaskbarSlot.loop => 44,
        TaskbarSlot.shuffle => 44,
        TaskbarSlot.sound => 44,
        TaskbarSlot.volume => 104,
        TaskbarSlot.drop => 44,
        TaskbarSlot.display => 44,
      };

  group('放得下', () {
    test('全部可见时顺序不变、无溢出', () {
      final p = taskbarPlan(
        items: const [TaskbarSlot.episodes, TaskbarSlot.settings],
        availableWidth: 400,
        widthOf: w,
      );
      expect(p.visible, [TaskbarSlot.episodes, TaskbarSlot.settings]);
      expect(p.hasOverflow, isFalse);
    });

    test('空列表返回空', () {
      final p = taskbarPlan(
          items: const [], availableWidth: 300, widthOf: w);
      expect(p.visible, isEmpty);
      expect(p.overflow, isEmpty);
    });
  });

  group('放不下时按优先级取舍', () {
    test('窄屏保留播放与显示，「播放设置」最先被收进更多', () {
      final p = taskbarPlan(
        items: const [
          TaskbarSlot.play,
          TaskbarSlot.episodes,
          TaskbarSlot.settings,
          TaskbarSlot.sound,
          TaskbarSlot.drop,
          TaskbarSlot.display,
        ],
        availableWidth: 200,
        widthOf: w,
        maxVisible: 5,
      );
      expect(p.hasOverflow, isTrue);
      expect(p.visible, contains(TaskbarSlot.play));
      expect(p.visible, contains(TaskbarSlot.display));
      // 规格点名「播放设置」可并入菜单 → 它必须在溢出里。
      expect(p.overflow, contains(TaskbarSlot.settings));
      // 可见顺序仍保持传入顺序，不发生跳位。
      final order = const [
        TaskbarSlot.play,
        TaskbarSlot.episodes,
        TaskbarSlot.settings,
        TaskbarSlot.sound,
        TaskbarSlot.drop,
        TaskbarSlot.display,
      ];
      final idx = p.visible.map(order.indexOf).toList();
      expect(idx, orderedEquals([...idx]..sort()));
    });

    test('可见按钮数不超过 maxVisible', () {
      final p = taskbarPlan(
        items: const [
          TaskbarSlot.play,
          TaskbarSlot.episodes,
          TaskbarSlot.settings,
          TaskbarSlot.sound,
          TaskbarSlot.drop,
        ],
        availableWidth: 2000,
        widthOf: w,
        maxVisible: 3,
      );
      expect(p.visible.length, lessThanOrEqualTo(3));
      expect(p.hasOverflow, isTrue);
    });

    test('优先级最高槽位永远保留，即使宽度不够', () {
      final p = taskbarPlan(
        items: const [TaskbarSlot.play, TaskbarSlot.settings],
        availableWidth: 10,
        widthOf: w,
        maxVisible: 5,
      );
      expect(p.visible, contains(TaskbarSlot.play));
    });

    test('「更多」按钮自身宽度计入预算，不会被裁掉', () {
      // 3 个 44dp = 132dp 刚好等于「2 个 44dp + 44dp 更多」的前一档：
      // 给 110dp 时放不下全部，必须真的留出「更多」的位置。
      final p = taskbarPlan(
        items: const [
          TaskbarSlot.play,
          TaskbarSlot.settings,
          TaskbarSlot.drop,
        ],
        availableWidth: 110,
        widthOf: (s) => 44,
        maxVisible: 5,
      );
      expect(p.hasOverflow, isTrue);
      final visibleW = p.visible.fold(0.0, (a, s) => a + 44);
      expect(visibleW + kTaskbarMoreWidth, lessThanOrEqualTo(110));
    });

    test('桌面端宽音量模块按真实宽度参与预算', () {
      final wide = taskbarPlan(
        items: const [TaskbarSlot.play, TaskbarSlot.volume],
        availableWidth: 200,
        widthOf: w,
        maxVisible: 99,
      );
      expect(wide.visible, contains(TaskbarSlot.volume));
      final narrow = taskbarPlan(
        items: const [TaskbarSlot.play, TaskbarSlot.volume],
        availableWidth: 100,
        widthOf: w,
        maxVisible: 99,
      );
      // 48 + 104 > 100 → 音量模块进菜单，播放保留。
      expect(narrow.visible, [TaskbarSlot.play]);
      expect(narrow.overflow, [TaskbarSlot.volume]);
    });
  });

  group('优先级表', () {
    test('播放/显示在主位，播放设置排在最后', () {
      expect(kKeepPriority[TaskbarSlot.play]!,
          lessThan(kKeepPriority[TaskbarSlot.settings]!));
      expect(kKeepPriority[TaskbarSlot.display]!,
          lessThan(kKeepPriority[TaskbarSlot.settings]!));
      expect(kKeepPriority[TaskbarSlot.settings],
          kKeepPriority.values.reduce((a, b) => a > b ? a : b));
    });
  });

  group('更多按钮', () {
    testWidgets('点击菜单项回调对应槽位', (tester) async {
      TaskbarSlot? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskbarMoreButton(
            items: const [TaskbarSlot.settings, TaskbarSlot.sound],
            labelOf: (s) => s.name,
            onSelected: (s) => picked = s,
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('taskbar-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('taskbar-more-settings')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('taskbar-more-settings')));
      await tester.pumpAndSettle();
      expect(picked, TaskbarSlot.settings);
    });

    testWidgets('触达区不小于 44dp', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskbarMoreButton(
            items: const [TaskbarSlot.sound],
            labelOf: (s) => s.name,
            onSelected: (_) {},
            width: 20,
          ),
        ),
      ));
      final size = tester.getSize(find.byKey(const Key('taskbar-more')));
      expect(size.width, greaterThanOrEqualTo(44));
    });
  });
}
