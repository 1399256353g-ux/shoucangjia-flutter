import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/lib_names.dart';

/// 0.9.355 第一百一十批契约。
///
/// 主题与上一批同族：「库名怎么显示」已经有唯一出口
/// （`libEntryTitle` = 去序号 + 名字空回落 id，`libraryDisplayName` = 规范化 +
/// 去序号），但仍有三处页面**自己拼原始字段**：
///
/// 1. 分类树页标题 `Text('分类 · ${basic.name}')`——只原样输出：名字为空时
///    标题只剩「分类 · 」，目录名带 `(1) ` 时原样露出，而同一个基础库在
///    单元库页/基础库卡标题上都是去序号 + 回落 id。
/// 2. 单元库页基础库卡片词条 `unitLabel: unit.name`——词条名字与卡片标题
///    走两个来源：标题（`libEntryTitle`）回落 id、词条回落到**本库**名字。
/// 3. 爬虫设置页「设为默认媒体库 / 删除库」两条文案 `'${l['name']}'`，
///    以及搜索页库筛选 chip `'${l['name'] ?? l['id']}'`——同一条注册库在
///    列表里是 `libraryDisplayName` 的结果，在这三处是原始名。
///
/// 另外清掉一处**死表**：单元库页 `ownerLabel`（子树遍历出来的
/// 「基础库 → 上级单元库名」）从未被读过，只有 `ownerKey` 在用。
///
/// 隐私：全部合成 id / 名字（`lib-1` / `u1` / 纯空格），不读真实目录名、
/// 不涉及截图与媒体内容。
void main() {
  final mainSrc = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
  final viewSrc =
      File('lib/unit_library_view.dart').readAsStringSync().replaceAll('\r\n', '\n');
  final catSrc =
      File('lib/category_tree_page.dart').readAsStringSync().replaceAll('\r\n', '\n');

  /// 只保留代码行（注释里引用旧写法不算实现）。
  List<String> codeLines(String src) => [
        for (final line in src.split('\n'))
          if (!line.trimLeft().startsWith('//')) line,
      ];
  String codeOnly(String src) => codeLines(src).join('\n');

  group('1. 分类树页标题走同一个出口', () {
    test('标题不再自拼 basic.name', () {
      final code = codeOnly(catSrc);
      expect(code.contains('分类 · \${widget.basic.name}'), isFalse,
          reason: '原样输出名字：空名时标题只剩「分类 · 」');
      expect(code.contains('${''}\u0024{libEntryTitle(widget.basic.id'), isTrue,
          reason: '标题必须走 libEntryTitle（去序号 + 回落 id）');
    });

    test('出口对三条边界给出预期答案（钉住缺口本身）', () {
      // 旧写法 `'分类 · ${name}'` 在这三条上分别得到 `分类 · `、`分类 · (1) X`。
      expect(libEntryTitle('lib-1', ''), 'lib-1');
      expect(libEntryTitle('lib-1', '   '), 'lib-1');
      expect(libEntryTitle('lib-1', '(1) 分类'), '分类');
    });
  });

  group('2. 单元库页基础库卡片词条与标题同一个出口', () {
    test('unitLabel 传 libEntryTitle 的结果', () {
      final code = codeOnly(viewSrc);
      expect(code.contains('unitLabel: unit.name,'), isFalse);
      expect(code.contains('unitLabel: libEntryTitle(unit.id, unit.name),'),
          isTrue);
    });

    test('ownerLabel 死表已删，ownerKey 仍保留（封面菜单作用域要用）', () {
      final code = codeOnly(viewSrc);
      expect(code.contains('ownerLabel'), isFalse,
          reason: '那张表只写不读，留着会让人以为词条走它');
      expect(code.contains('ownerKey[b.id] = u.id;'), isTrue);
      expect(code.contains('ownerKey['), isTrue);
    });

    // 卡片词条的回退值必须是「词条代表的那一层」：有单元库就回落单元库 id。
    test('回退 id 的口径不变（有单元库用单元库 id）', () {
      expect(libEntryTitle('u1', ''), 'u1');
      expect(libEntryTitle('lib-1', ''), 'lib-1');
    });
  });

  group('3. 注册库的提示文案与筛选 chip 走 libraryDisplayName', () {
    test('「设为默认 / 删除库」两条文案不再拼原始 name', () {
      final code = codeOnly(mainSrc);
      expect(code.contains("'已将「\${l['name']}」设为默认媒体库'"), isFalse);
      expect(code.contains("'删除库「\${l['name']}」？'"), isFalse);
      expect(code.contains('设为默认媒体库'), isTrue);
      expect(code.contains('删除库「'), isTrue);
      expect(
          RegExp(r"libraryDisplayName\(\s*id,\s*'\$\{l\['name'\] \?\? ''\}'\)")
              .hasMatch(code),
          isTrue,
          reason: '文案里的库名必须与列表行同一出口');
    });

    test('搜索页库筛选 chip 不再裸拼 name / id', () {
      final code = codeOnly(mainSrc);
      expect(code.contains("Text('\${l['name'] ?? l['id']}')"), isFalse);
      expect(
          RegExp(r"label: Text\(libraryDisplayName\(\s*'\$\{l\['id'\] \?\? ''\}'")
              .hasMatch(code),
          isTrue);
    });

    test('出口语义：空名回落 id、旧「抖音收藏」收敛为 id', () {
      // 用合成 id 钉住规则本身，不依赖任何真实库名。
      expect(libraryDisplayName('lib-9', ''), 'lib-9');
      expect(libraryDisplayName('lib-9', '   '), 'lib-9');
      expect(libraryDisplayName('lib-9', '(1) 名称'), '名称');
    });
  });

  group('4. 没有第二份实现（防回归）', () {
    test('lib/ 内不再有「分类 · 原始名字」或裸 name chip', () {
      final files = Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        final code = codeOnly(f.readAsStringSync().replaceAll('\r\n', '\n'));
        expect(code.contains('分类 · \${widget.basic.name}'), isFalse,
            reason: '${f.path} 仍在原样拼基础库名');
      }
    });
  });
}
