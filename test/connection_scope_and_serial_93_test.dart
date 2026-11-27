// 第九十三批（0.9.331）契约：三处「按库/按连接独立的数据被串成一条链」，
// 以及一处缓存键少了一层作用域。
//
// 本轮四个改动都是同一种形态：**数据彼此独立，代码却排成队**，或者
// **同一份数据在另一台服务器上不是同一份**；两边单看都「算对了」，
// 只有多连接/多库时才看出差别。
//
//  1. `_authorTypeCache` 只按 `lib` 做键：两台服务器各有一个 `lib-1`
//     （同 id 不同机器很常见）时，后写入的一份把先到的一份顶掉——第二台
//     服务器的「按类型筛选」用着第一台的 kinds，两边都是「读成功」。
//     现在键是 `<lib>\u0001<连接>`（`authorTypeCacheKey`），与 `LibMeta`
//     的 `metaCacheKey`、`unitCoverKey` 同一条规则；作废按库清**全部连接**
//     的副本，也允许只清指定连接那一份。
//
//  2. `AuthorPage.load()` 逐库 `for` + 两次 `await`（作者索引 + 作者卡，
//     各 20s 上限）：作者被合并到 N 个单元库时就是 N 次完整往返，页面
//     白等到最慢那个库。现在 `mapConcurrent(_libs, 4)`，保序所以
//     「先到先得」的 bio/av/uid/primaryLib 语义不变。收藏夹手动名单同理。
//
//  3. `runTotalRefresh` 两个阶段都是串行 `for` + `await`：N 条连接 = 2N
//     次往返（探测 6s + 库列表 12s 各一份），最慢那台离线时「总刷新」
//     要等满超时才出结果。现在两个阶段都是 4 路有界并发，`firstError`
//     仍是按连接顺序的第一条。
//
//  4. `postStat` 的 `.ignore()` 不是超时：请求会在连接池里挂到 OS 超时。
//     现在带 8s 上限（与其它读请求同一口径）。
//
// 隐私：本文件只读 `lib/` 源码文本与合成的 `s1`/`s2`/`lib-1`，不涉及任何
// 真实目录名、文件名或媒体内容。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
  group('1. 类型索引缓存按（库, 连接）存', () {
    test('缓存键带连接，未指定来源时退化为裸库 id', () {
      final main = _code('lib/main.dart');
      final body = _body(
          main,
          'String authorTypeCacheKey(String lib, String serverId) {',
          'Future<Map<String, Set<String>>> _authorTypesForLib(String lib,');
      expect(body.contains('l'), isTrue);
      expect(body.contains('sid'), isTrue);
      expect(body.contains(r'$l$kNodeKeySep$sid'), isTrue,
          reason: '分隔符必须取自 node_key（唯一拼装口）');
      expect(body.contains('return sid.isEmpty ? l :'), isTrue,
          reason: '不知道来源时不能凭空造作用域');
    });

    test('失败摘的是这枚键，不是裸库 id', () {
      final main = _code('lib/main.dart');
      final body = _body(main,
          'Map<String, Set<String>> _typesFailed(String cacheKey) {',
          'Future<Map<String, Set<String>>> _typesFromLibIndex(');
      expect(body.contains('_authorTypeCache.remove(cacheKey)'), isTrue);
      expect(body.contains('_authorTypeCache.remove(lib)'), isFalse,
          reason: '按裸库 id 摘会误删另一台服务器的成功结果');
    });

    test('按库作废清全部连接，指定连接时只清那一份', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'void clearAuthorTypeCache(String lib,',
          'bool authorTypeCacheKeyIsFor(');
      expect(body.contains('authorTypeCacheKey(l, serverId)'), isTrue);
      expect(body.contains('removeWhere((k, _) => authorTypeCacheKeyIsFor(k, l))'),
          isTrue);
      expect(body.contains('_authorTypeCache.remove(l)'), isFalse,
          reason: '只清裸键 = 另一台的旧 kinds 留到重启');
    });

    test('键归属判定同时认旧键与带作用域键', () {
      final main = _code('lib/main.dart');
      final body = _body(
          main,
          'bool authorTypeCacheKeyIsFor(String key, String lib) {',
          'typedef AuthorTypeScope');
      expect(body.contains('key == l'), isTrue);
      expect(body.contains(r"'$l$kNodeKeySep'"), isTrue);
    });

    test('loadAuthorTypes 把每条库的来源交给缓存键', () {
      final main = _code('lib/main.dart');
      final body = _body(main,
          'Future<Map<String, Set<String>>> loadAuthorTypes(Iterable<String> libs,',
          'void postStat(');
      expect(body.contains('serverIdOf'), isTrue);
      expect(body.contains('_authorTypesForLib(l, serverId:'), isTrue);
    });

    test('两个调用点都传了 serverIdOf（页面不得让缓存自己去猜）', () {
      final main = _code('lib/main.dart');
      expect('loadAuthorTypes(ids, serverIdOf: cfg.serverIdFor)'
          .allMatches(main).length, 1);
      expect('loadAuthorTypes(targets, serverIdOf: cfg.serverIdFor)'
          .allMatches(main).length, 1);
    });
  });

  group('2. 作者主页逐库取数改为有界并发', () {
    test('按 _libs 4 路并发，不再是逐库 await', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'Future<void> load() async {',
          'works = mergeAuthorWorks(perLib);');
      expect(
          RegExp(r'mapConcurrent<String, _AuthorLibFetch>\(_libs, 4,')
              .hasMatch(body),
          isTrue,
          reason: 'N 个库各 20s 上限串行 = 白等到最慢那个库');
      expect(body.contains('for (final lib in _libs)'), isFalse,
          reason: '旧形态：串行 for + 两次 await');
    });

    test('先到先得的四个字段仍按 _libs 顺序写', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'final perLib = <List<Map<String, dynamic>>>[];',
          'works = mergeAuthorWorks(perLib);');
      // mapConcurrent 保序 → 顺序遍历就是把「先到先得」写清楚。
      expect(body.contains('for (final f in fetched)'), isTrue);
      expect(body.contains('if (!f.ok) continue;'), isTrue);
      expect(body.contains('if (platformUid.isEmpty) platformUid = f.uid;'),
          isTrue);
      expect(body.contains('if (bio.isEmpty) bio = f.bio;'), isTrue);
      expect(body.contains('if (av.isEmpty) av = f.av;'), isTrue);
      expect(body.contains('if (primaryLib.isEmpty) primaryLib = f.lib;'),
          isTrue);
    });

    test('访问上报只对真的取到作品的库发', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'final perLib = <List<Map<String, dynamic>>>[];',
          'works = mergeAuthorWorks(perLib);');
      expect(body.contains("postStat('visit', widget.name, lib: f.lib)"), isTrue);
    });

    test('手动名单也走并发（逐库独立）', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'final manualParts = await mapConcurrent<String, Set<String>>(',
          'manualWorkIds = manual;');
      expect(
          RegExp(r'mapConcurrent<String, Set<String>>\(\s*manualLibs, 4,')
              .hasMatch(body),
          isTrue);
      expect(body.contains('for (final part in manualParts)'), isTrue);
    });
  });

  group('3. 总刷新两个阶段都并发', () {
    test('探测阶段 4 路并发', () {
      final src = _code('lib/refresh_all.dart');
      final body = _body(src, 'final probed = await mapConcurrent<ServerConn,',
          'final counted = await mapConcurrent<ServerConn,');
      expect(RegExp(r'mapConcurrent<ServerConn,').hasMatch(body), isTrue);
      expect(body.contains('live, 4,'), isTrue);
      expect(body.contains('for (final s in live) {\n      var code = 0;'),
          isFalse,
          reason: '旧形态：逐条连接 await');
    });

    test('库列表阶段同样并发，且只对在线连接发', () {
      final src = _code('lib/refresh_all.dart');
      final body = _body(src, 'final counted = await mapConcurrent<ServerConn,',
          'await clearCoverCache();');
      expect(body.contains('if ((codes[s.id] ?? 0) != 0) s'), isTrue);
      expect(body.contains(', 4, (s) async {'), isTrue);
    });

    test('错误文案仍是「连接名：原因」，首条错误按连接顺序', () {
      final src = _code('lib/refresh_all.dart');
      final body = _body(src, 'final probed = await mapConcurrent<ServerConn,',
          'final counted = await mapConcurrent<ServerConn,');
      expect(body.contains(r"'${p.title}：${p.err ?? '连接失败'}'"), isTrue);
      expect(body.contains('if (firstError == null)'), isTrue);
    });
  });

  group('4. 统计上报有上限', () {
    test('postStat 带 8 秒超时（.ignore 不是超时）', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'void postStat(String type, String author,',
          'Future<Map<String, dynamic>?> fetchDropStatus(');
      expect(body.contains('.timeout(const Duration(seconds: 8))'), isTrue);
      expect(body.contains('.ignore()'), isTrue,
          reason: '仍然不关心结果，只是不再无限挂起');
    });
  });
}
