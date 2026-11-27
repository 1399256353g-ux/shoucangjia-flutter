// 第九十四批（0.9.334）契约：两条「地址按 A 路由、账号却按 B」的残留，
// 以及分隔符字面量的第五、六、七、八份。
//
// 1. `AuthorPage._openAuthorMount` 把 `cfg.base`（**激活连接**的地址）
//    和 `cfg.headersFor(lib)`（**作者所属库那条连接**的账号）配在一起。
//    从另一台服务器的单元库进入作者页时，地址与账号不同源：401 或空列表，
//    而「这个作者没有任何挂载」与「请求本身发错了」在界面上长得一样。
//
// 2. `_AuthorGridPageState.loadLibs` 的 `/api/crawler` 请求地址写 `cfg.base`、
//    参数写 `cfg.lib`、账号又走 `cfg.headers`：切过连接但没切库时，请求
//    打到 A 却问着 B 的库 id，返回 200 + 空脚本表——与「真的没有脚本」
//    完全一样，卡片上的爬虫入口看起来就是坏的。
//
// 3. `\u0001` 这个分隔符字面量此前在 `node_key.dart` 之外还有五份：
//    `author_dir_filter`（作者目录筛选键）、`crawler_sections`（单元库键与
//    爬虫配置键）、`meta_source`（元数据缓存键的拼装与归属判定）。五份都是
//    肉眼分不出差别的控制字符，只有某处被改成 `\u0001 ` 之类时才炸，而那时
//    的表现是「这条筛选/配置/缓存读不出来」，每一处单看都自洽。
//    现在拼装收成 `node_key.scopedKey(a, b)`，反向判定读 `kNodeKeySep`。
//
// 隐私：本文件只读 `lib/` 源码文本，不涉及任何真实目录名、文件名或媒体内容。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_dir_filter.dart';
import 'package:shoucangjia/crawler_sections.dart';
import 'package:shoucangjia/meta_source.dart';
import 'package:shoucangjia/node_key.dart';

/// 去掉整行注释后的源码（注释里引用旧写法是在解释为什么改）。
String _code(String path) {
  final raw = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  final out = StringBuffer();
  for (final line in raw.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    out.writeln(line);
  }
  return out.toString();
}

/// 取某段源码（从 [startMark] 到 [endMark]）。
String _body(String src, String startMark, String endMark) {
  final s = src.indexOf(startMark);
  expect(s, greaterThanOrEqualTo(0), reason: '找不到起点：$startMark');
  final e = src.indexOf(endMark, s);
  expect(e, greaterThan(s), reason: '找不到终点：$endMark');
  return src.substring(s, e);
}

void main() {
  group('1. 作者挂载面板的地址与账号同源', () {
    test('地址取该库所属连接，不再写裸 cfg.base', () {
      final main = _code('lib/main.dart');
      final body = _body(
          main, 'Future<void> _openAuthorMount() async {', 'await load();');
      expect(body.contains('base: cfg.baseFor(lib)'), isTrue,
          reason: '地址必须与 headersFor(lib) 同源');
      expect(body.contains('headers: cfg.headersFor(lib)'), isTrue);
      expect(body.contains('base: cfg.base,'), isFalse,
          reason: '裸 cfg.base 是激活连接的地址，跨连接时与账号不是同一台');
    });
  });

  group('2. 爬虫入口的地址、lib 参数、账号三件同源', () {
    test('地址用 baseFor(cfg.lib)，与 lib 参数、鉴权头同一个库', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'Future<void> loadLibs() async {',
          'Future<void> load({bool quiet = false}) async {');
      expect(
          body.contains(
              "libApiUrl(\n                    cfg.baseFor(cfg.lib), '/api/crawler', cfg.lib)"),
          isTrue);
      expect(body.contains('headers: cfg.headersFor(cfg.lib)'), isTrue);
      expect(main.contains("libApiUrl(cfg.base, '/api/crawler'"), isFalse,
          reason: '裸 cfg.base 与 cfg.lib 在跨连接时不是同一台');
    });
  });

  group('3. 分隔符只有一份拼装口', () {
    test('scopedKey 输出与 nodeKey 逐字相同（分隔符同源）', () {
      expect(scopedKey('s1', 'A/B'), nodeKey('s1', 'A/B'));
      expect(scopedKey(' s1 ', ' A/B '), nodeKey('s1', 'A/B'),
          reason: '两侧各 trim 一次，与 nodeKey 口径一致');
      // 字段顺序相反也不影响「分隔符只有一份」这件事。
      expect(
          metaCacheKey('lib-1',
              const MetaSource(serverId: 's1', base: 'http://a:8090')),
          scopedKey('lib-1', 's1'));
      // 未指定来源时仍是裸库 id（旧键），不能凭空造作用域。
      expect(metaCacheKey('lib-1', MetaSource.none), 'lib-1');
    });

    test('作者目录筛选键仍带同样的分隔符', () {
      const o = AuthorDirOption(lib: 'lib-1', authorDir: '@A');
      expect(o.key, scopedKey('lib-1', '@A'));
      expect(o.key.contains(kNodeKeySep), isTrue);
    });

    test('爬虫的两枚键（单元库 rel / 注册库 id）都走同一个拼装', () {
      expect(crawlerConfigKey('s1', 'lib-1'), scopedKey('s1', 'lib-1'));
      expect(unitRelKey('s1', r'A\B'), scopedKey('s1', 'A/B'),
          reason: 'rel 归一与键拼装是同一步');
    });

    test('契约：五份字面量不得复活', () {
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final name = f.uri.pathSegments.last;
        if (name == 'node_key.dart') continue;
        // 源码里出现 `'\u0001'` 说明又手拼了一次分隔符。
        if (_code(f.path).contains(r"'\u0001'")) offenders.add(name);
      }
      expect(offenders, isEmpty, reason: '分隔符字面量又出现在: $offenders');
    });

    test('归属判定读常量，不再写第二份分隔符', () {
      final src = _code('lib/meta_source.dart');
      // 0.9.336：判定体与作者类型索引那边**逐字节相同**，已收成
      // `node_key.scopedKeyIsFor`。这里钉「只有转发」：自己再写一遍
      // `key == l || key.startsWith('$l...')` 就是第二份实现。
      final body = _body(
          src, 'bool metaKeyIsFor(String key, String lib)', '\n');
      expect(body.contains('scopedKeyIsFor(key, lib)'), isTrue,
          reason: '键归属判定只有一处实现（与类型索引同源）');
      expect(body.contains('startsWith('), isFalse,
          reason: '转发型函数里不得再写一份前缀判定');
      expect(src.contains(r"'\u0001'"), isFalse);
    });
  });

  group('4. 两个页面的筛选面板汇总不再各写一遍', () {
    test('多份 meta 汇总只有一处实现（推荐页与搜索页共用）', () {
      final main = _code('lib/main.dart');
      expect('AuthorFilterOptions authorFilterOptionsOfMetas('.allMatches(main).length,
          1);
      expect('String unitNameInMetas('.allMatches(main).length, 1);
      expect(main.contains('_optionsOf('), isFalse,
          reason: '两份字节完全相同的私有副本已收口');
      expect(main.contains('static String _unitNameIn('), isFalse);
      // 两个页面必须都走这一处，否则同一个单元库会在两页显示不同名字。
      expect(
          'authorFilterOptionsOfMetas(meta == null ? const [] : [meta!])'
              .allMatches(main)
              .length,
          1);
      expect('authorFilterOptionsOfMetas(metas.values.toList())'
          .allMatches(main).length, 1);
    });
  });
}
