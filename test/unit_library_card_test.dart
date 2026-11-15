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
  final unit = tree.children.first;

  testWidgets('单元库卡片：与基础库同卡片形状（圆角 12、封面更大）', (t) async {
    await t.pumpWidget(host(UnitLibraryCard(unit: unit, onTap: () {})));

    final card = t.getRect(find.byKey(ValueKey('unit-card-${unit.id}')));
    final cover = t.getSize(find.byKey(ValueKey('unit-cover-${unit.id}')));
    // 封面铺满整张卡片。
    expect(cover.width, card.width);
    expect(cover.height, card.height);

    // 圆角与基础库卡片一致（12）。
    final mat = t.widget<Material>(find
        .ancestor(
            of: find.byKey(ValueKey('unit-card-${unit.id}')),
            matching: find.byType(Material))
        .first);
    expect(mat.borderRadius, BorderRadius.circular(12));
  });

  testWidgets('单元库卡片：标题 + 作者/作品数', (t) async {
    await t.pumpWidget(host(UnitLibraryCard(unit: unit, onTap: () {})));
    // 不再贴来源词条：只显示一次名称，统计与基础库数量合并一行。
    expect(find.text('(1) A'), findsOneWidget);
    expect(find.textContaining('3 作者 · 30 作品'), findsOneWidget);
  });

  testWidgets('爬虫配置入口在卡片右上角', (t) async {
    String? opened;
    await t.pumpWidget(host(UnitLibraryCard(
      unit: unit,
      onTap: () {},
      onToggleStar: () {},
      onConfigure: () => opened = unit.id,
    )));

    final card = t.getRect(find.byKey(ValueKey('unit-card-${unit.id}')));
    final btn =
        t.getRect(find.byKey(ValueKey('unit-crawler-${unit.id}')));
    // 右上角操作区（与基础库卡片的顶部封面行一致）
    expect(btn.top - card.top, lessThan(64));
    expect(card.right - btn.right, lessThan(64));

    // 星标同排、不与爬虫入口重叠
    final star = t.getRect(find.byKey(ValueKey('unit-star-${unit.id}')));
    expect((star.center.dy - btn.center.dy).abs(), lessThan(2));
    expect(star.left, greaterThanOrEqualTo(btn.right));

    await t.tap(find.byKey(ValueKey('unit-crawler-${unit.id}')));
    expect(opened, unit.id);
    expect(opened, isNotNull);
  });

  testWidgets('顶级单元库卡片不显示爬虫入口', (t) async {
    await t.pumpWidget(host(UnitLibraryCard(
      unit: tree,
      onTap: () {},
      onConfigure: () {},
    )));
    expect(find.byKey(ValueKey('unit-crawler-${tree.id}')), findsNothing);
    expect(UnitLibraryCard.canConfigure(tree), isFalse);
    expect(UnitLibraryCard.canConfigure(unit), isTrue);
  });

  testWidgets('进入单元库后不再显示自身卡片，爬虫入口在标题栏', (t) async {
    String? opened;
    await t.pumpWidget(host(UnitLibraryPage(
      unit: unit,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onConfigureUnit: (u) => opened = u.id,
    )));
    // 自身卡片不再重复显示；爬虫配置改到 AppBar 右上角。
    expect(find.byKey(ValueKey('unit-card-${unit.id}')), findsNothing);
    await t.tap(find.byKey(ValueKey('unit-crawler-${unit.id}')));
    expect(opened, unit.id);
  });
}
