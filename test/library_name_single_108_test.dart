import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/lib_names.dart';
import 'package:shoucangjia/unit_library_view.dart';

/// 0.9.353 第一百零八批契约。
///
/// 主题：「名字空 → 回落 id」这条规则 (`libEntryTitle`) 已经是唯一出口，但还有
/// 五个渲染点只做 `stripIndex`（只剥 `(1) ` 前缀、名字是空串就**原样返回空**）。
/// 服务端把库名下发成空串/纯空格时，同一个库在这些位置是一片空白，在卡片标题
/// 上却是 id——两边都不报错。
///
/// 本批把这五处全部转发到 `libEntryTitle`，并把 `BasicLibCard.badgeText`
/// 的签名改成「回落 id + 名字」两个参数（它必须知道这条词条代表哪一层）。
///
/// 隐私：全部合成 id / 名字（`lib-1` / `u1` / 纯空格），不读真实目录名，
/// 不涉及截图、媒体内容或 NAS 文件。
void main() {
  String codeOf(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  /// 只保留代码行（注释里引用旧写法不算实现）。
  String codeOnly(String src) => [
        for (final line in src.split('\n'))
          if (!line.trimLeft().startsWith('//')) line,
      ].join('\n');

  group('1. 词条文本与标题同一个出口', () {
    test('badgeText 转发 libEntryTitle：去序号 + 名字空回落 id', () {
      // 与服务端真实下发形态一致的三条边界。
      expect(BasicLibCard.badgeText('u1', '(8) 🦶'), '🦶');
      expect(BasicLibCard.badgeText('u1', ''), 'u1');
      expect(BasicLibCard.badgeText('u1', '   '), 'u1');
      expect(BasicLibCard.badgeText('u1', null), 'u1');
      // 与标题出口逐条同答案（同一条规则不能两个说法）。
      for (final raw in <String?>['(1) 名称', '', '   ', null, '名称']) {
        expect(BasicLibCard.badgeText('u9', raw), libEntryTitle('u9', raw));
      }
    });

    test('badgeText 体内不再有自己的 stripIndex 调用', () {
      final view = codeOnly(codeOf('lib/unit_library_view.dart'));
      final start = view.indexOf('static String badgeText(');
      expect(start, greaterThan(0));
      final body = view.substring(start, view.indexOf(';', start));
      expect(body.contains('stripIndex('), isFalse,
          reason: '只要转发 libEntryTitle，不要再自己剥一次序号');
      expect(body.contains('libEntryTitle('), isTrue);
    });

    test('基础库卡片词条按「有单元库就回落单元库 id」传参', () {
      final view = codeOnly(codeOf('lib/unit_library_view.dart'));
      expect(
          view.contains(
              'BasicLibCard.badgeText(hasUnit ? unitId : widget.basic.id,'),
          isTrue);
    });
  });

  group('2. 五个只剥序号的渲染点已收口', () {
    test('设置页单元库行 / 爬虫分节 / 设置页标题 都走 libEntryTitle', () {
      final main = codeOnly(codeOf('lib/main.dart'));
      expect(main.contains('LibraryBadge.stripIndex(u.name)'), isFalse,
          reason: '设置页单元库行：名字空时整行空白');
      expect(main.contains('LibraryBadge.stripIndex(b.name)'), isFalse,
          reason: '设置页基础库行同上');
      expect(main.contains('LibraryBadge.stripIndex(section.title)'), isFalse,
          reason: '爬虫分节标题同上');
      expect(main.contains('LibraryBadge.stripIndex(name)'), isFalse,
          reason: '设置页分组头用的是去掉回落的中间变量');
      // 三个新写法各至少出现一次。
      expect(main.contains('libEntryTitle(u.id, u.name)'), isTrue);
      expect(main.contains('libEntryTitle(b.id, b.name)'), isTrue);
      expect(main.contains('libEntryTitle(section.key, section.title)'), isTrue);
      expect(main.contains('libEntryTitle(top.id, top.name)'), isTrue);
    });

    test('爬虫配置页标题走 libEntryTitle（不再是裸 stripIndex）', () {
      final page = codeOnly(codeOf('lib/unit_crawler_page.dart'));
      expect(page.contains('LibraryBadge.stripIndex('), isFalse);
      expect(page.contains('libEntryTitle(widget.unit.id, widget.unit.name)'),
          isTrue);
    });

    test('设置页继承源名字也走同一个出口', () {
      final main = codeOnly(codeOf('lib/main.dart'));
      final start = main.indexOf('String _inheritedSourceName(');
      expect(start, greaterThan(0));
      final body = main.substring(start, main.indexOf('\n\n', start));
      expect(body.contains('stripIndex('), isFalse);
      expect(body.contains('libEntryTitle('), isTrue);
    });
  });

  group('3. 叫不出名字的按键不再显示内部十进制键码', () {
    test('未知键码显示可读的十六进制', () {
      const odd = 99999999;
      final label = AppSettings.keyLabelById(odd);
      expect(label.contains('0x${odd.toRadixString(16).toUpperCase()}'), isTrue);
      expect(label.contains('按键#'), isFalse,
          reason: '`按键#99999999` 是 Flutter 内部键码，用户看不懂');
    });
  });
}
