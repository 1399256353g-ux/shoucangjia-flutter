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

    test('aggregates types from collection work lists', () {
      final m = authorTypesFromCollections([
        {
          'works': [
            {'a': 'A', 't': 'v', 'm': ['x.mp4']},
            {'a': 'A', 't': 'p', 'm': ['1.jpg', '2.jpg']},
            {'a': 'B', 't': 'p', 'm': ['1.jpg']},
            {'a': 'C', 't': 'x'},
            'bad',
          ]
        },
        {
          'works': [
            {'a': 'A', 't': 'p', 'm': ['1.jpg', '2.jpg', '3.jpg']},
          ]
        },
        'bad',
      ]);
      expect(m['A'], {workFilterVideo, workFilterPost});
      expect(m['B'], {workFilterPicture});
      expect(m.containsKey('C'), isFalse);
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
}
