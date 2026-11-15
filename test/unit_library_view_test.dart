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
      stars: const {'big-01'},
      onOpenUnit: (u) => opened = u.id,
      onToggleUnitStar: (_) {},
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

  testWidgets('主页星标点的是单元库本身', (t) async {
    String? toggled;
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: tree,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (u) => toggled = u.id,
      onTapBasic: (_) {},
      onOpenStars: () {},
    )));
    await t.tap(find.byKey(ValueKey('unit-star-${tree.id}')));
    expect(toggled, tree.id);
  });

  testWidgets('单元库页显示基础库卡片与词条，基础库不再有星标', (t) async {
    await t.pumpWidget(host(UnitLibraryPage(
      unit: tree.children.first,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
    )));

    expect(find.text('基础库'), findsOneWidget);
    expect(find.byKey(const ValueKey('basic-card-l1')), findsOneWidget);
    expect(find.byKey(const ValueKey('star-card-l1')), findsNothing);
    // 词条文本去掉「(序号) 」前缀
    expect(BasicLibCard.badgeText('(8) 🦶'), '🦶');
  });

  testWidgets('下级单元库卡片可星标', (t) async {
    // 造一个带下级单元库的层级
    final nested = buildUnitTree(
      nodes: const [
        LibNode(id: 'big-01', rel: '(1) A', name: '(1) A'),
        LibNode(id: 'big-01-sub', rel: '(1) A/sub', name: 'sub'),
      ],
      basics: [basic('l1', '(1) A/sub/x')],
    )!;
    String? toggled;
    await t.pumpWidget(host(UnitLibraryPage(
      unit: nested.children.first,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (u) => toggled = u.id,
      onTapBasic: (_) {},
    )));
    final btn = find.byKey(const ValueKey('unit-star-big-01-sub'));
    expect(btn, findsOneWidget);
    await t.tap(btn);
    expect(toggled, isNotNull);
  });

  testWidgets('非顶级单元库显示爬虫配置入口并可打开', (t) async {
    String? opened;
    await t.pumpWidget(host(UnitLibraryPage(
      unit: tree.children.first,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
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
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onConfigureUnit: (_) {},
    )));
    expect(find.byKey(const ValueKey('unit-crawler-secret')), findsNothing);
  });

  testWidgets('星标单元库页空态有引导文案', (t) async {
    await t.pumpWidget(host(StarredUnitsPage(
      units: const [],
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
    )));
    expect(find.textContaining('还没有星标的单元库'), findsOneWidget);
  });

  testWidgets('星标单元库页列出星标单元库并支持取消', (t) async {
    String? toggled;
    await t.pumpWidget(host(StarredUnitsPage(
      units: [tree.children.first],
      onOpenUnit: (_) {},
      onToggleUnitStar: (u) => toggled = u.id,
    )));
    expect(find.byKey(const ValueKey('unit-big-01')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('unit-star-big-01')));
    expect(toggled, 'big-01');
  });
}
