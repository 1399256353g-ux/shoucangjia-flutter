import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/label_fallback.dart';
import 'package:shoucangjia/lib_names.dart';
import 'package:shoucangjia/unit_author_groups.dart';

/// 0.9.352 第一百零七批契约。
///
/// 这一批是**同一条「库名怎么显示」的规则，在不同页面上各写一遍，边界数据
/// 上给出不同答案**：
///
/// | 位置 | 旧写法 | 名字为纯空格时 |
/// |---|---|---|
/// | `basic_lib_page` 页面标题 | `stripIndex(b.name)` | 标题整条空白 |
/// | `LibCardInfo` 调用方（单元库卡/基础库卡） | 直接传 `unit.name` / `basic.name` | 卡片标题空白 |
/// | 单元库页 AppBar / 首页顶级词条 | `stripIndex(unit.name)` | 空串（后缀孤零零） |
/// | `authors` 挂载面板 ×2 | 各自的 `trim().isEmpty` | 一份回落 id、一份空白 |
/// | `AuthorMountItem.displayLib` | 裸 `isEmpty` | 空白 |
/// | `_AuthorPageState.libLabel` | 两段手写循环，先 `allBasics` | 取到另一台服务器的名字 |
///
/// 隐私：全部合成 id / 名字（`lib-1` / `u1` / 纯空格），不读真实目录名，
/// 不涉及截图、媒体内容或 NAS 文件。
void main() {
  String codeOf(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  String allLib() {
    final dir = Directory('lib');
    final buf = StringBuffer();
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      buf.writeln(f.readAsStringSync().replaceAll('\r\n', '\n'));
    }
    return buf.toString();
  }

  /// 只保留代码行（注释里引用旧写法不算实现）。
  String codeOnly(String src) => [
        for (final line in src.split('\n'))
          if (!line.trimLeft().startsWith('//')) line,
      ].join('\n');

  group('1. 库名回落规则只有一处（labelOrId 派生）', () {
    test('libLabelOf 与 labelOrId 同一答案（含纯空格）', () {
      expect(libLabelOf('lib-1', '库甲'), '库甲');
      expect(libLabelOf('lib-1', '  库甲  '), '  库甲  ',
          reason: '本函数不改写展示文字，只做回落');
      expect(libLabelOf('lib-1', '   '), 'lib-1');
      expect(libLabelOf('lib-1', ''), 'lib-1');
      expect(libLabelOf('lib-1', null), 'lib-1');
      expect(libLabelOf('  lib-1  ', null), 'lib-1');
      for (final raw in <String?>['', '   ', null]) {
        expect(libLabelOf('lib-9', raw), labelOrId('lib-9', raw));
      }
    });

    test('挂载面板与 AuthorMountItem 都转发 libLabelOf，不再各写判空', () {
      final sheet = codeOnly(codeOf('lib/author_mount_sheet.dart'));
      final page = codeOnly(codeOf('lib/unit_author_mount_page.dart'));
      final groups = codeOnly(codeOf('lib/unit_author_groups.dart'));
      for (final src in <String>[sheet, page, groups]) {
        expect(src.contains('libLabelOf('), isTrue,
            reason: '三个入口都必须走同一条回落规则');
        // 旧写法：自己 trim 后判空（三份各一份）。
        expect(src.contains('libName.trim()'), isFalse);
        expect(src.contains('b.name.trim()'), isFalse);
        expect(src.contains('libName.isEmpty ? lib : libName'), isFalse);
      }
      expect(
          RegExp(r'String _libLabelOf\(String lib\) \{')
              .allMatches(sheet)
              .length,
          1);
      expect(
          RegExp(r'String _libLabelOf\(String lib\) \{')
              .allMatches(page)
              .length,
          1);
    });

    test('AuthorMountItem.displayLib 不再是裸 isEmpty', () {
      final src = codeOnly(codeOf('lib/unit_author_groups.dart'));
      expect(src.contains('String get displayLib => libLabelOf(lib, libName);'),
          isTrue);
      // 合成数据往返：纯空格名字 → id（旧写法给空串）。
      final item = AuthorMountItem.fromJson({
        'lib': 'lib-1',
        'libName': '   ',
        'authorDir': '作者甲',
      })!;
      expect(item.displayLib, 'lib-1');
    });
  });

  group('2. 目录节点标题（去序号 + 空回落 id）只有一处', () {
    test('libEntryTitle：有序号去序号、纯空格回落 id、正常名原样', () {
      expect(libEntryTitle('u1', '(1) 单元库'), '单元库');
      expect(libEntryTitle('u1', '   '), 'u1');
      expect(libEntryTitle('u1', ''), 'u1');
      expect(libEntryTitle('u1', null), 'u1');
      expect(libEntryTitle('u1', '单元库'), '单元库');
    });

    test('关闭「省略序号」开关时只做回落，不剥前缀', () {
      final before = AppSettings.stripLibIndex;
      AppSettings.stripLibIndex = false;
      try {
        expect(libEntryTitle('u1', '(1) 单元库'), '(1) 单元库');
        expect(libEntryTitle('u1', '   '), 'u1', reason: '回落到 id 不受开关影响');
      } finally {
        AppSettings.stripLibIndex = before;
      }
    });

    test('单元库页/基础库页/卡片不再自拼 stripIndex(名字)', () {
      final view = codeOnly(codeOf('lib/unit_library_view.dart'));
      final page = codeOnly(codeOf('lib/basic_lib_page.dart'));
      // 旧写法四条（页面标题、卡片标题 ×2、顶级词条）。
      expect(view.contains('LibraryBadge.stripIndex(title), unitId'), isTrue,
          reason: 'LibCardInfo 只做渲染，回落由调用方 libEntryTitle 完成');
      expect(view.contains('title: unit.name,'), isFalse);
      expect(view.contains('title: basic.name,'), isFalse);
      expect(view.contains('label: LibraryBadge.stripIndex(unit.name),'), isFalse);
      expect(
          view.contains('LibraryBadge.stripIndex(unit.name), unit.id)),'),
          isFalse);
      expect(view.contains('title: libEntryTitle(unit.id, unit.name),'), isTrue);
      expect(view.contains('title: libEntryTitle(basic.id, basic.name),'), isTrue);
      expect(view.contains('label: libEntryTitle(unit.id, unit.name),'), isTrue);
      // 基础库页 AppBar 走库名唯一出口。
      expect(page.contains('title: Text(libraryDisplayName(b.id, b.name)'),
          isTrue);
      expect(page.contains('title: Text(LibraryBadge.stripIndex(b.name)'),
          isFalse);
    });

    test('LibCardInfo 仍然只做「去序号 + 后缀」，不自己猜 id', () {
      final view = codeOnly(codeOf('lib/unit_library_view.dart'));
      expect(
          view.contains(
              'LibraryBadge.labelWithEmoji(LibraryBadge.stripIndex(title), unitId)'),
          isTrue);
      // 不能在本组件里出现 libEntryTitle(title) —— 它不知道对应哪个库。
      expect(view.contains('libEntryTitle(title'), isFalse);
    });
  });

  group('3. 作者页来源库名不再重写 basicById 的查找顺序', () {
    test('_AuthorPageState.libLabel 只调 basicById + 库名唯一出口', () {
      final main = codeOnly(codeOf('lib/main.dart'));
      final start = main.indexOf('String libLabel(String id) {');
      expect(start, greaterThan(0));
      final body = main.substring(start, main.indexOf('}', start));
      expect(body.contains('meta?.basicById(id)'), isTrue);
      expect(body.contains('libraryDisplayName('), isTrue);
      // 旧写法：两段手写循环（allBasics 在前，与文档/ basicById 顺序相反）。
      expect(body.contains('for (final b in'), isFalse);
      expect(body.contains('allBasics'), isFalse);
    });

    test('libLabel 对未知 id 回落 id 本身', () {
      // 规则层：labelOrId 的答案就是 libLabel 的兜底（同一函数族）。
      expect(labelOrId('lib-404', null), 'lib-404');
    });
  });

  group('4. lib/ 内不再有「只 stripIndex 不回落」的标题写法', () {
    test('除渲染层转发外，lib/ 里 stripIndex(…) 的调用点屈指可数', () {
      final lib = codeOnly(allLib());
      final hits = RegExp(r'LibraryBadge\.stripIndex\(').allMatches(lib).length;
      // 允许的转发点：LibCardInfo 内 1、LibBadgeChip 内 1、lib_names 2、
      // library_badge.labels 1、设置页分组头/继承源 2、爬虫分节 2、
      // 删除监测/排行榜顶部筛选 2、爬虫配置页 1、单元库页 badgeText 1。
      expect(hits, lessThanOrEqualTo(16), reason: '实际 $hits 处');
    });

    test('基础库 BasicLib 名字本身不被改写（模型层保持原样）', () {
      final b = BasicLib(
        id: 'lib-1',
        name: '   ',
        rel: 'A',
        bigId: '',
        authors: 1,
        works: 2,
      );
      expect(b.name, '   ', reason: '模型只存服务端下发的原串');
    });
  });
}
