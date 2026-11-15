import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';

BasicLib basic(String id, String rel, {int authors = 1, int works = 10}) =>
    BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: authors,
      works: works,
    );

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final tree = buildUnitTree(
    nodes: const [
      LibNode(id: 'big-01', rel: '(1) A', name: '(1) A'),
      LibNode(id: 'big-02', rel: '(2) B', name: '(2) B'),
    ],
    basics: [
      basic('l1', '(1) A/x', authors: 3, works: 30),
      basic('l2', '(2) B/y', authors: 5, works: 50),
    ],
  )!;

  testWidgets('主页只铺单元库卡片 + 星标入口', (t) async {
    var opened = '';
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: tree,
      stars: const {'l1'},
      onOpenUnit: (u) => opened = u.id,
      onToggleStar: (_) {},
      onTapBasic: (_) {},
      onOpenStars: () => opened = 'stars',
    )));

    expect(find.text('单元库'), findsOneWidget);
    expect(find.byKey(const ValueKey('starred-entry')), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);
    // 主页只给顶级单元库一张卡；下级单元库不铺在主页
    expect(find.byKey(ValueKey('unit-${tree.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('unit-big-01')), findsNothing);
    expect(find.byKey(const ValueKey('unit-big-02')), findsNothing);
    // 基础库卡片也不在主页出现（层级递减：点进单元库才有）
    expect(find.byKey(const ValueKey('basic-card-l1')), findsNothing);

    await t.tap(find.byKey(ValueKey('unit-${tree.id}')));
    expect(opened, tree.id);
  });

  testWidgets('单元库页显示基础库卡片与词条', (t) async {
    await t.pumpWidget(host(UnitLibraryPage(
      unit: tree.children.first,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleStar: (_) {},
      onTapBasic: (_) {},
    )));

    expect(find.text('基础库'), findsOneWidget);
    expect(find.byKey(const ValueKey('basic-card-l1')), findsOneWidget);
    expect(find.byKey(const ValueKey('star-card-l1')), findsOneWidget);
    // 词条文本去掉「(序号) 」前缀
    expect(BasicLibCard.badgeText('(8) 🦶'), '🦶');
  });

  testWidgets('非顶级单元库显示爬虫配置入口并可打开', (t) async {
    String? opened;
    await t.pumpWidget(host(UnitLibraryPage(
      unit: tree.children.first,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleStar: (_) {},
      onTapBasic: (_) {},
      onConfigureUnit: (u) => opened = u.id,
    )));
    final btn = find.byKey(const ValueKey('unit-crawler-big-01'));
    expect(btn, findsOneWidget);
    await t.tap(btn);
    expect(opened, 'big-01');
  });

  testWidgets('顶级单元库不显示爬虫配置入口', (t) async {
    await t.pumpWidget(host(UnitLibraryPage(
      unit: tree,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleStar: (_) {},
      onTapBasic: (_) {},
      onConfigureUnit: (_) {},
    )));
    expect(find.byKey(const ValueKey('unit-crawler-secret')), findsNothing);
  });

  testWidgets('星标页空态有引导文案', (t) async {
    await t.pumpWidget(host(StarredLibrariesPage(
      basics: const [],
      onToggleStar: (_) {},
      onTapBasic: (_) {},
    )));
    expect(find.textContaining('还没有星标的基础库'), findsOneWidget);
  });

  testWidgets('星标页列出星标基础库并支持取消', (t) async {
    String? toggled;
    await t.pumpWidget(host(StarredLibrariesPage(
      basics: [basic('l2', '(2) B/y')],
      onToggleStar: (b) => toggled = b.id,
      onTapBasic: (_) {},
    )));
    expect(find.byKey(const ValueKey('basic-card-l2')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('star-card-l2')));
    expect(toggled, 'l2');
  });
}
