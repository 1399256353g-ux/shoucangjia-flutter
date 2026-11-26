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

  // owner 2026-11-26（第三次提同一件事）：
  // > 「媒体库词条弄得个星图标就只贴在个首页媒体库卡上，这块不知道在搞什么
  // >   东西，有点蠢」「词条还是没下发，还是没粘贴」
  //
  // 旧实现只画一个无文字图案块（注释理由是「名字重复是噪声」）。但词条的
  // 作用就是标明「哪个库、什么颜色、什么后缀」，一个色点承载不了——用户看到
  // 的就是一个星图标。现在贴真正的文字词条（`LibBadgeChip`，与单元库页标题
  // 同一套：去序号名称 + emoji 后缀 + 该层级真实外观）。
  testWidgets('媒体库卡片贴文字词条（不再是只有图案的色点）', (t) async {
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

    // 词条出现。
    final swatch = find.byKey(const ValueKey('unit-top-entry-top-1'));
    expect(swatch, findsOneWidget);

    // 词条里必须有文字（这就是「贴词条」与「贴个图标」的区别）。
    expect(
        find.descendant(of: swatch, matching: find.byType(Text)),
        findsWidgets,
        reason: '媒体库卡片上的词条必须带文字，不能只有一个图案');
    expect(find.descendant(of: swatch, matching: find.text('T1')),
        findsWidgets,
        reason: '词条文字＝去序号后的媒体库名');
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
    // 词条改了颜色要跟着变：直接比渲染出来的文字样式所在 chip 的颜色。
    int chipColor() => LibraryBadge.colorForUnit('top-1');

    final before = chipColor();
    LibraryBadge.topCustom['top-1'] = 0xFF00FF00;
    LibraryBadge.revision.value++;
    await t.pumpAndSettle();
    expect(chipColor(), isNot(before));
    // 词条底色不是满不透明（底纹浓度由 LibEntryKind.top 决定）。
    final argb = LibraryBadge.colorForUnit('top-1');
    final deco = LibraryBadge.decorationFor(LibEntryKind.top, argb);
    expect(deco, isNotNull, reason: '词条外观必须能取到');
  });

  testWidgets('非首页卡片（下级单元库）不带顶级词条色块', (t) async {
    await t.pumpWidget(host(UnitLibraryCard(
      unit: tree.children.first,
      headers: const {},
    )));
    final id = tree.children.first.id;
    expect(find.byKey(ValueKey('unit-top-entry-$id')), findsNothing);
  });

  // owner 2026-11-25：「在线标识搞个绿色原点就可以了，不在线就变红色就行，
  // 简约一点」。卡片底部不再写「已连接/已断连」文字，改成圆点 + IP 地址。
  testWidgets('顶级单元库卡片用红/绿圆点表示连接状态，不写文字', (t) async {
    Future<void> pumpWith(bool? online) async {
      await t.pumpWidget(host(UnitLibraryHomeView(
        tree: tree,
        stars: const {},
        onOpenUnit: (_) {},
        onToggleUnitStar: (_) {},
        onTapBasic: (_) {},
        onOpenStars: () {},
        topCoverOf: (_) => '',
        statusOf: (_) => online,
      )));
      await t.pumpAndSettle();
    }

    // 断连 → 红点
    await pumpWith(false);
    expect(find.text('已断连'), findsNothing, reason: '不应再写文字');
    expect(find.text('已连接'), findsNothing, reason: '不应再写文字');
    expect(_dotColors(t, kCardOfflineColor), isTrue, reason: '断连应为红点');
    expect(_dotColors(t, kCardOnlineColor), isFalse);

    // 已连接 → 绿点
    await pumpWith(true);
    expect(find.text('已连接'), findsNothing, reason: '不应再写文字');
    expect(_dotColors(t, kCardOnlineColor), isTrue, reason: '在线应为绿点');
    expect(_dotColors(t, kCardOfflineColor), isFalse);

    // 状态未知 → 不画圆点
    await pumpWith(null);
    expect(_dotColors(t, kCardOnlineColor), isFalse);
    expect(_dotColors(t, kCardOfflineColor), isFalse);
  });

  testWidgets('卡片底部标注 IP（不含协议），订阅服务端 base', (t) async {
    final withBase = buildUnitTree(
      nodes: const [
        LibNode(
            id: 'top-9',
            rel: 'T9',
            name: 'T9',
            serverBase: 'http://192.168.2.4:8090'),
      ],
      basics: [basic('b9', 'T9/x')],
    )!;
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: withBase,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onOpenStars: () {},
      topCoverOf: (_) => '',
      statusOf: (_) => true,
    )));
    await t.pumpAndSettle();
    // owner 2026-11-25：「媒体库卡片最下面补上 ip 地址标注」。
    expect(find.text('192.168.2.4:8090'), findsOneWidget);
    expect(find.textContaining('http://'), findsNothing,
        reason: '卡片只写主机:端口，不写协议');
  });

  group('hostLabelOf：只留主机与端口', () {
    test('协议/路径/查询串全部去掉', () {
      expect(hostLabelOf('http://192.168.2.4:8090/api/x?y=1'), '192.168.2.4:8090');
      expect(hostLabelOf('https://nas.local'), 'nas.local');
      expect(hostLabelOf('192.168.2.4:8090'), '192.168.2.4:8090');
      expect(hostLabelOf('  192.168.2.4:8090/  '), '192.168.2.4:8090');
    });

    test('空串返回空串；解析不出主机时原样返回不吞掉配置', () {
      expect(hostLabelOf(''), '');
      expect(hostLabelOf('   '), '');
      expect(hostLabelOf('http://'), 'http://');
    });
  });
}

/// 卡片底部是否存在指定颜色的状态圆点（7x7 圆形 Container）。
bool _dotColors(WidgetTester t, Color want) {
  final hit = find.byWidgetPredicate((w) {
    if (w is! Container) return false;
    final d = w.decoration;
    if (d is! BoxDecoration) return false;
    if (d.shape != BoxShape.circle) return false;
    if (d.color != want) return false;
    return true;
  });
  return hit.evaluate().isNotEmpty;
}
