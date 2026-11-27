import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_controls.dart';

void main() {
  group('P1 §1 互动栏：点赞删除后无残留', () {
    // owner 2026-11-23 删除双击点赞后，右侧互动栏整块成为无调用死代码；
    // 本组断言「不是忘了接，而是确实不再有这块 UI」，防止有人把它加回来
    // 又不接调用点，退化成只在测试里通过的假功能。
    test('lib/ 下没有任何互动栏调用点', () {
      final lib = Directory('lib');
      final hits = <String>[];
      for (final f in lib.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('player_controls.dart')) continue;
        final src = f.readAsStringSync().replaceAll('\r\n', '\n');
        if (src.contains('PlayerInteractionRail')) hits.add(f.path);
      }
      expect(hits, isEmpty);
    });
  });

  group('P1 §2 信息区：无第二套实现', () {
    // 与「去点赞」同一类问题：`player_controls.dart` 里的 PlayerInfoPanel /
    // MarqueeText / 文案展开判定曾是播放页信息区的**第二套实现**，而真正
    // 渲染在 main.dart 里的信息区从来没用过它们。于是测试绿着、界面上那块
    // 组件永远不出现——测试在为一个不存在的界面作证。
    //
    // 现在整块删除，并把「确实只有一套」变成可执行断言：
    //  - lib/ 下不得再出现 PlayerInfoPanel / MarqueeText；
    //  - 信息区宽度常量仍只有 kRailReservedWidth（舞台长按热区要用）。
    test('lib/ 下没有任何信息区第二套实现', () {
      final lib = Directory('lib');
      final hits = <String>[];
      for (final f in lib.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync().replaceAll('\r\n', '\n');
        if (src.contains('PlayerInfoPanel') || src.contains('class MarqueeText')) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty);
    });

    test('信息区宽度预留仍只有一处来源', () {
      // 84 = 44 头像 + 10 右边距 + 余量；舞台长按热区的 rightInset 仍在用。
      expect(kRailReservedWidth, 84);

      final lib = Directory('lib');
      final decls = <String>[];
      for (final f in lib.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final line in f.readAsLinesSync()) {
          if (line.startsWith('const double kRailReservedWidth')) {
            decls.add(f.path);
          }
        }
      }
      expect(decls.length, 1, reason: '常量只允许声明一次');
    });
  });

  group('P1 §4 任务栏', () {
    test('间距：默认 28、320 窄屏 20、并夹在最低 16', () {
      expect(taskbarSpacingFor(375), 28);
      expect(taskbarSpacingFor(390), 28);
      expect(taskbarSpacingFor(360), 28);
      expect(taskbarSpacingFor(320), 20);
      expect(taskbarSpacingFor(300), 20);
      expect(taskbarSpacingFor(340), closeTo(24, 1e-9));
      expect(taskbarSpacingFor(double.nan), 28);
      expect(kTaskbarHeight, 56);
      expect(kTaskbarIconSize, 24);
      expect(kTaskbarSidePadding, 16);
      expect(kTaskbarDividerColor, const Color(0x1AFFFFFF));
      expect(kTaskbarInactiveColor, const Color(0xB3FFFFFF));
    });
  });
}
