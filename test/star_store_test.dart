import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/star_store.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';

BasicLib basic(String id, String rel) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 10,
      serverBase: '',
    );

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final tree = buildUnitTree(
    nodes: const [
      LibNode(id: 'big-01', rel: '(1) A', name: '(1) A'),
      LibNode(id: 'big-01-sub', rel: '(1) A/sub', name: 'sub'),
    ],
    basics: [basic('l1', '(1) A/sub/x')],
  )!;

  tearDown(StarStore.instance.debugReset);

  test('toggle 最新标记在前并可取消', () async {
    StarStore.instance.debugSeed(const []);
    await StarStore.instance.toggle('big-01');
    await StarStore.instance.toggle('big-02');
    expect(StarStore.instance.ordered, ['big-02', 'big-01']);
    await StarStore.instance.toggle('big-01');
    expect(StarStore.instance.ordered, ['big-02']);
    expect(StarStore.instance.contains('big-01'), isFalse);
  });

  testWidgets('单元库页星标跟随 StarStore 变化（返回父页不再显示旧值）', (t) async {
    StarStore.instance.debugSeed(const ['big-01-sub']);
    await t.pumpWidget(host(UnitLibraryPage(
      unit: tree.children.first,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
    )));
    final key = find.byKey(const ValueKey('unit-star-big-01-sub'));
    expect(key, findsOneWidget);
    expect(
      find.descendant(of: key, matching: find.byIcon(Icons.star)),
      findsOneWidget,
    );

    // 其它页面（如星标页）取消了该星标：本页应立即变回空心。
    StarStore.instance.debugSeed(const []);
    await t.pumpWidget(host(UnitLibraryPage(
      unit: tree.children.first,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
    )));
    await t.pump();
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('unit-star-big-01-sub')),
          matching: find.byIcon(Icons.star_border)),
      findsOneWidget,
    );
  });

  testWidgets('主页星标计数与 StarStore 一致', (t) async {
    StarStore.instance.debugSeed(const ['big-01', 'big-02']);
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: tree,
      stars: const {},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onOpenStars: () {},
    )));
    expect(find.text('2 个'), findsOneWidget);
  });

  testWidgets('未初始化时仍使用构造参数里的星标快照（测试/降级路径）', (t) async {
    StarStore.instance.debugReset();
    await t.pumpWidget(host(UnitLibraryHomeView(
      tree: tree,
      stars: const {'big-01'},
      onOpenUnit: (_) {},
      onToggleUnitStar: (_) {},
      onTapBasic: (_) {},
      onOpenStars: () {},
    )));
    expect(find.text('1 个'), findsOneWidget);
  });
}
