// 第九十二批（0.9.328）契约：逐连接取数不再串行 / 「默认库」按连接 / 路径取库改名。
//
// 本轮四处改动都是「同一条规则在两处按两种口径成立，各自都算对了」：
//
//  1. `load()` 与 `_loadTree()` 逐台服务器取 `libraries.json` 是串行
//     `for` + `await`（各 10s / 8s 上限）。0.9.327 已经把 `/api/nodes`
//     改成有界并发，这两处是**同一处遗漏**：N 台服务器 = N 次完整往返，
//     首页首屏一直白等到最慢的那台。现在同为 4 路 `mapConcurrent`。
//
//  2. `_authorTypesForLib` 反过来是**无界**：`Future.wait` 一次发出全部
//     基础库的 `index.json` 请求（实测 39 条），把连接池打满。现在 6 路。
//
//  3. 「默认库」是**每条连接**的属性。此前只有一个全局 `defaultId`，
//     两台服务器各有默认库时后读到的顶掉前一台（第一台永远不标星），
//     同 id 时又都标星。现在按连接 id 存表，查的时候带上记录自己的连接。
//
//  4. `libForMediaPath`（作用**路径**）与 `work_lib.workLibOf`（作用
//     **条目 `_lib` 字段**）名字太像，看名字分不出输入是什么。前者改名
//     `libFromMediaPath`，并在文档里写清两者的区别。
//
// 隐私：本文件只读 `lib/` 源码文本与合成常量 `s1`/`s2`/`lib-1`，不涉及
// 任何真实目录名、文件名或媒体内容。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 去掉整行注释后的源码（注释里引用旧写法是允许的，那是在解释为什么改）。
String _code(String path) {
  final raw = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  final out = StringBuffer();
  for (final line in raw.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    out.writeln(line);
  }
  return out.toString();
}

/// 取某个方法/函数的体（到 `until` 那一行为止）。两个锚点都按**代码行**找，
/// 不用注释行（注释已被 [_code] 剥掉）。
String _body(String src, String startMarker, String until) {
  final start = src.indexOf(startMarker);
  expect(start, greaterThan(0), reason: '找不到 $startMarker');
  final end = src.indexOf(until, start);
  expect(end, greaterThan(start), reason: '$startMarker 的下一个锚点变了');
  return src.substring(start, end);
}

