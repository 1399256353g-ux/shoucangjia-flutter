import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/home_top_bar.dart';
import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/refresh_all.dart';

TopBarAction act(String id) => TopBarAction(
    id: id, tooltip: id, icon: Icons.circle, onPressed: () {});

ServerConn conn(String id, {bool enabled = true, String base = 'http://x'}) =>
    ServerConn(id: id, label: id, base: base, user: 'u', pass: 'p',
        enabled: enabled);

void main() {
  group('顶部任务栏排布', () {
    test('宽屏放得下时不出现「⋯」，可见数不超过 4', () {
      final l = topBarLayout(width: 600, actions: [act('refresh'), act('search')]);
      expect(l.visible.length, 2);
      expect(l.hasOverflow, isFalse);
    });

    test('窄屏超过上限的动作进「⋯」，可见数 ≤4', () {
      final ids = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      final l = topBarLayout(
          width: 300, actions: [for (final id in ids) act(id)]);
      expect(l.visible.length, lessThanOrEqualTo(kTopBarMaxVisible));
      expect(l.hasOverflow, isTrue);
      expect(l.visible.length + l.overflow.length, ids.length);
      // 顺序不变：前 N 个常驻，其余按原顺序进菜单（不重排、不丢项）。
      expect(l.visible.map((a) => a.id).toList(),
          ids.take(l.visible.length).toList());
      expect(l.overflow.map((a) => a.id).toList(),
          ids.skip(l.visible.length).toList());
    });

    test('极窄宽度仍保留至少一格常驻 + 一格「⋯」', () {
      final l = topBarLayout(width: 60, actions: [act('a'), act('b'), act('c')]);
      expect(l.visible.length, 1);
      expect(l.overflow.length, 2);
    });

    test('空动作列表不崩溃', () {
      final l = topBarLayout(width: 100, actions: const []);
      expect(l.visible, isEmpty);
      expect(l.hasOverflow, isFalse);
    });
  });

  group('TotalRefresh 编排', () {
    test('全部成功：在线数、库数正确，无错误', () async {
      var cleared = 0;
      var authors = 0;
      final out = await runTotalRefresh(
        servers: [conn('s1'), conn('s2')],
        probe: (_) async => 401,
        libraryCount: (_) async => 7,
        clearCoverCache: () async => cleared++,
        reloadAuthors: () async => authors++,
      );
      expect(out.online, 2);
      expect(out.libraries, 7);
      expect(out.firstError, isNull);
      expect(out.message, '已刷新 7 个库');
      expect(cleared, 1);
      expect(authors, 1);
    });

    test('部分连接失败：只记录第一条错误，缓存与作者索引仍执行', () async {
      var cleared = 0;
      final out = await runTotalRefresh(
        servers: [conn('bad'), conn('ok')],
        probe: (s) async => s.id == 'bad' ? 0 : 200,
        libraryCount: (s) async {
          if (s.id == 'bad') throw StateError('不应该请求已失败的连接');
          return 3;
        },
        clearCoverCache: () async => cleared++,
        reloadAuthors: () async {},
      );
      expect(out.online, 1);
      expect(out.libraries, 3);
      expect(out.firstError, isNotNull);
      expect(out.message.startsWith('刷新失败：'), isTrue);
      expect(cleared, 1);
    });

    test('探测抛异常不中断流程', () async {
      final out = await runTotalRefresh(
        servers: [conn('boom')],
        probe: (_) async => throw Exception('down'),
        libraryCount: (_) async => 1,
        clearCoverCache: () async {},
        reloadAuthors: () async {},
      );
      expect(out.online, 0);
      expect(out.firstError, contains('down'));
      expect(out.servers, 1);
    });

    test('已断连的连接不参与探测', () async {
      var probed = 0;
      final out = await runTotalRefresh(
        servers: [conn('off', enabled: false), conn('on')],
        probe: (_) async {
          probed++;
          return 200;
        },
        libraryCount: (_) async => 2,
        clearCoverCache: () async {},
        reloadAuthors: () async {},
      );
      expect(probed, 1);
      expect(out.servers, 1);
      expect(out.online, 1);
    });

    test('没有可用连接时提示明确', () async {
      final out = await runTotalRefresh(
        servers: const [],
        probe: (_) async => 200,
        libraryCount: (_) async => 0,
        clearCoverCache: () async {},
        reloadAuthors: () async {},
      );
      expect(out.message, '没有可用的连接');
    });

    test('索引失败也记录，但不影响返回库数', () async {
      final out = await runTotalRefresh(
        servers: [conn('s')],
        probe: (_) async => 200,
        libraryCount: (_) async => 5,
        clearCoverCache: () async {},
        reloadAuthors: () async => throw StateError('authors'),
      );
      expect(out.libraries, 5);
      expect(out.firstError, contains('authors'));
    });
  });

  group('总刷新防抖', () {
    test('首次允许', () {
      expect(totalRefreshAllowed(DateTime(2026, 11, 23, 10), null), isTrue);
    });

    test('5 秒内拒绝、之后允许', () {
      final t0 = DateTime(2026, 11, 23, 10);
      expect(totalRefreshAllowed(t0.add(const Duration(seconds: 3)), t0), isFalse);
      expect(totalRefreshAllowed(t0.add(const Duration(seconds: 5)), t0), isTrue);
      expect(totalRefreshAllowed(t0.add(const Duration(seconds: 9)), t0), isTrue);
    });
  });

  group('HomeTopBar 渲染', () {
    testWidgets('窄宽度下多余动作进「⋯」，刷新按钮触达 ≥40dp', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              HomeTopBar(availableWidth: 160, actions: [
                act('refresh'),
                act('search'),
                act('a'),
                act('b'),
                act('c'),
              ]),
            ],
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('topbar-more')), findsOneWidget);
      final btn = t.getSize(find.byKey(const ValueKey('topbar-refresh')));
      expect(btn.width, greaterThanOrEqualTo(40));
      expect(btn.height, greaterThanOrEqualTo(40));
    });

    testWidgets('刷新中显示转圈并禁用重复点击', (t) async {
      var taps = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              HomeTopBar(refreshing: true, actions: [
                TopBarAction(
                    id: 'refresh',
                    tooltip: '总刷新',
                    icon: Icons.refresh,
                    onPressed: () => taps++),
              ]),
            ],
          ),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('topbar-refresh')));
      await t.pump();
      expect(taps, 0);
    });

    testWidgets('「⋯」菜单列出全部溢出动作，且携带原动作', (t) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              HomeTopBar(availableWidth: 160, actions: [
                act('refresh'),
                act('search'),
                TopBarAction(
                    id: 'extra',
                    tooltip: '额外',
                    icon: Icons.settings,
                    onPressed: () {}),
                TopBarAction(
                    id: 'extra2',
                    tooltip: '额外2',
                    icon: Icons.info,
                    onPressed: () {}),
              ]),
            ],
          ),
        ),
      ));
      await t.tap(find.byKey(const ValueKey('topbar-more')));
      await t.pumpAndSettle();
      final items = t
          .widgetList<PopupMenuItem<TopBarAction>>(
              find.byType(PopupMenuItem<TopBarAction>))
          .toList();
      expect(items.length, 2);
      // 菜单项的值就是原动作对象（onSelected 直接调用它的 onPressed）。
      expect(items.map((e) => e.value!.id).toList(), ['extra', 'extra2']);
      expect(find.text('额外'), findsOneWidget);
    });
  });
}
