import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_filter.dart';
import 'package:shoucangjia/work_forms.dart';

void main() {
  group('AuthorFilterState', () {
    test('empty filter matches everything', () {
      final f = AuthorFilterState();
      expect(f.isActive, isFalse);
      expect(
          f.matches(
              basicId: '', bigId: '', grade: '', workTypes: const {}),
          isTrue);
    });

    test('basic/big library selection is OR inside the dimension', () {
      final f = AuthorFilterState(basics: {'lib-001'}, bigs: {'big-04'});
      expect(f.matches(basicId: 'lib-001', bigId: 'big-09', grade: 'A', workTypes: const {}), isTrue);
      expect(f.matches(basicId: 'lib-002', bigId: 'big-04', grade: 'A', workTypes: const {}), isTrue);
      expect(f.matches(basicId: 'lib-002', bigId: 'big-05', grade: 'A', workTypes: const {}), isFalse);
      expect(f.matches(basicId: '', bigId: '', grade: 'A', workTypes: const {}), isFalse);
    });

    test('grade and type dimensions stack with library filters', () {
      final f = AuthorFilterState(
        basics: {'lib-001'},
        grades: {'S', 'A'},
        types: {workFilterVideo, workFilterPost},
      );
      expect(
          f.matches(
              basicId: 'lib-001',
              bigId: '',
              grade: 'A',
              workTypes: {workFilterVideo}),
          isTrue);
      expect(
          f.matches(
              basicId: 'lib-001',
              bigId: '',
              grade: 'C',
              workTypes: {workFilterVideo}),
          isFalse);
      expect(
          f.matches(
              basicId: 'lib-001',
              bigId: '',
              grade: 'S',
              workTypes: {workFilterPicture}),
          isFalse);
      expect(
          f.matches(
              basicId: 'lib-001', bigId: '', grade: 'S', workTypes: const {}),
          isFalse);
    });

    test('type-only filter rejects authors without type data', () {
      final f = AuthorFilterState(types: {workFilterCollection});
      expect(f.matches(basicId: '', bigId: '', grade: 'B', workTypes: const {}),
          isFalse);
      expect(
          f.matches(
              basicId: '',
              bigId: '',
              grade: 'B',
              workTypes: {workFilterCollection}),
          isTrue);
    });

    test('toggle and clear', () {
      final f = AuthorFilterState();
      f.toggleBasic('lib-001');
      f.toggleBasic('lib-002');
      f.toggleBasic('lib-001');
      f.toggleBig('big-01');
      f.toggleGrade('A');
      f.toggleType(workFilterPost);
      expect(f.basics, {'lib-002'});
      expect(f.activeCount, 4);
      expect(f.isActive, isTrue);
      f.clear();
      expect(f.isActive, isFalse);
    });

    test('summary lists active dimensions', () {
      final f = AuthorFilterState(
          basics: {'lib-001'}, grades: {'A'}, types: {workFilterVideo});
      final s = f.summary(basicNames: {'lib-001': '足'});
      expect(s.contains('基础库 足'), isTrue);
      expect(s.contains('等级 A'), isTrue);
      expect(s.contains('视频'), isTrue);
      expect(AuthorFilterState().summary(), '未筛选');
    });
  });

  group('author types', () {
    test('kind mapping covers all four categories', () {
      expect(authorTypeFromKind('v:single'), workFilterVideo);
      expect(authorTypeFromKind('p:post'), workFilterPost);
      expect(authorTypeFromKind('v:chapters'), workFilterCollection);
      expect(authorTypeFromKind('p:album'), workFilterCollection);
      expect(authorTypeFromKind('p:single'), workFilterPicture);
      expect(authorTypeFromKind('unknown'), '');
    });

    test('parses kinds and ignores zero/bad entries', () {
      final m = authorTypesFromIndex({
        'authors': [
          {
            'name': 'A',
            'kinds': {'v:single': 2, 'p:post': 1}
          },
          {
            'name': 'B',
            'kinds': {'p:album': 0}
          },
          {'name': '', 'kinds': {'v:single': 1}},
          'bad',
        ]
      });
      expect(m['A'], {workFilterVideo, workFilterPost});
      expect(m.containsKey('B'), isFalse);
      expect(authorTypesFromIndex(null), isEmpty);
      expect(authorTypesFromIndex({'authors': 'x'}), isEmpty);
    });

    test('merges multiple basic-library indexes', () {
      final m = mergeAuthorTypes([
        {
          'A': {workFilterVideo}
        },
        {
          'A': {workFilterPost},
          'B': {workFilterPicture}
        },
      ]);
      expect(m['A'], {workFilterVideo, workFilterPost});
      expect(m['B'], {workFilterPicture});
    });

    test('ignores non-index payloads instead of throwing', () {
      // T3：旧「收藏夹」工作列表汇总已移除，类型索引只剩基础库 index.json 一条路径。
      expect(authorTypesFromIndex(null), isEmpty);
      expect(authorTypesFromIndex('bad'), isEmpty);
      expect(authorTypesFromIndex({'authors': 'bad'}), isEmpty);
    });
  });

  group('applyAuthorFilter', () {
    final items = <Map<String, dynamic>>[
      {'n': 'A', 'g': 'S', 't': workFilterVideo},
      {'n': 'B', 'g': 'B', 't': workFilterPost},
      {'n': 'C', 'g': 'B', 't': workFilterVideo},
    ];
    bool match(Map<String, dynamic> e, AuthorFilterState f) =>
        f.matches(
            basicId: 'lib-1', bigId: '', grade: e['g'] as String,
            workTypes: {e['t'] as String});

    test('returns a copy when filter inactive', () {
      final out = applyAuthorFilter(items, AuthorFilterState(), match);
      expect(out.length, 3);
      expect(identical(out, items), isFalse);
    });

    test('filters by grade and type across lists', () {
      final out = applyAuthorFilter(
          items, AuthorFilterState(grades: {'B'}), match);
      expect(out.map((e) => e['n']), ['B', 'C']);
      final v = applyAuthorFilter(items,
          AuthorFilterState(grades: {'B'}, types: {workFilterVideo}), match);
      expect(v.map((e) => e['n']), ['C']);
    });
  });
  group('AuthorFilterState · P3 顶级节点维度', () {
    test('顶级节点收敛整棵子树：其下单元库/基础库命中，其它顶级不命中', () {
      final f = AuthorFilterState(tops: {'T1'});
      expect(f.isActive, isTrue);
      expect(f.activeCount, 1);
      // 顶级节点命中
      expect(
          f.matches(
              basicId: 'b1',
              bigId: '',
              unitId: 'T1',
              topId: 'T1',
              grade: 'A',
              workTypes: const {}),
          isTrue);
      // 子单元库 / 孙单元库都在 T1 子树下
      expect(
          f.matches(
              basicId: 'b1',
              bigId: '',
              unitId: 'T1/MID/LEAF',
              topId: 'T1',
              grade: 'A',
              workTypes: const {}),
          isTrue);
      // 另一个顶级节点下的条目被排除
      expect(
          f.matches(
              basicId: 'b2',
              bigId: '',
              unitId: 'T2/x',
              topId: 'T2',
              grade: 'A',
              workTypes: const {}),
          isFalse);
      // 无归属（三个 id 都空）也被排除：选库维度时不可归类即不命中
      expect(
          f.matches(
              basicId: '', bigId: '', grade: 'A', workTypes: const {}),
          isFalse);
    });

    test('顶级节点与单元库同属库维度，取并集不互相覆盖', () {
      final f = AuthorFilterState(tops: {'T1'}, units: {'T2/u'});
      expect(
          f.matches(
              basicId: 'b',
              bigId: '',
              unitId: 'T1/MID',
              topId: 'T1',
              grade: '',
              workTypes: const {}),
          isTrue);
      expect(
          f.matches(
              basicId: 'b',
              bigId: '',
              unitId: 'T2/u',
              topId: 'T2',
              grade: '',
              workTypes: const {}),
          isTrue);
      expect(
          f.matches(
              basicId: 'b',
              bigId: '',
              unitId: 'T3/other',
              topId: 'T3',
              grade: '',
              workTypes: const {}),
          isFalse);
    });

    test('toggleTop / clear / copy 覆盖新维度', () {
      final f = AuthorFilterState();
      f.toggleTop('T1');
      expect(f.tops, {'T1'});
      f.toggleTop('T1');
      expect(f.tops, isEmpty);
      f.toggleTop('T1');
      final g = f.copy();
      expect(g.tops, {'T1'});
      g.clear();
      expect(g.tops, isEmpty);
    });

    test('摘要优先显示媒体库（库根），名称缺省回落 id', () {
      final f = AuthorFilterState(tops: {'T1', 'T2'});
      // 按「解析后的名称」排序（缺省回落 id），与单元库/基础库口径一致。
      expect(f.summary(topNames: const {'T1': '甲'}), '媒体库 T2/甲');
      expect(AuthorFilterState().summary(), '未筛选');
    });
  });
}