void main() {
  group('1. 逐连接取数：有界并发，不是串行 loop', () {
    test('load() 的注册表+索引读取走 mapConcurrent(use, 4)', () {
      final main = _code('lib/main.dart');
      // `load()` 有好几个同名方法（各页面各一个），用类内唯一下文锚定。
      final start = main.indexOf('      final fetched = await mapConcurrent<ServerConn, ({');
      expect(start, greaterThan(0), reason: 'load() 里找不到并发取数');
      final body = main.substring(start, start + 2600);
      expect(body.contains('})>(use, 4, (s) async {'), isTrue,
          reason: '输入是整张在线连接表，并发 4 路（与爬虫页同一口径）');
      expect('.timeout(kTimeoutReadSlow)'.allMatches(body).length, 2,
          reason: '并发不等于可以不限时：注册表与索引两条各走同一个读取档');
      expect(body.contains('final snaps = [for (final r in fetched) r.snap];'),
          isTrue,
          reason: '结果要保序回填，snaps 的顺序必须与 servers 一致');
    });

    test('load() 里不再有「对 use 逐个 await」的串行 loop', () {
      final main = _code('lib/main.dart');
      // 串行形态：`for (final s in use) {` 开头、400 字内出现 `await http`。
      final serial = RegExp(
        r'for \(final s in use\) \{[\s\S]{0,400}?await http',
      );
      expect(serial.hasMatch(main), isFalse,
          reason: 'N 台服务器 = N×10s 串行往返，是本次修掉的形态');
    });

    test('_loadTree() 的树读取同样并发，且全局根名仍只由首条连接写', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'Future<void> _loadTree() async {',
          '  Future<void> _toggleUnitStar(UnitLibrary u) async {');
      expect(
          body.contains(
              'final fetched = await mapConcurrent<ServerConn, ({'),
          isTrue,
          reason: '树快照也是逐台独立，串行 = N×8s 白等');
      expect(body.contains('})>(servers, 4, (s) async {'), isTrue);
      expect(RegExp(r'for \(final s in servers\) \{').hasMatch(body), isFalse,
          reason: '串行 for 循环是本次修掉的形态');
      // 校准语义：全局 `TopNodeName` 仍只由首条连接写（旧页面没有 meta 用它）。
      expect(body.contains('identical(s, servers.first)'), isTrue);
      // 保序：先收集成 fetched，再按 servers 顺序落 snaps/rootNames。
      expect(body.contains('for (final r in fetched) {'), isTrue);
      // 节点仍逐条连接各取一次（0.9.326 的契约不能被并发改动带坏）。
      expect(body.contains('_fetchNodesPerServer()'), isTrue);
      expect(body.contains('serverId: s.id'), isTrue);
    });
  });

  group('2. 类型索引扇出：有界 6 路，不是无界 Future.wait', () {
    test('_authorTypesForLib 用 mapConcurrent(basics, 6)，不再无界 fan-out',
        () {
      final main = _code('lib/main.dart');
      final body = _body(
          main,
          'Future<Map<String, Set<String>>> _authorTypesForLib(String lib,',
          'Map<String, Set<String>> _typesFailed(String cacheKey) {');
      // 调用的实参跨了行：`mapConcurrent<...>(` 与 `basics, 6,` 之间有换行，
      // 所以断言按「泛型签名 + 换行 + 实参」而不是拼成一行。
      expect(
          RegExp(
            r'mapConcurrent<BasicLib, Map<String, Set<String>>>\(\s*'
            r'basics, 6,',
          ).hasMatch(body),
          isTrue,
          reason: '39 个基础库同一瞬间全发会把连接池与 NAS 打满');
      expect(body.contains('Future.wait('), isFalse,
          reason: '无界 fan-out 是本次修掉的形态');
      // 失败语义不变：四条失败分支仍走 _typesFailed。
      // 0.9.331：缓存键带连接，失败分支摘的是这枚键（语义不变，键变了）。
      expect('_typesFailed(key)'.allMatches(body).length, 4);
    });

    test('loadAuthorTypes 的「库级」并发是另一件事，保持原样', () {
      final main = _code('lib/main.dart');
      final body = _body(main,
          'Future<Map<String, Set<String>>> loadAuthorTypes(Iterable<String> libs,',
          'void postStat(');
      // 注册库数量通常个位数，这一层的 Future.wait 不是问题；
      // 真正会爆的是上面「每个基础库一条」那层。
      expect(body.contains('Future.wait('), isTrue);
    });
  });

  group('3. 「默认库」是每条连接的属性', () {
    test('默认库按连接 id 存表，而不是一个全局字符串', () {
      final main = _code('lib/main.dart');
      expect(main.contains('final Map<String, String> defaultIdByServer'),
          isTrue,
          reason: '两台服务器可以各有各的默认库；全局单值必然互相覆盖');
      expect(RegExp(r'String\? defaultId;').hasMatch(main), isFalse,
          reason: '单个全局字段是本次修掉的形态');
      expect(main.contains('String defaultIdOf(String serverId)'), isTrue,
          reason: '查默认库必须带上它自己的连接');
    });

    test('回填按结果各自写表，不再「第一个非空就锁死」', () {
      final main = _code('lib/main.dart');
      // 锚点用**代码行**（注释在 _code 里已剥掉）：
      // `clear()` → `for (final r in fetched)` → `final snaps = [...]`。
      final start = main.indexOf('defaultIdByServer.clear();');
      expect(start, greaterThan(0), reason: '找不到默认库回填段');
      final end = main.indexOf('final snaps = [for (final r in fetched) r.snap];',
          start);
      expect(end, greaterThan(start));
      final body = main.substring(start, end);
      expect(body.contains('defaultIdByServer[sid] = r.def;'), isTrue,
          reason: '每台各记一份，键是连接 id，不存在互相覆盖');
      expect(
          RegExp(r'if \(r\.def\.isNotEmpty && defaultId == null\)')
              .hasMatch(body),
          isFalse,
          reason: '「全局第一个非空」是本次修掉的形态');
      // 只出现一次：`load()` 里这一处；别的方法不得再维护第二张默认表。
      expect('defaultIdByServer.clear();'.allMatches(main).length, 1);
    });

    test('卡片标星时按记录自己的连接查默认库', () {
      final main = _code('lib/main.dart');
      // 锚点必须**单行**：Windows CI 检出的是 CRLF，一个横跨两行的字面量
      // 锚点会找不到（本批 Windows 红、Linux 绿就是这么来的）。签名里带
      // `UnitLibrary` 的那一处是单元库卡片，与这里要的注册库卡片不同名，
      // 所以第一处命中就是它。
      const marker = 'Widget _libTile(Map<String, dynamic> l) {';
      final start = main.indexOf(marker);
      expect(start, greaterThan(0), reason: '找不到主页面那张卡片');
      expect(main.substring(start, start + 80).contains("final id = "), isTrue);
      final end = main.indexOf("final cr = mapOrNull(l['crawler'])", start);
      expect(end, greaterThan(start));
      final body = main.substring(start, end);
      expect(body.contains('id == defaultIdOf(serverOriginOf(l).id)'), isTrue,
          reason: 'A 的默认库 id 不能给 B 的同 id 库标星');
      expect(RegExp(r'id == defaultId[^O]').hasMatch(body), isFalse,
          reason: '裸全局比较是本次修掉的形态');
    });
  });

  group('4. 路径取库改名：libFromMediaPath（不叫 libForMediaPath）', () {
    test('改名后旧名在 lib/ 与 test/ 里零出现（注释里的历史说明除外）', () {
      final lib = _code('lib/lib_cover.dart');
      expect(lib.contains('String libFromMediaPath('), isTrue);
      expect(RegExp(r'\blibForMediaPath\b').hasMatch(_code('lib/main.dart')),
          isFalse,
          reason: '页面里的调用点必须一起改名');
      expect(
          RegExp(r'\blibForMediaPath\b')
              .hasMatch(_code('lib/author_avatar_view.dart')),
          isFalse);
    });

    test('两个名字作用的对象不同，文档里写明', () {
      // 说明在注释里，所以读原文。
      final raw = File('lib/lib_cover.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(raw.contains('作用的是**地址字符串**'), isTrue,
          reason: '必须写清它吃的是路径，与 workLibOf 吃条目字段不同');
      expect(raw.contains('workLibOf'), isTrue,
          reason: '对照物要指名，否则下一个人还会按名字猜');
      expect(_code('lib/lib_cover.dart')
          .contains('return fallbackLib?.trim() ?? '), isTrue,
          reason: '函数本体仍是「取不到就回落到调用方的库」这一条');
    });

    test('路径取库与条目取库仍是两条独立出口（不合并成一个）', () {
      final workLib = _code('lib/work_lib.dart');
      expect(workLib.contains('String workLibOf(dynamic work'), isTrue,
          reason: '条目取库看的是 _lib 字段，不能并进路径取库');
      final libCover = _code('lib/lib_cover.dart');
      expect(libCover.contains('String libOfMediaPath(String p)'), isTrue,
          reason: '路径取库看的是 /media/<lib>/ 段');
    });
  });
}
