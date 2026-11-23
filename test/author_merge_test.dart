import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_merge.dart';

void main() {
  group('authorLibCount / authorSourceSummary', () {
    test('去空去重后计数', () {
      expect(authorLibCount(const []), 0);
      expect(authorLibCount(const ['', '  ']), 0);
      expect(authorLibCount(const ['lib-001']), 1);
      expect(authorLibCount(const ['lib-001', 'lib-001']), 1);
      expect(authorLibCount(const ['lib-001', 'lib-002']), 2);
      expect(authorLibCount(const ['lib-001', '', 'lib-002']), 2);
    });

    test('两个库以上才提示来源', () {
      expect(authorSourceSummary(const []), '');
      expect(authorSourceSummary(const ['lib-001']), '');
      expect(authorSourceSummary(const ['lib-001', 'lib-002']), '来自 2 个库');
      expect(authorSourceSummary(const ['a', 'b', 'c']), '来自 3 个库');
    });
  });

  group('groupWorksByLib', () {
    test('按 _lib 分组且保持首次出现顺序', () {
      final works = [
        {'id': 'w1', '_lib': 'lib-002'},
        {'id': 'w2', '_lib': 'lib-001'},
        {'id': 'w3', '_lib': 'lib-002'},
      ];
      final g = groupWorksByLib(works);
      expect(g.keys.toList(), ['lib-002', 'lib-001']);
      expect(g['lib-002']!.map((e) => e['id']), ['w1', 'w3']);
      expect(g['lib-001']!.map((e) => e['id']), ['w2']);
    });

    test('缺 _lib 的作品归到 fallback，非 Map 条目跳过', () {
      final g = groupWorksByLib(
        [
          {'id': 'w1'},
          'not-a-map',
          {'id': 'w2', '_lib': ''},
        ],
        fallbackLib: 'lib-009',
      );
      expect(g.keys.toList(), ['lib-009']);
      expect(g['lib-009']!.map((e) => e['id']), ['w1', 'w2']);
    });

    test('空输入返回空映射', () {
      expect(groupWorksByLib(const []), isEmpty);
    });
  });

  group('mergeAuthorWorks', () {
    test('按 id 去重，先到先得（主库优先）', () {
      final merged = mergeAuthorWorks([
        [
          {'id': 'dup', '_lib': 'lib-001', 'v': 'main'},
          {'id': 'a', '_lib': 'lib-001'},
        ],
        [
          {'id': 'dup', '_lib': 'lib-002', 'v': 'second'},
          {'id': 'b', '_lib': 'lib-002'},
        ],
      ]);
      expect(merged.map((e) => e['id']), ['dup', 'a', 'b']);
      expect(merged.first['v'], 'main');
      expect(merged.first['_lib'], 'lib-001');
    });

    test('id 为空的作品都保留（不静默丢内容）', () {
      final merged = mergeAuthorWorks([
        [
          {'_lib': 'lib-001'},
          {'_lib': 'lib-001'},
        ]
      ]);
      expect(merged.length, 2);
    });

    test('空批次不影响结果', () {
      expect(mergeAuthorWorks([const [], const []]), isEmpty);
    });
  });

  group('filterWorksByLib', () {
    final works = [
      {'id': 'w1', '_lib': 'lib-001'},
      {'id': 'w2', '_lib': 'lib-002'},
      {'id': 'w3', '_lib': ''},
    ];

    test('空库 = 全部', () {
      expect(filterWorksByLib(works).length, 3);
    });

    test('按库筛选，fallback 生效', () {
      expect(filterWorksByLib(works, lib: 'lib-001').map((e) => e['id']),
          ['w1']);
      expect(
        filterWorksByLib(works, lib: 'lib-009', fallbackLib: 'lib-009')
            .map((e) => e['id']),
        ['w3'],
      );
    });

    test('筛不中的库返回空列表', () {
      expect(filterWorksByLib(works, lib: 'lib-404'), isEmpty);
    });
  });

  group('libFilterOptions', () {
    test('按首次出现顺序给出 (lib, 作品数)', () {
      final opts = libFilterOptions([
        {'id': 'w1', '_lib': 'lib-002'},
        {'id': 'w2', '_lib': 'lib-001'},
        {'id': 'w3', '_lib': 'lib-002'},
      ]);
      expect(opts.map((e) => e.key), ['lib-002', 'lib-001']);
      expect(opts.map((e) => e.value), [2, 1]);
    });

    test('空库 id 不进入选项', () {
      final opts = libFilterOptions([
        {'id': 'w1', '_lib': ''},
        {'id': 'w2', '_lib': 'lib-001'},
      ]);
      expect(opts.map((e) => e.key), ['lib-001']);
    });
  });
}
