import 'dart:io';

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
  _loadPathContract();
}

void _loadPathContract() {
  // 作者页加载路径与合并规则必须是同一份实现（0.9.199）。
  //
  // 这段不是普通单测：它读 `lib/main.dart` 的真实源码，断言作者页
  // 走的是 mergeAuthorWorks，而不是自己再写一遍 `seen` 去重循环。
  // 一旦有人把那份循环加回来，这里立刻变红——单测再绿也说明不了
  // 真实路径用的是它。
  group('作者页加载路径只用一份合并规则', () {
    final src = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

    test('作者页调用 mergeAuthorWorks', () {
      expect(src.contains('mergeAuthorWorks('), isTrue);
    });

    test('作者页不再自己维护去重集合', () {
      // 旧实现的特征行：`if (id.isNotEmpty && !seen.add(id)) continue;`
      expect(src.contains('!seen.add(id)'), isFalse);
    });

    test('合并器每家只收一次（_libs 顺序即主库优先）', () {
      final i = src.indexOf('works = mergeAuthorWorks(perLib);');
      expect(i, greaterThan(0));
      // 收集循环必须出现在合并调用之前，而不是边拉边写 works。
      expect(src.indexOf('perLib.add(['), lessThan(i));
    });
  });
}
