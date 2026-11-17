import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';

BasicLib basic(String id, String rel) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 2,
    );

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final tree = buildUnitTree(
    nodes: const [LibNode(id: 'big-01', rel: '(1) A', name: '(1) A')],
    basics: [basic('l1', '(1) A/x')],
  )!;
  final unit = tree.children.first;
  final oneBasic = unit.allBasics.first;

  testWidgets('单元库卡片：有上传入口时显示封面按钮并可点击', (t) async {
    var taps = 0;
    await t.pumpWidget(host(UnitLibraryCard(
      unit: unit,
      onTap: () {},
      onSetCover: () => taps++,
    )));
    final btn = find.byKey(ValueKey('unit-cover-btn-${unit.id}'));
    expect(btn, findsOneWidget);
    await t.tap(btn);
    expect(taps, 1);
  });

  testWidgets('单元库卡片：无上传入口时不显示封面按钮', (t) async {
    await t.pumpWidget(host(UnitLibraryCard(unit: unit, onTap: () {})));
    expect(find.byKey(ValueKey('unit-cover-btn-${unit.id}')), findsNothing);
  });

  testWidgets('基础库卡片：有上传入口时显示封面按钮并可点击', (t) async {
    var taps = 0;
    await t.pumpWidget(host(BasicLibCard(
      basic: oneBasic,
      onTap: () {},
      onSetCover: () => taps++,
    )));
    final btn = find.byKey(ValueKey('basic-cover-btn-${oneBasic.id}'));
    expect(btn, findsOneWidget);
    await t.tap(btn);
    expect(taps, 1);
  });

  testWidgets('基础库卡片：无上传入口时不显示封面按钮', (t) async {
    await t.pumpWidget(host(BasicLibCard(basic: oneBasic, onTap: () {})));
    expect(find.byKey(ValueKey('basic-cover-btn-${oneBasic.id}')), findsNothing);
  });
}
