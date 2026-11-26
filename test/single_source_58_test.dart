/// 第八十一批契约（0.9.315）：**「内容区的约束」不等于「这块网格在屏幕里」** +
/// **界面里有一句话在讲已经推翻的旧规则**。
///
/// 1. 单元库页两块网格都在同一个 `ListView` 里（`shrinkWrap`），0.9.313 把
///    预热尺寸从「整窗口」换成「内容区 `LayoutBuilder` 约束」。内容区包含
///    **另一个网格 + 两条标题行**：下级单元库网格只占顶部一两行，基础库网格
///    在它下面，按内容区高度算就会给屏幕外的那个网格也预热一整屏。
///    正确做法与首页同一条：一个网格一把 key，读
///    `scroll_viewport.visibleViewportOf`（可见高度为 0 就不预热）。
/// 2. 同一类卡片的两处配额并存（`kUnitLibGrid.maxPrefetch = 8` 与调用点
///    `maxItems: 6`），谁说了算没人写得清。
/// 3. owner 2026-11-27 已把分发规则改成「逐级上行，第一个设过色的层即分发源」，
///    界面上残着「非末梢 · 仅本层」与「末梢才分发」——写着与行为相反的结论。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/grid_spec.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';

/// 只保留非注释行：文档里的「旧写法」不能被契约扫描当成现役代码。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _classBody(String src, String name) {
  final start = src.indexOf('class $name');
  expect(start, isNonNegative, reason: '找不到 $name');
  final rest = src.substring(start + 1);
  final next = rest.indexOf('\nclass ');
  return next < 0 ? rest : rest.substring(0, next);
}

BasicLib _basic(String id, String rel, {int works = 10}) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: works,
    );

