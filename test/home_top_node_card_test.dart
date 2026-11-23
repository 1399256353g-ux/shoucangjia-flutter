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
