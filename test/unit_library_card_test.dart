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

  testWidgets('单元库卡片：与基础库同圆角，但更高、封面更大', (t) async {
    await t.pumpWidget(host(UnitLibraryCard(unit: unit, onTap: () {})));

    final rect = t.getRect(find.byKey(ValueKey('unit-card-${unit.id}')));
    expect(rect.height, UnitLibraryCard.height);
    expect(UnitLibraryCard.height, 150);

    final cover = t.getSize(find.byKey(ValueKey('unit-cover-${unit.id}')));
    expect(cover.width, 72);
    expect(cover.height, 72);

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
    // 词条与标题都显示单元库名（与基础库卡片一致）。
    expect(find.text('(1) A'), findsNWidgets(2));
    expect(find.text('3 作者 · 30 作品'), findsOneWidget);
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
    // 贴右上角
    expect(btn.top - card.top, lessThan(4));
    expect(card.right - btn.right, lessThan(20));

    // 星标在右下角，两者不重叠
    final star = t.getRect(find.byKey(ValueKey('unit-star-${unit.id}')));
    expect(star.center.dy - card.top, greaterThan(90));
    expect(star.top, greaterThanOrEqualTo(btn.bottom));

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
