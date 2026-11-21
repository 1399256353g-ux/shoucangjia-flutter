import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';
import 'package:shoucangjia/work_plays.dart';

BasicLib basic(String id, String rel,
        {int authors = 1, int works = 10, String serverBase = ''}) =>
    BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: authors,
      works: works,
      serverBase: serverBase,
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
    expect(find.text('2 个单元库'), findsOneWidget);
    // 旧「大库描述」（N 个基础库）不再出现在单元库卡片/标题上。
    expect(find.textContaining('个基础库'), findsNothing);
    // 主页把顶级下的单元库卡片铺成网格（与基础库卡片同形状）
    expect(find.byKey(const ValueKey('unit-big-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('unit-big-02')), findsOneWidget);
    // 基础库卡片也不在主页出现（层级递减：点进单元库才有）
    expect(find.byKey(const ValueKey('basic-card-l1')), findsNothing);

    await t.tap(find.byKey(const ValueKey('unit-big-01')));
    expect(opened, 'big-01');
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
    await t.tap(find.byKey(const ValueKey('unit-star-big-01')));
    expect(toggled, 'big-01');
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

  testWidgets('基础库卡片封面铺满整卡（非缩略图）', (t) async {
    await t.pumpWidget(host(UnitLibraryPage(
      unit: tree.children.first,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
    )));

    final card = find.byKey(const ValueKey('basic-card-l1'));
    final cover = find.byKey(const ValueKey('basic-cover-l1'));
    expect(card, findsOneWidget);
    expect(cover, findsOneWidget);
    final cardSize = t.getSize(card);
    final coverSize = t.getSize(cover);
    // 封面与整卡同尺寸：铺满，不再是小缩略图。
    expect(coverSize.width, cardSize.width);
    expect(coverSize.height, cardSize.height);
    expect(coverSize.width, greaterThan(100));
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

  group('单元库封面解析', () {
    tearDown(() => WorkPlaysStore.resetForTest(items: const {}));

    final playTree = buildUnitTree(
      nodes: const [
        LibNode(id: 'big-01', rel: '(1) A', name: '(1) A'),
        LibNode(id: 'big-01-sub', rel: '(1) A/sub', name: 'sub'),
      ],
      basics: [
        basic('l1', '(1) A/x', serverBase: 'http://nas:8090'),
        basic('l2', '(1) A/sub/y', serverBase: 'http://nas:8090'),
      ],
    )!;

    test('自定义封面优先于播放量', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 9, thumb: '/media/l1/x/th.jpg'),
      });
      expect(
          unitCoverUrl(playTree,
              customUrl: 'http://nas:8090/media/l1/x/_cover/v1.jpg'),
          'http://nas:8090/media/l1/x/_cover/v1.jpg');
    });

    test('无自定义时取整棵子树内播放量最高的作品封面', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 2, thumb: '/media/l1/x/a.jpg'),
        'l2/w2': const WorkPlay(count: 7, thumb: '/media/l2/y/b.jpg'),
      });
      final top = topPlayedInUnit(playTree);
      expect(top?.basic.id, 'l2');
      expect(top?.thumb, '/media/l2/y/b.jpg');
      expect(unitCoverUrl(playTree), 'http://nas:8090/media/l2/y/b.jpg');
    });

    test('相对缩略图按基础库前缀补齐', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 4, thumb: 'x/th.jpg'),
      });
      expect(unitCoverUrl(playTree),
          'http://nas:8090/media/l1/x/th.jpg');
    });

    test('播放记录只有空缩略图时回退默认图', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 6, thumb: ''),
      });
      expect(topPlayedInUnit(playTree), isNull);
      expect(unitCoverUrl(playTree), '');
    });

    test('thumbUrlOf 可替换 URL 拼装（交给 cfg 处理鉴权/路由）', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 4, thumb: '/media/l1/x/th.jpg'),
      });
      expect(
          unitCoverUrl(playTree,
              thumbUrlOf: (b, th) => 'custom:$th@${b.id}'),
          'custom:/media/l1/x/th.jpg@l1');
    });

    test('单元库卡片鉴权头取子树第一个基础库的连接', () {
      expect(unitHeadersOf(playTree, null), isEmpty);
      expect(
          unitHeadersOf(playTree, ([lib]) => {'Authorization': 'Basic $lib'}),
          {'Authorization': 'Basic l1'});
    });
  });
  testWidgets('库卡片封面必须带鉴权头（服务端要求 Basic，否则 401 永远空白）', (t) async {
    final headers = {'Authorization': 'Basic test'};
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: tree,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onOpenStars: () {},
      unitCoverOf: (u) => 'http://10.0.0.2:8090/media/l1/a.jpg',
      headersOf: ([lib]) => headers,
    )));
    final imgs =
        t.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(imgs, isNotEmpty);
    for (final w in imgs) {
      expect(w.httpHeaders, headers);
    }
  });

}
