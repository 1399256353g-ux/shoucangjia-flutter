// 第九十八批（0.9.343）契约：
//   1. `+N` 折叠项不是词条：不得借用任何一级的层级外观与颜色。
//   2. 「多挂几处就贴几个」：同名作者跨两台服务器时，两个媒体库词条都要贴；
//      同一个媒体库不得重复贴。
//
// 隐私：全部用合成 id/名字（`b1` / `T1` / `T2`），不读任何真实目录名，
// 不涉及截图或媒体内容。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/main.dart' show LibBadges, LibMeta, UnitBadges;
import 'package:shoucangjia/top_node.dart';
import 'package:shoucangjia/unit_library.dart';

BasicLib b(String id, String rel, {String sid = 's1'}) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 3,
      serverId: sid,
      serverLabel: sid == 's2' ? 'B' : 'A',
    );

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 两台服务器各一个媒体库根：T1/s1 与 T2/s2。
UnitLibrary twoServers() => buildUnitTree(
      nodes: const [
        LibNode(id: 'T1', rel: 'T1', name: 'T1', serverId: 's1', serverLabel: 'A'),
        LibNode(id: 'T2', rel: 'T2', name: 'T2', serverId: 's2', serverLabel: 'B'),
      ],
      basics: [
        b('b1', 'T1/x'),
        b('b2', 'T2/y', sid: 's2'),
      ],
      topName: 'ROOT',
    )!;

LibMeta metaOf(UnitLibrary tree) => LibMeta(
      basics: tree.allBasics,
      allBasics: tree.allBasics,
      stats: const {},
      unitTree: tree,
      units: flattenUnits(tree),
      basicToUnit: unitOfBasics(tree),
      topName: 'ROOT',
    );

/// 词条文字（排除 `+N` 与纯数字的展开键）。
List<String> chipTexts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data)
    .whereType<String>()
    .where((s) => !RegExp(r'^[+\d]').hasMatch(s))
    .toList();

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LibraryBadge.load();
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.topOfUnit.clear();
    LibraryBadge.parentOfUnit.clear();
    UnitBadgeRegistry.order.clear();
    UnitBadgeRegistry.labels.clear();
    UnitBadgeRegistry.keys.clear();
    TopNodeName.reset();
  });

  group('1. `+N` 折叠项不是一个词条', () {
    testWidgets('+N 用默认层级与灰色，不借用第 4 个库的外观', (t) async {
      await t.pumpWidget(host(const LibBadges(libIds: <String>[
        'media:s1',
        'T1/a',
        'T1/b',
        'T1/c',
        'T1/d',
      ])));
      final folds = t
          .widgetList<LibBadgeChip>(find.byType(LibBadgeChip))
          .where((w) => w.label.startsWith('+'))
          .toList();
      expect(folds, isNotEmpty, reason: '5 个库只显示 3 个，应有 +2');
      for (final w in folds) {
        expect(w.kind, LibEntryKind.unit,
            reason: '+N 不代表任何一级库，不得借用户可辨识的层级外观');
        expect(w.unitId, isEmpty, reason: '+N 不属于任何库');
        expect(w.color, LibraryBadge.gray);
      }
    });
  });

  group('2. 多挂几处就贴几个媒体库词条', () {
    testWidgets('跨两台服务器时两个媒体库词条都在', (t) async {
      final tree = twoServers();
      UnitBadgeRegistry.setFrom(tree);
      await t.pumpWidget(host(UnitBadges(
        meta: metaOf(tree),
        mediaPath: '',
        basicIds: const <String>['b1', 'b2'],
      )));
      final texts = chipTexts(t);
      // 只对第一个单元库求媒体库时，另一台的媒体库词条永远不出现——这是本
      // 条契约要挡的回归。**两个媒体库名都要在**（合成名 A / B）。
      expect(texts.where((s) => s == 'A' || s == 'B').length, 2,
          reason: '两台服务器的媒体库词条缺一条，说明只取了 ids.first');
      expect(texts.where((s) => s.contains('media:')), isEmpty,
          reason: '媒体库词条不得把内部键 media:s1 写到界面上');
    });

    testWidgets('折叠只吃掉末位的单元库，不挤掉媒体库词条', (t) async {
      final tree = twoServers();
      UnitBadgeRegistry.setFrom(tree);
      await t.pumpWidget(host(UnitBadges(
        meta: metaOf(tree),
        mediaPath: '',
        basicIds: const <String>['b1', 'b2'],
      )));
      final texts = chipTexts(t);
      final all = t
          .widgetList<LibBadgeChip>(find.byType(LibBadgeChip))
          .map((w) => w.label)
          .toList();
      // 2 媒体库 + 2 单元库 = 4 条候选，显示预算 3：折叠必须落在**末位**
      // （单元库 T2），`+1` 如实说明还剩一条。
      // 若折叠吃掉的是媒体库，同级里「更上级的词条被下级挤掉」就反了。
      expect(all.where((s) => s.startsWith('+')).toList(), ['+1']);
      expect(texts, contains('A'));
      expect(texts, contains('B'));
      expect(texts, contains('T1'));
      expect(texts, isNot(contains('T2')),
          reason: '折叠应当只吃掉末位单元库；媒体库两条都必须在');
    });

    testWidgets('同一个媒体库不按来源数量翻倍', (t) async {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'T1', rel: 'T1', name: 'T1', serverId: 's1', serverLabel: 'A'),
        ],
        basics: [b('b1', 'T1/x'), b('b2', 'T1/y')],
        topName: 'ROOT',
      )!;
      UnitBadgeRegistry.setFrom(tree);
      await t.pumpWidget(host(UnitBadges(
        meta: metaOf(tree),
        mediaPath: '',
        basicIds: const <String>['b1', 'b2'],
      )));
      final texts = chipTexts(t);
      // 媒体库 1 + 单元库 1 = 2：媒体库只要一条。
      expect(texts.length, 2);
      expect(texts.where((s) => s == 'T1').length, 1);
    });
  });
}
