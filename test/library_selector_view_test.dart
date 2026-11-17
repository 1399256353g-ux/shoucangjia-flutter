import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/library_selector_view.dart';
import 'package:shoucangjia/library_tree.dart';

LibraryTree _tree({List<String> stars = const []}) => LibraryTree.parse({
      'bigLibraries': [
        {'id': 'big-01', 'name': '大库一', 'path': '/x/一', 'authors': 3, 'works': 9},
        {'id': 'big-02', 'name': '大库二', 'path': '/x/二', 'authors': 2, 'works': 5},
      ],
      'basicLibraries': [
        {
          'id': 'lib-001',
          'name': '基础一',
          'rel': '一/基础一',
          'big_id': 'big-01',
          'authors': 2,
          'works': 6
        },
        {
          'id': 'lib-002',
          'name': '基础二',
          'rel': '一/基础二',
          'big_id': 'big-01',
          'authors': 1,
          'works': 3
        },
        {
          'id': 'lib-003',
          'name': '基础三',
          'rel': '二/基础三',
          'big_id': 'big-02',
          'authors': 2,
          'works': 5
        },
      ],
    }, stars: stars)!;

Widget _host({
  required LibraryTree tree,
  Set<String> expanded = const {},
  Set<String> stars = const {},
  bool legacyOpen = false,
  List<String> legacyNames = const ['旧库甲', '旧库乙'],
  void Function(String)? onToggleSection,
  void Function(BasicLib)? onToggleStar,
  VoidCallback? onToggleLegacy,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView(children: [
        LibrarySelectorView(
          tree: tree,
          expanded: expanded,
          stars: stars,
          legacyCount: legacyNames.length,
          legacyOpen: legacyOpen,
          onToggleSection: onToggleSection ?? (_) {},
          onToggleStar: onToggleStar ?? (_) {},
          onTapBasic: (_) {},
          onToggleLegacy: onToggleLegacy ?? () {},
          legacyBuilder: (_) => Column(
            children: [
              for (final n in legacyNames) ListTile(title: Text(n)),
            ],
          ),
        ),
      ]),
    ),
  );
}

void main() {
  testWidgets('首屏只显示大库，基础库与旧注册表默认收起', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(tree: _tree()));

    expect(find.text('大库一'), findsOneWidget);
    expect(find.text('大库二'), findsOneWidget);
    expect(find.text('基础一'), findsNothing);
    expect(find.text('基础二'), findsNothing);
    expect(find.text('基础三'), findsNothing);
    expect(find.text('旧库甲'), findsNothing);
    expect(find.text('旧库乙'), findsNothing);
    expect(find.byKey(const ValueKey('legacy-toggle')), findsOneWidget);

    // J3：首屏条目数 = 标题 + 2 个大库 + 管理入口，不随基础库数量增长。
    expect(find.byType(ListTile), findsNWidgets(3));
  });

  testWidgets('点开大库才显示其基础库', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var expanded = <String>{};
    await tester.pumpWidget(_host(
      tree: _tree(),
      onToggleSection: (id) => expanded = toggleExpanded(expanded, id),
    ));
    await tester.tap(find.byKey(const ValueKey('big-big-01')));
    await tester.pump();

    // 回调生效后重建，基础库出现；另一个大库仍收起。
    await tester.pumpWidget(_host(
      tree: _tree(),
      expanded: expanded,
      onToggleSection: (id) => expanded = toggleExpanded(expanded, id),
    ));
    expect(find.text('基础一'), findsOneWidget);
    expect(find.text('基础二'), findsOneWidget);
    expect(find.text('基础三'), findsNothing);
  });

  testWidgets('旧注册表展开后才出现，且保留全部入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var open = false;
    await tester.pumpWidget(_host(
      tree: _tree(),
      onToggleLegacy: () => open = !open,
    ));
    expect(find.text('旧库甲'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('legacy-toggle')));
    await tester.pump();
    await tester.pumpWidget(_host(
      tree: _tree(),
      legacyOpen: open,
      onToggleLegacy: () => open = !open,
    ));
    expect(find.text('旧库甲'), findsOneWidget);
    expect(find.text('旧库乙'), findsOneWidget);
  });

  testWidgets('星标基础库置顶且不在大库里重复', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tree = _tree(stars: ['lib-002']);
    expect(tree.starred.single.name, '基础二');

    await tester.pumpWidget(_host(tree: tree, stars: {'lib-002'}));
    expect(find.text('基础二'), findsOneWidget);
    expect(find.byKey(const ValueKey('basic-lib-002')), findsOneWidget);
    // 大库一未展开，不重复渲染。
    expect(find.byKey(const ValueKey('basic-lib-001')), findsNothing);
  });
}
