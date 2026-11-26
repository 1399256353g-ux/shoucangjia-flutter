import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_big_nodes.dart';
import 'package:shoucangjia/author_filter.dart';
import 'package:shoucangjia/json_num.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/stable_order.dart';
import 'package:shoucangjia/text_clip.dart';
import 'package:shoucangjia/unit_library.dart';

/// 第三十三批：截断切开代理对 / 同名排序不稳定 / 大库选项两套写法 /
/// 字符串形式的非有限数值。
///
/// 四条都是「测试全绿、真机上看得出」的形态：
///  - 词条/文件名/备注按 UTF-16 单元硬切，切点落在 emoji 上 → 界面与磁盘
///    文件名里出现替换方块；
///  - 单元库树/分类树按名称排序用 `List.sort`（**不稳定**），同名的同级项
///    每次重建都可能换位置 → 刷新一下卡片顺序自己变了；
///  - 「大库 / 单元库」筛选项在推荐页与搜索页各写一套去重 + 排序，同一库里
///    两个页面显示的名字与顺序都可能不同；
///  - `double.tryParse('NaN')` / `'1e999'` 是**合法解析**：字符串分支没有
///    `isFinite` 守卫，NaN 一路进到 `Border.all(width: NaN)` 与 `clamp`。
void main() {
  group('截断：不得切开 UTF-16 代理对', () {
    test('emoji 正好放得下时原样返回', () {
      const s = '🎬🎬'; // 4 个单元：每个 emoji 占两个
      expect(clipToUnits(s, 4), s);
      expect(clipToUnits(s, 5), s);
    });

    test('截断点落在代理对中间时丢掉那个高位代理', () {
      const s = '🎬🎬🎬';
      final cut = clipToUnits(s, 3); // 第 3 个单元是第二个 emoji 的高位
      expect(cut, '🎬');
      expect(cut.codeUnits.length, 2);
      expectNoLoneSurrogate(cut);
    });

    test('混合中英文与 emoji：任意上限都只在安全边界切', () {
      const s = '库a🎬b';
      for (var n = 1; n <= s.length; n++) {
        final out = clipToUnits(s, n);
        expectNoLoneSurrogate(out);
        expect(out.length <= n, isTrue);
        expect(s.startsWith(out), isTrue, reason: 'n=$n 必须是前缀');
      }
    });

    test('省略号只在真的截断时追加', () {
      expect(clipWithEllipsis('短名称', 10), '短名称');
      expect(clipWithEllipsis('这是一个很长的库名称', 4), '这是一个…');
      expect(clipWithEllipsis('🎬🎬🎬', 3), '🎬…');
    });

    test('上限 <= 0 返回空串，不抛', () {
      expect(clipToUnits('abc', 0), '');
      expect(clipToUnits('abc', -3), '');
      expect(clipWithEllipsis('abc', 0), '');
    });

    test('爬虫备注 / 错误文案 / 播放错误摘要都走同一实现', () {
      // 三个函数在各自文件里已改为 clipToUnits/clipWithEllipsis；
      // 这里钉住行为：超长时结果无孤立代理且不超上限。
      final note = clipToUnits('备注${'🎬' * 120}', 200);
      expectNoLoneSurrogate(note);
      expect(note.length <= 200, isTrue);
    });
  });

  group('稳定排序：相等元素保持输入顺序', () {
    test('同分元素顺序不变（对照：List.sort 不保证）', () {
      final items = List<int>.generate(40, (i) => i);
      stableSort<int>(items, (a, b) => (a ~/ 10).compareTo(b ~/ 10));
      expect(items, List<int>.generate(40, (i) => i));
    });

    test('按名称排序：同名项保持输入顺序', () {
      final names = <String>['b', 'a', 'a', 'b', 'a'];
      final indexed = List<int>.generate(names.length, (i) => i);
      stableSort<int>(indexed, (x, y) => names[x].compareTo(names[y]));
      expect(indexed, <int>[1, 2, 4, 0, 3]);
      expect(
        stableSortByName<String>(List<String>.of(names), (s) => s),
        <String>['a', 'a', 'a', 'b', 'b'],
      );
    });

    test('单个与空列表安全', () {
      expect(stableSortByName<String>(<String>[], (s) => s), isEmpty);
      expect(stableSortByName<String>(<String>['x'], (s) => s), <String>['x']);
    });

    test('固定长度列表也能排序（setAll 而非逐个下标赋值）', () {
      final fixed = List<String>.filled(3, 'z');
      fixed[0] = 'c';
      fixed[1] = 'a';
      fixed[2] = 'b';
      stableSortByName<String>(fixed, (s) => s);
      expect(fixed, <String>['a', 'b', 'c']);
    });

    test('单元库树：同名单元库的顺序在两次构建中一致', () {
      const nodes = <LibNode>[
        LibNode(id: 'X', rel: 'p', name: '同名'),
        LibNode(id: 'Y', rel: 'q', name: '同名'),
      ];
      final basics = <BasicLib>[
        basic('bx', 'p/a'),
        basic('by', 'q/a'),
      ];
      final first = buildUnitTree(nodes: nodes, basics: basics)!;
      final second = buildUnitTree(nodes: nodes, basics: basics)!;
      expect(flattenNames(first), flattenNames(second));
      // 同名两层都保留（不是被去重吃掉一个）。
      expect(flattenNames(first).where((n) => n == '同名').length, 2);
    });
  });

  group('大库（单元库）筛选项只有一套实现', () {
    test('按 bigId 去重、名称回落 id、同名按 id 升序', () {
      const basics = <AuthorLibNode>[
        AuthorLibNode(id: 'b1', name: '基础1', bigId: 'u2'),
        AuthorLibNode(id: 'b2', name: '基础2', bigId: 'u1'),
        AuthorLibNode(id: 'b3', name: '基础3', bigId: 'u2'),
        AuthorLibNode(id: 'b4', name: '基础4', bigId: ''),
      ];
      const names = <String, String>{'u1': '同名', 'u2': '同名'};
      final out = authorBigNodes(basics, nameOf: (id) => names[id] ?? id);
      expect(out.map((e) => e.id).toList(), <String>['u1', 'u2']);
      expect(out.map((e) => e.name).toList(), <String>['同名', '同名']);
    });

    test('名称回调给空串时回落到 id', () {
      final out = authorBigNodes(
        const <AuthorLibNode>[
          AuthorLibNode(id: 'b', name: 'x', bigId: 'u9')
        ],
        nameOf: (_) => '',
      );
      expect(out.single.name, 'u9');
    });

    test('去重排序只在 author_big_nodes；页面不再各写一份 _filterBigs', () {
      final main = codeOfLib('lib/main.dart');
      final opts = codeOfLib('lib/author_filter_options.dart');
      expect(main.contains('out.removeWhere((e) => !seen.add(e.id));'), isFalse,
          reason: '推荐页的大库去重还在手写');
      // 0.9.319：两页的 `_filterBigs` 都收进 `author_filter_options`，
      // `main.dart` 不再直接调 `authorBigNodes`（否则又是「一处规则、两处调用」）。
      expect(main.contains('authorBigNodes('), isFalse,
          reason: '页面不该自己汇总筛选项');
      expect(main.contains('List<AuthorBigNode> get _filterBigs'), isFalse,
          reason: '两页各一份选项构造已经合并');
      expect(opts.contains('authorBigNodes('), isTrue,
          reason: '唯一汇总点必须转调 author_big_nodes.dart');
      expect(main.contains('authorFilterOptionsFrom('), isTrue);
    });
  });

  group('字符串形式的非有限数值不得漏进 UI', () {
    test('doubleOrNull / numOrNull 拒绝 NaN / Infinity / 1e999 字符串', () {
      for (final raw in <String>['NaN', 'Infinity', '-Infinity', '1e999']) {
        expect(doubleOrNull(raw), isNull, reason: raw);
        expect(numOrNull(raw), isNull, reason: raw);
      }
    });

    test('合法数字字符串照旧解析', () {
      expect(doubleOrNull('1.5'), 1.5);
      expect(doubleOrNull(' 2 '), 2.0);
      expect(numOrNull('3'), 3);
      expect(intOrNull('7'), 7);
      expect(doubleOf('NaN', 1.25), 1.25);
    });

    test('词条外观解析遇到 "NaN" 不产生 NaN 边框', () {
      // EntryStyle.fromJson → clampW/clampA；NaN 会让 Border.all 断言失败。
      final style = EntryStyle.fromJson(<String, dynamic>{
        'w': 'NaN',
        'ba': 'Infinity',
        'fa': '1e999',
      }, kDefaultEntryStyle[LibEntryKind.basic]!);
      expect(style.borderWidth.isFinite, isTrue);
      expect(style.borderAlpha.isFinite, isTrue);
      expect(style.fillAlpha.isFinite, isTrue);
      expect(style.borderWidth, kDefaultEntryStyle[LibEntryKind.basic]!.borderWidth);
    });
  });

  group('契约：单一实现不允许被绕开', () {
    test('unit_library / category_tree 不再裸 sort(by name)', () {
      for (final f in <String>['lib/unit_library.dart', 'lib/category_tree.dart']) {
        final src = codeOfLib(f);
        expect(src.contains('.sort((a, b) => a.name.compareTo(b.name))'),
            isFalse,
            reason: '$f 又出现不稳定排序');
        expect(src.contains('stableSort'), isTrue, reason: '$f 未走稳定排序');
      }
    });

    test('按长度截断显示文案只允许出现在 text_clip', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final path = f.path;
        if (path.endsWith('text_clip.dart')) continue;
        final src = codeOfLib(path);
        // 只抓「按长度切成显示文案」的形状：`length > N ? ... substring(0,`
        if (RegExp(r'\.length\s*>\s*\d+\s*\?\s*[^;\n]*substring\(0,')
            .hasMatch(src)) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty, reason: '显示截断绕过了 text_clip：$offenders');
    });
  });
}

BasicLib basic(String id, String rel) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 1,
    );

void expectNoLoneSurrogate(String s) {
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    if (u >= 0xD800 && u <= 0xDBFF) {
      final next = i + 1 < s.length ? s.codeUnitAt(i + 1) : 0;
      expect(next >= 0xDC00 && next <= 0xDFFF, isTrue, reason: '孤立高位代理 @$i');
      i++;
    } else {
      expect(u >= 0xDC00 && u <= 0xDFFF, isFalse, reason: '孤立低位代理 @$i');
    }
  }
}

List<String> flattenNames(UnitLibrary u) {
  final out = <String>[u.name];
  for (final c in u.children) {
    out.addAll(flattenNames(c));
  }
  return out;
}

/// 读源码并去掉整行注释（避免把文档里的旧写法当成缺陷）。
String codeOfLib(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');
