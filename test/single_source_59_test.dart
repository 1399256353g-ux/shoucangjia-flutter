import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/library_badge.dart';

/// 0.9.316 第八十二批：
///  1. 「末梢才分发」那套表整体删除（规则已推翻，留着就是永远为真的判定）；
///  2. 作者行库归属 `authorRowIdsFor` 零调用点，删除；
///  3. `LibMeta.bigIdFor` 与 `basicIdForPath` 两条反查链，收成一条；
///  4. 单元库爬虫页同时贴相对路径与绝对路径两行，删掉相对路径那行。
void main() {
  String codeOf(String path) => File(path)
      .readAsStringSync().replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('分发规则推翻后，末梢那套表不得复活', () {
    test('LibraryBadge 无 leafUnits / canDistribute', () {
      final s = codeOf('lib/library_badge.dart');
      expect(s.contains('leafUnits'), isFalse);
      expect(s.contains('canDistribute'), isFalse);
    });

    test('UnitLibrary 无 isLeaf / leafUnitIds，注册表不再有 leaf 视图', () {
      final s = codeOf('lib/unit_library.dart');
      expect(s.contains('leafUnitIds'), isFalse);
      expect(s.contains('get leaf =>'), isFalse);
      expect(s.contains('LibraryBadge.leafUnits'), isFalse);
    });

    test('分发链只由 parentOfUnit 逐级上行决定', () {
      final s = codeOf('lib/library_badge.dart');
      expect(s.contains('parentOfUnit'), isTrue);
      // 判定一个单元库能不能分发色的代码已经不存在：任何层都可以。
      expect(s.contains('if (!canDistribute'), isFalse);
    });
  });

  group('作者库归属只有两条链，不得再抄第三份', () {
    test('作者行归属零调用点的 helper 已删除', () {
      final s = codeOf('lib/main.dart');
      expect(s.contains('authorRowIdsFor'), isFalse,
          reason: '零调用点的库归属 helper 不该留');
    });

    test('bigIdFor 只经 basicIdForPath 反查（含 allBasics）', () {
      final s = codeOf('lib/main.dart');
      expect(
          RegExp(r'String bigIdFor\(String mediaPath\) =>\s*\n\s*basicById\(basicIdForPath\(mediaPath\)\)')
              .hasMatch(s),
          isTrue,
          reason: 'bigIdFor 不能再自己调 basicLibForMedia(basics, …)，否则跨单元库时永远空');
      // 三个同级查询必须都走同一个反查入口。
      for (final name in ['basicIdForPath', 'unitIdFor', 'bigIdFor']) {
        expect(s.contains(name), isTrue);
      }
    });

    test('LibMeta 之外的作者归属仍只有一处（作者筛选）', () {
      final s = codeOf('lib/main.dart');
      // 两个页面的 `_matches` 都靠 meta 的三个查询，不自己拼路径。
      //
      // 0.9.317：排行榜那处 `bigIdFor` 调用**必须**消失——它把注册库 id 当
      // 历史分组 id 比，两个命名空间永不相等（点「某库」一条都看不到）。
      // 所以这里从「≥3」收紧成「正好这两处」。
      expect(RegExp(r"\.bigIdFor\(").allMatches(s).length, 2);
      // 0.9.350：`labelFor`/`idFor` 不再各自调 `basicLibForMedia`（那条只认
      // 目录前缀，库作用域写法 `lib-015/...` 认不出），统一走
      // `basicIdForPath`（含 `lib-\\d+` 前缀处理）。所以这里断言的是
      // 「路径反查唯一出口」，而不是「某个具体函数名还在」。
      expect(s.contains('basicIdForMedia(basics, mediaPath)'), isTrue,
          reason: '路径反查仍在（basicIdForPath 内部）');
      expect(s.contains('String idFor(String mediaPath) => basicIdForPath'),
          isTrue,
          reason: 'idFor 必须与 basicIdForPath 同一条链');
    });
  });

  group('单元库爬虫页只留一行真实路径', () {
    test('不再同时显示相对路径与绝对路径两行', () {
      final s = codeOf('lib/unit_crawler_page.dart');
      expect(s.contains('单元库：\${widget.unit.rel}'), isFalse,
          reason: '相对路径与绝对路径说的是同一件事的两种坐标');
      expect(s.contains("ValueKey('unit-crawler-path')"), isTrue);
    });

    test('标题仍带单元库名（作用域不丢）', () {
      final s = codeOf('lib/unit_crawler_page.dart');
      expect(
          s.contains("'爬虫配置 · \${LibraryBadge.stripIndex(widget.unit.name)}'"),
          isTrue);
    });
  });

  group('删除规则后仍能按结构着色（真实数据路径）', () {
    setUp(() {
      LibraryBadge.custom.clear();
      LibraryBadge.topCustom.clear();
      LibraryBadge.basicCustom.clear();
      LibraryBadge.topOfUnit.clear();
      LibraryBadge.parentOfUnit.clear();
    });

    test('没有结构表时不会把任何层判成「不参与分发」', () {
      // 旧实现靠 canDistribute 在结构未加载时返回 true 来兜底；
      // 现在根本没有这个判定，直接按继承链走。
      LibraryBadge.custom['A'] = 0xFF123456;
      expect(LibraryBadge.colorForUnit('A'), 0xFF123456);
    });
  });

  group('一个媒体库在界面上只有一个名字', () {
    test('libraryDisplayName 是「规范化 + 去序号」的唯一出口', () {
      final names = File('lib/lib_names.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(names.contains('String libraryDisplayName('), isTrue);
      expect(names.contains('LibraryBadge.stripIndex(displayLibraryName('), isTrue);
    });

    test('页面不再自己拼 stripIndex(displayLibraryName(...))', () {
      // 同一个组合写法散在页面里，就是「同一个库在两页两个名字」的来源：
      // 网络设置那页只调 displayLibraryName、爬虫设置那页套了 stripIndex。
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main.contains('LibraryBadge.stripIndex(displayLibraryName'),
          isFalse,
          reason: '页面不要自己组合这两个函数；用 libraryDisplayName');
      expect(main.contains('libraryDisplayName('), isTrue);
    });

    test('爬虫配置页与维护页的标题都带库名（名字走同一出口）', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main.contains("'爬虫配置 · '"), isTrue);
      expect(main.contains("'维护 · '"), isTrue);
      // 两处标题里都不再直接贴 `widget.lib['name']`。
      expect(main.contains("Text('爬虫配置 · \${widget.lib['name']}')"), isFalse);
      expect(main.contains("Text('维护 · \${widget.lib['name']}')"), isFalse);
    });

    test('库列表归一化不剥序号（渲染时才剥）', () {
      // 剥了序号的名字与其它来源（同步源、作者挂载）比对时会对不上。
      final names = File('lib/lib_names.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(names.contains("'name': displayLibraryName("), isTrue);
      expect(names.contains("'name': libraryDisplayName("), isFalse);
    });
  });
}
