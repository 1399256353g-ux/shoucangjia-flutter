import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_filter.dart';
import 'package:shoucangjia/author_filter_ui.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/main.dart';
import 'package:shoucangjia/unit_library.dart';

// P3：筛选、功能页引入「顶级节点」分类（＝每个连接的媒体库根）。
// 判定全部读结构（树/映射），不看任何目录名文本。

UnitLibrary _tree() {
  BasicLib b(String id, String rel) => BasicLib(
      id: id, name: id, rel: rel, bigId: '', authors: 0, works: 0);
  LibNode n(String rel) => LibNode(id: rel, rel: rel, name: rel);

  final leaf = UnitLibrary(
    node: n('T1/MID/LEAF'),
    basics: [b('b-leaf', 'T1/MID/LEAF/x')],
    children: const [],
  );
  final mid = UnitLibrary(
    node: n('T1/MID'),
    basics: [b('b-mid', 'T1/MID/y')],
    children: [leaf],
  );
  final top1 = UnitLibrary(node: n('T1'), basics: const [], children: [mid]);
  final top2 = UnitLibrary(
    node: n('T2'),
    basics: [b('b-two', 'T2/z')],
    children: const [],
  );
  return UnitLibrary(
    node: const LibNode(id: 'secret', rel: '', name: 'SECRET'),
    basics: const [],
    children: [top1, top2],
  );
}

void main() {
  setUp(() {
    LibraryBadge.topOfUnit.clear();
    LibraryBadge.leafUnits.clear();
    UnitBadgeRegistry.topOf.clear();
    UnitBadgeRegistry.leaf.clear();
    UnitBadgeRegistry.order.clear();
  });

  test('LibMeta.tops 只取根的直接子节点；空子库被排除', () {
    final tree = _tree();
    final meta = LibMeta(
      basics: const [],
      stats: const {},
      unitTree: tree,
      units: flattenUnits(tree),
      basicToUnit: unitOfBasics(tree),
    );
    expect(meta.tops.map((u) => u.id).toList(), ['T1', 'T2']);
  });

  test('基础库 → 单元库 → 顶级节点链路不给错答案', () {
    final tree = _tree();
    final meta = LibMeta(
      basics: const [],
      stats: const {},
      unitTree: tree,
      units: flattenUnits(tree),
      basicToUnit: unitOfBasics(tree),
    );
    UnitBadgeRegistry.setFrom(tree);
    expect(meta.topIdForBasic('b-leaf'), 'T1');
    expect(meta.topIdForBasic('b-mid'), 'T1');
    expect(meta.topIdForBasic('b-two'), 'T2');
    expect(meta.topIdForBasic('不存在的基础库'), '');
    expect(meta.topIdFor('T1/MID/LEAF'), 'T1');
    expect(meta.topIdFor(''), '');
    expect(meta.topIdFor('T9/unknown'), '');
  });

  testWidgets('筛选面板把媒体库（库根）排在最前，选中后收敛', (t) async {
    AuthorFilterState? out;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                out = await showAuthorFilterSheet(
                  context: c,
                  initial: AuthorFilterState(),
                  basics: const [],
                  bigs: const [],
                  units: const [
                    AuthorLibNode(id: 'T1/MID', name: 'MID'),
                  ],
                  tops: const [
                    AuthorLibNode(id: 'T1', name: 'T1'),
                    AuthorLibNode(id: 'T2', name: 'T2'),
                  ],
                  grades: const ['S', 'A'],
                  count: (_) => 0,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.text('媒体库'), findsOneWidget);
    // 顶级节点分区排在单元库分区之前
    final topY = t.getTopLeft(find.text('媒体库')).dy;
    final unitY = t.getTopLeft(find.text('单元库')).dy;
    expect(topY, lessThan(unitY));

    await t.tap(find.widgetWithText(FilterChip, 'T1'));
    await t.pumpAndSettle();
    await t.tap(find.text('应用'));
    await t.pumpAndSettle();
    expect(out, isNotNull);
    expect(out!.tops, {'T1'});
    expect(out!.isActive, isTrue);
  });
}