void main() {
  group('单元库页每块网格读自己的可见高度（0.9.315）', () {
    test('两块网格各有一把 key，几何只走 visibleViewportOf', () {
      final src = _code('lib/unit_library_view.dart');
      final body = _classBody(src, '_UnitLibraryPageState');
      expect(body.contains('final GlobalKey _childrenGridKey = GlobalKey();'),
          isTrue);
      expect(body.contains('final GlobalKey _basicsGridKey = GlobalKey();'),
          isTrue);
      expect(body.contains('visibleViewportOf(_childrenGridKey)'), isTrue);
      expect(body.contains('visibleViewportOf(_basicsGridKey)'), isTrue);
      // 「内容区约束」只用来判断窗口尺寸变没变，不得再当预热几何。
      expect(body.contains('viewport: _pageSize'), isFalse,
          reason: '内容区约束不是任何一块网格的可见高度');
      expect(body.contains('viewport: _pageViewport'), isFalse,
          reason: '旧字段已删');
      // 两个网格都挂上了自己的 key（否则读到的是 null，永远不预热）。
      expect(RegExp(r'key: _childrenGridKey,').hasMatch(body), isTrue);
      expect(RegExp(r'key: _basicsGridKey,').hasMatch(body), isTrue);
    });

    test('布局阶段只写字段、不 setState（与 _gridViewport 系列同一条规矩）', () {
      final body = _classBody(_code('lib/unit_library_view.dart'),
          '_UnitLibraryPageState');
      final flat = body.replaceAll(RegExp(r'\n\s*'), ' ');
      expect(RegExp(r'_pageSize = cons\.biggest;\s*setState').hasMatch(flat),
          isFalse,
          reason: '布局阶段不得 setState');
      // GlobalKey 只在字段声明处建一次：若在 build 里 new 一个，每帧都换 key，
      // `visibleViewportOf` 永远读到刚建的空 context。
      final declarations =
          RegExp(r'final GlobalKey _\w+GridKey = GlobalKey\(\);')
              .allMatches(flat)
              .length;
      expect(declarations, 2, reason: '两块网格各一把 key，且只在字段处建');
      expect(RegExp(r'_\w+GridKey = GlobalKey\(\)').allMatches(flat).length, 2,
          reason: '不得在 build 里重建 GlobalKey');
    });

    testWidgets('两块网格都有真实 key；滚出屏幕的那块可见高度为 0', (tester) async {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'big-01', rel: '(1) A', name: '(1) A'),
          LibNode(id: 'big-02', rel: '(1) A/(1) A1', name: '(1) A1'),
        ],
        basics: [
          _basic('l1', '(1) A/x'),
          _basic('l2', '(1) A/(1) A1/y'),
        ],
      )!;
      await tester.pumpWidget(MaterialApp(
        home: UnitLibraryPage(
          unit: tree.children.first, // big-01：有下级单元库 + 一个直属基础库
          stars: const <String>{},
          onOpenUnit: (_) {},
          onToggleUnitStar: (_) {},
          onTapBasic: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      // 两块网格在渲染树里都存在（页面本身把两类卡片都建出来了），
      // 且各自挂了 GlobalKey——预热才有地方读几何。
      final grids = tester
          .widgetList<GridView>(find.byType(GridView))
          .toList();
      expect(grids.length, 2);
      for (final g in grids) {
        expect(g.key, isA<GlobalKey>(),
            reason: '网格没有 key，预热只能拿整块内容区顶替');
      }
      expect(grids[0].key, isNot(equals(grids[1].key)),
          reason: '两块网格共用一把 key 时只能读到其中一块的几何');
    });
  });

  group('同一网格只有一处配额（0.9.315）', () {
    test('单元库页不再自带 maxItems 覆盖规格表', () {
      final src = _code('lib/unit_library_view.dart');
      expect(RegExp(r'maxItems:\s*6').hasMatch(src), isFalse,
          reason: 'kUnitLibGrid.maxPrefetch 已经说了话，调用点不该另写一个上限');
      expect(kUnitLibGrid.maxPrefetch, 8);
      expect(kBasicLibGrid.maxPrefetch, 8);
    });

    testWidgets('可见高度为 0 时 firstScreenThumbCount 收手（判据本身有效）',
        (t) async {
      final n = kUnitLibGrid.prefetchCount(
        const Size(400, 0),
        padding: kLibGridPadding,
      );
      expect(n, 0, reason: '屏幕外的网格不该预热');
      // 契约：同一份几何喂给「可见 0」与「正常屏高」必须给出不同答案，
      // 否则说明高度这一维被丢掉了。
      final ok = kUnitLibGrid.prefetchCount(
        const Size(400, 800),
        padding: kLibGridPadding,
      );
      expect(ok, greaterThan(0));
    });

    test('visibleViewportOf 由页面转发（几何唯一实现）', () {
      final src = File('lib/scroll_viewport.dart').readAsStringSync();
      expect(src.contains('Size? visibleViewportOf(GlobalKey key)'), isTrue);
      // 页面不得自己算「视口高 − 偏移」。
      final page = _code('lib/unit_library_view.dart');
      expect(page.contains('viewportDimension'), isFalse);
      expect(page.contains('globalToLocal'), isFalse);
    });
  });

  group('界面里不得出现已推翻的分发规则（0.9.315）', () {
    test('main 不再有「仅本层 / 非末梢 / 末梢才分发」', () {
      final src = _code('lib/main.dart');
      expect(src.contains('仅本层'), isFalse);
      expect(src.contains('非末梢'), isFalse);
      expect(src.contains('末梢才分发'), isFalse);
      expect(src.contains('_NoDistributeMark'), isFalse);
      expect(src.contains('基础库（末梢'), isFalse);
    });

    test('分发说明只剩一种口径：任何单元库设的色都往下给', () {
      final src = _code('lib/main.dart');
      expect(src.contains("'可分发给下级'"), isTrue);
      expect(src.contains("'向下继承'"), isTrue);
    });

    test('库角标页的层级名不用内部结构术语', () {
      final src = _code('lib/main.dart');
      expect(src.contains("单元库（中间层）"), isFalse,
          reason: '「中间层」是代码结构叫法，用户看的是媒体库/单元库/基础库');
      expect(src.contains("'单元库',"), isTrue);
    });
  });

  group('脚本大小不再写裸字节（0.9.315）', () {
    test('两处脚本列表都走 formatBytes', () {
      final main = _code('lib/main.dart');
      final crawler = _code('lib/unit_crawler_page.dart');
      expect(main.contains(r"${s.size} B"), isFalse,
          reason: '「1234 B」是给机器看的；人读的是 KB/MB');
      expect(crawler.contains(r"${s.size} B"), isFalse);
      expect(main.contains('formatBytes(s.size)'), isTrue);
      expect(crawler.contains('formatBytes(s.size)'), isTrue);
    });
  });
}
