import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_big_nodes.dart';
import 'package:shoucangjia/author_filter.dart';
import 'package:shoucangjia/author_filter_options.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/label_fallback.dart';
import 'package:shoucangjia/lib_names.dart';
import 'package:shoucangjia/library_rank.dart';
import 'package:shoucangjia/unit_library.dart';

/// 0.9.351 第一百零六批契约。
///
/// 这一批是**同一条判定写了两遍、两份在边界数据上给出两个答案**：
///
/// | 规则 | 写法 A（去空白） | 写法 B（裸判空） | 后果 |
/// |---|---|---|---|
/// | 名字为空回落 id | `trim().isEmpty ? id : name` | `isEmpty ? id : name` | 名字是纯空格时一个回落 id、一个画成空白 |
/// | 多份元数据的末级回落 | `_metaForAuthorPage` 里写死 | `_rowMeta` 里再写一遍 | 榜单词条与作者卡可能来自不同服务器 |
/// | 「全量基础库优先」 | `LibMeta.filterBasics` | `_createAuthor` 里重写一遍 | 建目录下拉与筛选面板列出不同的库 |
///
/// 隐私：全部使用合成 id / 名字（`lib-1` / `u1` / `t1` / `b1`），不读任何
/// 真实目录名，不涉及截图或媒体内容。
void main() {
  String codeOf(String path) => File(path)
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  /// `lib/` 全部源码拼接（契约扫描用）。
  String allLib() {
    final dir = Directory('lib');
    final buf = StringBuffer();
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      buf.writeln(f.readAsStringSync().replaceAll('\r\n', '\n'));
    }
    return buf.toString();
  }

  group('1. 名字为空回落 id 只有一处实现', () {
    test('去空白后为空才回落 id；非空原样返回', () {
      expect(labelOrId('t1', '媒体库甲'), '媒体库甲');
      expect(labelOrId('t1', ''), 't1');
      expect(labelOrId('t1', null), 't1');
      // 关键边界：纯空白是「没有名字」，不是「一个空名字」。
      expect(labelOrId('t1', '   '), 't1');
      expect(labelOrId('t1', '\t\n'), 't1');
      // 有内容时保留原串（不 trim 展示文字，去空白是判定的事）。
      expect(labelOrId('t1', ' 名 '), ' 名 ');
    });

    test('id 自身也被 trim：空白 id 不能画成词条', () {
      expect(labelOrId('  ', '  '), '');
    });

    test('筛选/设置/排行四处走同一个函数', () {
      final src = allLib();
      // 裸判空（旧写法）在名字回落这条规则上不得再出现。
      for (final bad in <String>[
        "name.isEmpty ? top.id : top.name",
        "u.name.isEmpty ? id : u.name",
        "name.isEmpty ? ids[i] : name",
        "t.name.trim().isEmpty ? t.id : t.name",
      ]) {
        expect(src.contains(bad), isFalse, reason: '旧写法仍在：$bad');
      }
      // 四个入口都转发 labelOrId。
      expect(codeOf('lib/author_big_nodes.dart').contains('labelOrId('), isTrue);
      expect(codeOf('lib/author_filter_options.dart').contains('labelOrId('),
          isTrue);
      expect(codeOf('lib/library_badge.dart').contains('labelOrId('), isTrue);
      expect(codeOf('lib/library_rank.dart').contains('labelOrId('), isTrue);
      expect(codeOf('lib/main.dart').contains('labelOrId('), isTrue);
    });

    test('行为钉住差异：纯空格名字在旧写法下是空白，新写法下是 id', () {
      // 旧写法两种（等价于分别调用）：`name.isEmpty ? id : name` 与
      // `name.trim().isEmpty ? id : name`。这一条证明它们真的不同答案。
      const name = '   ';
      const id = 't9';
      expect(name.isEmpty ? id : name, name,
          reason: '裸判空：空白名字被当成有效名字');
      expect(labelOrId(id, name), id, reason: '统一实现：回落 id');
    });

    test('历史分组（big）与顶级节点两条汇总都跟着这条规则', () {
      final basics = <AuthorLibNode>[
        const AuthorLibNode(id: 'b1', name: 'b1', bigId: 'g1'),
      ];
      // 名称表给一个纯空格：应回落 id，不产生空白词条。
      final nodes = authorBigNodes(basics, nameOf: (_) => '   ');
      expect(nodes.single.name, 'g1');

      final opts = authorFilterOptionsFrom(
        basics: <BasicLib>[
          const BasicLib(
            id: 'b1',
            name: 'b1',
            rel: 'r1',
            bigId: 'g1',
            authors: 1,
            works: 1,
          ),
        ],
        tops: <UnitLibrary>[],
      );
      expect(opts.bigNames['g1'], 'g1');
    });

    test('各库排行榜的库名同样回落 id', () {
      final rows = buildLibraryRank(
        libs: <Map<String, dynamic>>[
          {'id': 'lib-1', 'name': '  ', 'baseOk': true, 'indexOk': true},
        ],
        stats: <String, Map<String, dynamic>>{
          'lib-1': {'authors': <String, dynamic>{}},
        },
        metric: 'play',
      );
      expect(rows.single.name, 'lib-1');
    });
  });

  group('2. 多份元数据的末级回落只有一处', () {
    test('偏好顺序命中第一个；全不命中时取任意一份', () {
      // 用一个最小替身观察「按 id 取」的行为：`metaFirstOf` 只读 Map。
      final metas = <String, int>{'a': 1, 'b': 2};
      expect(_pickFirst(metas, ['x', 'b', 'a']), 2);
      expect(_pickFirst(metas, ['a']), 1);
      expect(_pickFirst(metas, <String>[]), 1, reason: '空偏好取任意一份');
      expect(_pickFirst(<String, int>{}, ['a']), null, reason: '没有 meta 返回 null');
    });

    test('main.dart 里回落表达式只出现一次，且两个页面都调它', () {
      final main = codeOf('lib/main.dart');
      // 只数**代码行**：`return` 形式的回落本体只允许一处（`metaFirstOf`）。
      // 文档注释里引用旧写法不算实现。
      final code = main
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
          RegExp(r'metas\.isEmpty\s*\?\s*null\s*:\s*metas\.values\.first')
              .allMatches(code)
              .length,
          1);
      expect(main.contains('metaFirstOf('), isTrue);
      expect('metaFirstOf('.allMatches(main).length, greaterThanOrEqualTo(3));
    });
  });

  group('3. 「全量基础库优先」只有 LibMeta.filterBasics 一处', () {
    test('建目录下拉不再重写 allBasics/basics 三元表达式', () {
      final main = codeOf('lib/main.dart');
      expect(main.contains('meta.allBasics.isNotEmpty ? meta.allBasics'),
          isFalse,
          reason: '同一判定两份拷贝，与 filterBasics 会分叉');
      expect(main.contains('meta.filterBasics'), isTrue);
    });
  });

  group('4. 词条色继承来源的显示名只有一处', () {
    test('设置页两行不再各拼一遍 stripIndex(unitNameOf(...))', () {
      final main = codeOf('lib/main.dart');
      expect(
          'LibraryBadge.stripIndex(meta?.unitNameOf(inheritedFrom) ?? \'\')'
              .allMatches(main)
              .length,
          lessThanOrEqualTo(1),
          reason: '两行各写一遍时，同一个分发源会显示成一个带序号一个不带');
      expect(main.contains('_inheritedSourceName('), isTrue);
    });
  });
  group('5. 库名展示出口也走同一条回落', () {
    test('空白库名回落 id，正常名字原样（去 emoji 修复后）', () {
      expect(displayLibraryName('lib-1', '  '), 'lib-1');
      expect(displayLibraryName('lib-1', ''), 'lib-1');
      expect(displayLibraryName('lib-1', null), 'lib-1');
      expect(displayLibraryName('lib-1', '库名甲'), '库名甲');
    });
  });
}

/// 与 `main.metaFirstOf` 同一规则的最小替身（不 import main.dart：
/// 那个文件带 Flutter 平台通道，测试里只验证规则本身）。
int? _pickFirst(Map<String, int> metas, List<String> preferred) {
  for (final id in preferred) {
    if (id.trim().isEmpty) continue;
    final hit = metas[id];
    if (hit != null) return hit;
  }
  return metas.isEmpty ? null : metas.values.first;
}
