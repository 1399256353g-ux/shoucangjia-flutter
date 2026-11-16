import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_grade.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/main.dart';
import 'package:shoucangjia/source_lib.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';

/// 0.9.8：作者来源词条＝该作者所属**基础库**的单元库（名称/配色）。
void main() {
  const rootPath = '/vol1/1000/NAS1/Secret';
  const douyinBase =
      '$rootPath/(Hidden directory)/(1) Borderline Content/(2) douyin';

  final libs = <String, dynamic>{
    'root': rootPath,
    'basicLibraries': [
      {
        'id': 'lib-015',
        'name': '(2) 丝',
        'path': '$douyinBase/(2) 丝',
        'big_id': 'big-05',
      },
      {
        'id': 'lib-029',
        'name': '(1) Hetero',
        'path': '$rootPath/(1) Heterosexuality-异性恋/(1) Hetero',
        'big_id': 'big-01',
      },
    ],
  };

  setUp(AuthorGrade.reset);
  tearDown(AuthorGrade.reset);

  group('basicIdForMedia', () {
    final refs = basicsUnderBase(libs, douyinBase);

    test('库作用域路径直接取前缀里的基础库 id', () {
      expect(
          basicIdForMedia(
              refs, '/media/lib-015/%4033/_avatar/20261111142321_9c336f.jpg'),
          'lib-015');
      // 名字里带 lib- 但不是已注册基础库时不误判
      expect(basicIdForMedia(refs, '/media/lib-999/@a/x.jpg'), '');
    });

    test('普通相对路径仍按目录前缀匹配', () {
      expect(
          basicIdForMedia(refs, '/media/(2)%20%E4%B8%9D/@33/_avatar/x.jpg'),
          'lib-015');
    });
  });

  group('基础库 → 单元库（库根坐标系）', () {
    final refs = basicsUnderBase(libs, rootPath);
    final basics = <BasicLib>[
      for (final b in refs)
        BasicLib(
            id: b.id,
            name: b.name,
            rel: b.rel,
            bigId: b.bigId,
            authors: 0,
            works: 0),
    ];
    final tree = buildUnitTree(
        nodes: nodesFromMarks(const [
          '(1) Heterosexuality-异性恋',
          '(Hidden directory)',
          '(Hidden directory)/(1) Borderline Content',
          '(Hidden directory)/(1) Borderline Content/(2) douyin',
        ]),
        basics: basics)!;
    final toUnit = unitOfBasics(tree);

    test('每个基础库都有单元库归属，且按最深节点收敛', () {
      expect(toUnit['lib-015'],
          '(Hidden directory)/(1) Borderline Content/(2) douyin');
      expect(toUnit['lib-029'], '(1) Heterosexuality-异性恋');
      expect(toUnit.length, refs.length);
      expect(unitForBasic(tree, 'lib-015')!.name, '(2) douyin');
      expect(unitForBasic(tree, 'lib-029')!.name, '(1) Heterosexuality-异性恋');
      expect(unitForBasic(tree, 'lib-404'), isNull);
    });

    testWidgets('作者卡词条取所属基础库的单元库（含作用域头像路径）',
        (tester) async {
      final meta = LibMeta(
        basics: refs,
        stats: const {},
        unitTree: tree,
        units: flattenUnits(tree),
        basicToUnit: toUnit,
      );
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AuthorBadges(
        meta: meta,
        name: '33',
        mediaPath: '/media/lib-015/%4033/_avatar/x.jpg',
        fallbackId: 'douyin',
        fallbackName: '',
      ))));
      expect(find.text('douyin'), findsOneWidget);
    });

    testWidgets('作者页/基础库页只给基础库 id 时同样显示词条', (tester) async {
      final meta = LibMeta(
        basics: refs,
        stats: const {},
        unitTree: tree,
        units: flattenUnits(tree),
        basicToUnit: toUnit,
      );
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AuthorBadges(
        meta: meta,
        name: 'Hetero 作者',
        mediaPath: '',
        fallbackId: 'lib-029',
        fallbackName: '',
      ))));
      expect(find.text('Heterosexuality-异性恋'), findsOneWidget);
    });

    testWidgets('T5：作者词条与基础库卡词条完全同源（名称/去序号）', (tester) async {
      final meta = LibMeta(
        basics: refs,
        stats: const {},
        unitTree: tree,
        units: flattenUnits(tree),
        basicToUnit: toUnit,
      );
      final labels = unitLabelByBasic(tree);
      final keys = unitKeyByBasic(tree);
      // 基础库卡：词条文本＝所属单元库名去掉前缀序号
      final cardText = BasicLibCard.badgeText(labels['lib-015']!);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        AuthorBadges(
          meta: meta,
          name: '33',
          mediaPath: '',
          basicId: 'lib-015',
          fallbackId: 'douyin',
          fallbackName: '',
          unitLabels: labels,
          unitKeys: keys,
        ),
      ]))));
      expect(keys['lib-015'], toUnit['lib-015']);
      expect(cardText, 'douyin');
      expect(find.text(cardText), findsOneWidget);
    });

    test('T5：位置词条去序号规则', () {
      expect(LibraryBadge.stripIndex('(1) 名称'), '名称');
      expect(LibraryBadge.stripIndex('（12）名称'), '名称');
      expect(LibraryBadge.stripIndex('[3] 名称'), '名称');
      expect(LibraryBadge.stripIndex('01. 名称'), '名称');
      expect(LibraryBadge.stripIndex('名称'), '名称');
      expect(LibraryBadge.stripIndex('18+'), '18+');
    });
  });
}
