/// 第八十批契约（0.9.314）：**「这块内容在屏幕里到底有多大」没人算过** +
/// **写给人看的字里混进了脚本视角的字段**。
///
/// 前几批抓的是「同一个判定多个副本」「同一个数字两处算法」。这一批的两件事
/// 都是「变量有值、结果不报错，但那个值回答的不是这个问题」：
///
/// 1. 首页媒体库网格是整页 `ListView` 里的 `shrinkWrap` 网格。它的
///    `LayoutBuilder` 高度恒为 `infinity`（滚动方向不受约束），而
///    `MediaQuery.size` 是整窗口（上方还压着计数行与星标入口卡）。
///    `prefetchCount` 对非有限高度按「一行」收手、对整窗口按「全部」算——
///    两个都不报错，只是一个少预热一屏、一个多预热一行屏幕外的图。
///    真正要的数只能从渲染树读：视口高度 − 本块在视口内的偏移。
/// 2. `exit 0` / `pid=12345` / `1/3` 是脚本与接口的字段。用户既不知道 0 是好
///    是坏，也不知道分母 3 指什么。同一条「退出码怎么念」此前在同步日志与
///    爬虫配置页各写一遍。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/scroll_viewport.dart';
import 'package:shoucangjia/sync_ledger.dart';

/// 只保留非注释行，避免文档里的「旧写法」被契约扫描当成现役代码。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 一个类体的源码（从 `class X` 到下一个 `class ` 之前）。
String _classBody(String src, String name) {
  final start = src.indexOf('class $name');
  expect(start, isNonNegative, reason: '找不到 $name');
  final rest = src.substring(start + 1);
  final next = rest.indexOf('\nclass ');
  return next < 0 ? rest : rest.substring(0, next);
}

