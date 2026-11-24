import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';

BasicLib basic(String id, String rel) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 2,
      works: 20,
    );

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() {
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.topOfUnit.clear();
    LibraryBadge.leafUnits.clear();
    UnitBadgeRegistry.order.clear();
  });

  final tree = buildUnitTree(
    nodes: const [
      LibNode(id: 'top-1', rel: 'T1', name: 'T1'),
    ],
    basics: [basic('b1', 'T1/x')],
  )!;

  testWidgets('首页卡片只用 owner 设过的封面：未设时显示词条色块，不请求自动封面',
      (t) async {
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: tree,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onOpenStars: () {},
      // 明确模拟「未设置封面」
      topCoverOf: (_) => '',
    )));

    expect(find.byKey(const ValueKey('unit-top-1')), findsOneWidget);
    // 占位色块（tint）出现，且没有任何网络图请求（自动封面被禁用）
    expect(find.byKey(const ValueKey('unit-cover-tint')), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('设了封面的顶级单元库卡片才加载封面图', (t) async {
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: tree,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onOpenStars: () {},
      topCoverOf: (_) => 'http://nas/media/T1/_cover/v1.jpg',
    )));

    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.byKey(const ValueKey('unit-cover-tint')), findsNothing);
  });

  testWidgets('顶级单元库卡片带词条色块：有层级图案、无重复文字', (t) async {
    LibraryBadge.topCustom['top-1'] = 0xFF1D4ED8;
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: tree,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onOpenStars: () {},
      topCoverOf: (_) => '',
    )));

    // 词条色块出现，尺寸固定（形状尺寸四级一致）。
    final swatch = find.byKey(const ValueKey('unit-top-entry-top-1'));
    expect(swatch, findsOneWidget);
    final box = t.getSize(swatch);
    expect(box.width, kTopEntrySwatchSize);
    expect(box.height, kTopEntrySwatchSize);

    // 色块里没有文字：名字只出现一次（标题），词条不重复名字。
    expect(find.text('T1'), findsOneWidget);
    expect(
        find.descendant(of: swatch, matching: find.byType(Text)), findsNothing);
  });

  testWidgets('词条色块随顶级单元库自定义色变化', (t) async {
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: tree,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onOpenStars: () {},
      topCoverOf: (_) => '',
    )));
    Color swatchColor() {
      final c = t.widget<Container>(
          find.byKey(const ValueKey('unit-top-entry-top-1')));
      return (c.decoration! as BoxDecoration).color!;
    }

    final before = swatchColor();
    LibraryBadge.topCustom['top-1'] = 0xFF00FF00;
    LibraryBadge.revision.value++;
    await t.pumpAndSettle();
    expect(swatchColor(), isNot(before));
    // 底纹浓度由 LibEntryKind.top 决定，不是满不透明。
    expect(swatchColor().a, lessThan(1.0));
  });

  testWidgets('非首页卡片（下级单元库）不带顶级词条色块', (t) async {
    await t.pumpWidget(host(UnitLibraryCard(
      unit: tree.children.first,
      headers: const {},
    )));
    final id = tree.children.first.id;
    expect(find.byKey(ValueKey('unit-top-entry-$id')), findsNothing);
  });

  testWidgets('顶级单元库卡片显示连接状态', (t) async {
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: tree,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onOpenStars: () {},
      topCoverOf: (_) => '',
      statusOf: (_) => '已断连',
    )));

    expect(find.text('已断连'), findsOneWidget);
  });
}
