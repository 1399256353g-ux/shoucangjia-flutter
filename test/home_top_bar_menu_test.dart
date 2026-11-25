import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/home_top_bar.dart';

/// owner 2026-11-25：「主页的三点省略号点开还是 bug，不显示」。
///
/// 根因：`PopupMenuButton` 上写了 `constraints: tightFor(44, 44)`。
/// 这个约束虽然只写着按钮尺寸，Flutter 会把它作为**弹出菜单的宽度上限**，
/// 于是整个菜单被压成 44dp 宽、菜单项文字挤成 20×20 几乎不可见。
/// 真机实测：点开后 UI 树里只剩一个 77×77 的遮罩，没有任何菜单项文本。
///
/// 这组测试钉住「菜单项必须有正常宽度」，防止约束又被加回去。
List<TopBarAction> _sevenActions() => <TopBarAction>[
      for (final p in <List<Object>>[
        ['refresh', '总刷新', Icons.refresh],
        ['search', '搜索', Icons.search],
        ['folders', '文件结构 / 节点文件夹', Icons.account_tree_outlined],
        ['recommend', '推荐', Icons.auto_awesome],
        ['authors', '作者', Icons.people_alt_outlined],
        ['rank', '排行榜', Icons.leaderboard_outlined],
        ['settings', '设置', Icons.settings],
      ])
        TopBarAction(
          id: p[0] as String,
          tooltip: p[1] as String,
          icon: p[2] as IconData,
          onPressed: () {},
        ),
    ];

Widget _host(List<TopBarAction> actions, {double? width}) => MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('媒体库'),
          actions: [HomeTopBar(actions: actions, availableWidth: width)],
        ),
        body: const SizedBox.expand(),
      ),
    );

void main() {
  group('「⋯」菜单必须可读', () {
    testWidgets('菜单项宽度不能被压成按钮尺寸', (tester) async {
      await tester.pumpWidget(_host(_sevenActions()));
      await tester.pumpAndSettle();

      final more = find.byKey(const ValueKey('topbar-more'));
      expect(more, findsOneWidget, reason: '七项动作必须产生溢出菜单');

      await tester.tap(more);
      await tester.pumpAndSettle();

      final items = find.byType(PopupMenuItem<TopBarAction>);
      expect(items.evaluate().length, greaterThan(0), reason: '菜单没有弹出');
      for (var i = 0; i < items.evaluate().length; i++) {
        final sz = tester.getSize(items.at(i));
        expect(sz.width, greaterThan(100),
            reason: '菜单项被压成 ${sz.width}dp，文字会看不见');
        expect(sz.height, greaterThan(32));
      }
    });

    testWidgets('菜单文字有实际宽度（不是 20×20）', (tester) async {
      await tester.pumpWidget(_host(_sevenActions()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topbar-more')));
      await tester.pumpAndSettle();

      const label = '文件结构 / 节点文件夹';
      final txt = find.text(label);
      expect(txt, findsOneWidget);
      final sz = tester.getSize(txt);
      expect(sz.width, greaterThan(60), reason: '文字被挤扁：${sz.width}dp');
    });

    testWidgets('菜单项可点击且回调到对应动作', (tester) async {
      var tapped = '';
      final actions = <TopBarAction>[
        for (final a in _sevenActions())
          TopBarAction(
              id: a.id,
              tooltip: a.tooltip,
              icon: a.icon,
              onPressed: () => tapped = a.id),
      ];
      await tester.pumpWidget(_host(actions));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topbar-more')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('推荐'));
      await tester.pumpAndSettle();
      expect(tapped, 'recommend');
    });

    testWidgets('设置常驻尾位，不进溢出菜单', (tester) async {
      await tester.pumpWidget(_host(_sevenActions()));
      await tester.pumpAndSettle();
      // 设置直接可见
      expect(find.byKey(const ValueKey('topbar-settings')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topbar-more')));
      await tester.pumpAndSettle();
      // 菜单里不应再有设置
      expect(find.byKey(const ValueKey('topbar-menu-settings')), findsNothing);
    });
  });
}