void main() {
  group('首页网格的预热尺寸来自"屏幕里的那一块"（0.9.314）', () {
    testWidgets('可视高度 = 视口高 − 偏移，并用自身高度收顶', (tester) async {
      final key = GlobalKey();
      final scroll = ScrollController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ListView(
              controller: scroll,
              children: [
                const SizedBox(height: 100),
                // 自身 200 高，偏移 100：可见 = 400 − 100 = 300 > 200，取自身。
                SizedBox(
                  key: key,
                  height: 200,
                  child: const ColoredBox(color: Color(0xFF000000)),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(visibleViewportOf(key), const Size(800, 200),
          reason: '完全可见时按自身高度');

      // 往上滚 250：偏移 −150 → 可见 550，仍被自身 200 收顶。
      scroll.jumpTo(250);
      await tester.pumpAndSettle();
      final s = visibleViewportOf(key);
      expect(s, isNotNull);
      expect(s!.height, 200);
    });

    testWidgets('本块整块滚出视口时返回 0（不是负数、不是自身高度）', (tester) async {
      final key = GlobalKey();
      final scroll = ScrollController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ListView(
              controller: scroll,
              children: [
                const SizedBox(height: 600),
                SizedBox(
                  key: key,
                  height: 300,
                  child: const ColoredBox(color: Color(0xFF000000)),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // 偏移 600 > 视口 400：整块在屏幕下方。
      expect(visibleViewportOf(key)!.height, 0);

      scroll.jumpTo(600);
      await tester.pumpAndSettle();
      expect(visibleViewportOf(key)!.height, 300, reason: '滚到本块顶部对齐时全可见');
    });

    testWidgets('不在滚动容器里时按自身尺寸返回', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            key: key,
            width: 320,
            height: 180,
            child: const ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(visibleViewportOf(key), const Size(320, 180));
    });

    test('key 没有挂上时返回 null（不猜一个尺寸出来）', () {
      expect(visibleViewportOf(GlobalKey()), isNull);
    });

    test('首页不再拿整窗口当网格高度，也不拿 infinity 当高度', () {
      final src = _code('lib/unit_library_view.dart');
      final body = _classBody(src, '_UnitLibraryHomeViewState');
      expect(body.contains('visibleViewportOf(_gridKey)'), isTrue,
          reason: '几何只有 scroll_viewport 一处');
      expect(body.contains('viewport: mq.size'), isFalse,
          reason: '整窗口不是这块网格的可见高度');
      expect(RegExp(r'_gridViewport = cons\.biggest').hasMatch(body), isFalse,
          reason: 'shrinkWrap 网格的 LayoutBuilder 高度恒为 infinity');
      // 布局阶段不 setState（与 `_gridViewport` 系列同一条规矩）。
      expect(
          RegExp(r'_gridViewport = v;\s*setState')
              .hasMatch(body.replaceAll(RegExp(r'\n\s*'), ' ')),
          isFalse);
    });
  });

  group('预热只求值到配额用完为止（惰性列表）', () {
    test('库卡片四个调用点都传惰性 Iterable，不再先物化整张列表', () {
      for (final f in <String>[
        'lib/unit_library_view.dart',
      ]) {
        final src = _code(f);
        // `items: [` 是列表字面量：会先为每一张卡片跑一遍封面链。
        expect(RegExp(r'items:\s*\[$', multiLine: true).hasMatch(src), isFalse,
            reason: '$f 又用列表字面量物化了预热条目');
        expect(RegExp(r'items:\s*units\.map\(').allMatches(src).length, 2,
            reason: '主页 1 + 星标页 1');
        expect(RegExp(r'items:\s*unit\.children\.map\(').hasMatch(src), isTrue);
        expect(RegExp(r'items:\s*unit\.basics\.map\(').hasMatch(src), isTrue);
      }
    });

    test('作品卡片两个调用点同样惰性', () {
      final basic = _code('lib/basic_lib_page.dart');
      expect(RegExp(r'items:\s*shown\.map\(').hasMatch(basic), isTrue,
          reason: '基础库页：已渲染 60 张，只预热前 24 张');
      final main = _code('lib/main.dart');
      expect(RegExp(r'items:\s*works\.map\(').hasMatch(main), isTrue,
          reason: '作者主页/收藏夹可能上千条');
    });

    test('惰性 Iterable 语义：只取到 limit 就不再多算', () {
      var evaluated = 0;
      Iterable<int> src() sync* {
        for (var i = 0; i < 1000; i++) {
          evaluated++;
          yield i;
        }
      }

      // 与 `libCoverPrefetchRequests` / `prefetchThumbItems` 同一个取法。
      final taken = <int>[];
      for (final v in src()) {
        if (taken.length >= 8) break;
        taken.add(v);
      }
      expect(taken.length, 8);
      // 生成器按「先产出再让调用方决定」推进：第 9 个元素已被产出后才轮到
      // 循环顶部的 break。真实实现（`libCoverPrefetchRequests`）同样是
      // 「顶部判配额再取」，所以上限是 limit + 1 次求值，不是 1000 次。
      expect(evaluated, 9, reason: '写成 List 会算 1000 次');
    });
  });

  group('退出码只有一种说法（0.9.314）', () {
    test('syncExitLabel 三态', () {
      expect(syncExitLabel(null), '');
      expect(syncExitLabel(0), '已完成');
      expect(syncExitLabel(1), '退出码 1（有失败）');
      expect(syncExitLabel(137), '退出码 137（有失败）');
    });

    test('同步日志与爬虫配置页都读同一个出口，不再各自拼 exit', () {
      for (final f in <String>[
        'lib/sync_log_panel.dart',
        'lib/unit_crawler_page.dart',
      ]) {
        final src = _code(f);
        expect(src.contains('syncExitLabel('), isTrue, reason: '$f 没用出口');
        expect(RegExp(r"exit \$\{").hasMatch(src), isFalse,
            reason: '$f 还在自己拼 "exit N"');
        expect(RegExp(r"' · exit ").hasMatch(src), isFalse);
      }
    });

    test('全 lib 界面文案不再出现裸 exit / pid=', () {
      for (final f in <String>[
        'lib/main.dart',
        'lib/sync_log_panel.dart',
        'lib/unit_crawler_page.dart',
      ]) {
        final src = _code(f);
        expect(RegExp(r"pid=\$\{").hasMatch(src), isFalse,
            reason: '$f 把进程号写成了"pid=…"');
      }
    });
  });

  group('快检上限写成句子，不留 1/3 这种分母（0.9.314）', () {
    test('爬虫配置页的运行摘要', () {
      final src = _code('lib/unit_crawler_page.dart');
      expect(src.contains('本小时已快检'), isTrue);
      expect(src.contains('每小时最多 3 次'), isTrue);
      expect(RegExp(r'本小时快检 \$qh/3').hasMatch(src), isFalse,
          reason: '分母 3 没有任何来源说明');
    });
  });
}
