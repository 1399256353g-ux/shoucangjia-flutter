import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0.9.319 第八十四批：
///
/// 1. **地址按 `lib` 路由、鉴权头却按「当前库」取** —— 同一族缺陷的最后一处。
///    `cfg.u(path, lib: X)` 拼的是 X 那台服务器的地址，而 `cfg.headers` 是
///    **当前库**那条连接的账号：从另一个服务端的库进来时就是拿 A 的密码敲
///    B 的门（401），整棵库树/作者索引退回空，界面只显示「没有数据」。
/// 2. **各库排行串行 wait**：N 个库 N 次往返（各 8s 超时），库多时页面等十几秒。
///    这些请求彼此独立，改有界并发（`concurrency.mapConcurrent`）。
String _code(String path) => File(path).readAsStringSync();

/// 「按当前库取头」的字面出现次数：`cfg.headers` **后面不能紧跟 `For`**，
/// 否则 `cfg.headersFor(lib)` 也会被算成一次。
int _currentLibHeaderUses(String body) =>
    RegExp(r'cfg\.headers(?!For)').allMatches(body).length;

/// 去掉整行注释，避免「注释里提到 cfg.headers」被误判。
String _codeNoComments(String path) => _code(path)
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('地址与鉴权头必须同源（同一个 lib）', () {
    final main = _codeNoComments('lib/main.dart');

    test('LibMeta.load 四条请求都按 lib 取鉴权头', () {
      final start = main.indexOf('static Future<LibMeta> load(');
      final end = main.indexOf('String labelFor(String mediaPath', start);
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final body = main.substring(start, end);
      expect(_currentLibHeaderUses(body), 0,
          reason: 'cfg.headers 是当前库那条连接的账号，按 lib 取才对');
      // 0.9.323：四条请求的头从「各自写 `cfg.headersFor(lib)`」收成一个
      // `h()`——有显式来源（`MetaSource`）时用那条连接的账号，否则回落
      // `cfg.headersFor(lib)`。判定改成「唯一出口 + 四条都用它 + 回落分支
      // 仍按 lib」，比数 `cfg.headersFor(lib)` 的出现次数更贴近真实约束
      // （旧写法再多写两遍也只是重复）。
      expect(body.contains('cfg.headersFor(lib)'), isTrue,
          reason: '没有显式来源时必须按 lib 取头');
      expect('headers: h()'.allMatches(body).length, 4,
          reason: 'libraries.json / libraries / author_stats / nodes 四条都要走同一出口');
    });

    test('作者类型索引（libraries.json + lib/<id>/index.json）按 lib 取头', () {
      final start = main.indexOf('Future<Map<String, Set<String>>> _authorTypesForLib(');
      final end = main.indexOf('Future<Map<String, Set<String>>> loadAuthorTypes(', start);
      final body = main.substring(start, end);
      expect(_currentLibHeaderUses(body), 0);
      expect('cfg.headersFor(lib)'.allMatches(body).length,
          greaterThanOrEqualTo(3));
    });

    test('作者主页多库循环、单作品请求都按各自的 lib 取头', () {
      // 0.9.331 起每库请求改成有界并发：请求发生在 `fetched` 的
      // `mapConcurrent` 闭包里，`perLib` 只做汇总、不再发请求。
      // 因此断言必须盯**发请求那一段**，而不是汇总段。
      final start = main.indexOf(
          'final fetched = await mapConcurrent<String, _AuthorLibFetch>(');
      expect(start, greaterThan(0), reason: '找不到作者页多库取数块');
      final end = main.indexOf(
          'final perLib = <List<Map<String, dynamic>>>[];', start);
      expect(end, greaterThan(start), reason: '找不到取数块结尾');
      final body = main.substring(start, end);
      expect(_currentLibHeaderUses(body), 0,
          reason: '跨库循环里用当前库的账号会 401');
      expect('cfg.headersFor(lib)'.allMatches(body).length,
          greaterThanOrEqualTo(2));

      final fallback = main.indexOf('Future<void> _fetchFallbackAvatar(');
      final fbEnd = main.indexOf('Future<void> _open(String name)', fallback);
      expect(main.substring(fallback, fbEnd).contains('cfg.headersFor(lib)'),
          isTrue);
    });

    test('小水滴与统计上报同样按 lib 取头', () {
      final drops = main.indexOf('Future<Map<String, dynamic>?> fetchDropStatus(');
      expect(main.substring(drops, drops + 600).contains('cfg.headersFor(lib)'),
          isTrue);

      final stat = main.indexOf('void postStat(String type, String author,');
      final statEnd = main.indexOf('Future<Map<String, dynamic>?> fetchDropStatus(', stat);
      final body = main.substring(stat, statEnd);
      expect(body.contains('cfg.headersFor(lib)'), isTrue);
      expect(_currentLibHeaderUses(body), 0);
    });
  });

  group('各库排行的统计取数不串行', () {
    test('按库并发取 author_stats（有界），离线计数仍然正确', () {
      final main = _codeNoComments('lib/main.dart');
      final start = main.indexOf('class _LibraryRankPageState');
      final end = main.indexOf('class AuthorGridCard', start);
      expect(start, greaterThan(0));
      final body = main.substring(start, end);
      expect(body.contains('mapConcurrent<String, Map<String, dynamic>?>'),
          isTrue, reason: '每个库的统计彼此独立，串行 await 会累积等待');
      expect(body.contains('cfg.headersFor(id)'), isTrue,
          reason: '并发取数同样要按各自的库取鉴权头');
      expect(body.contains('offline++'), isTrue);
      // 不再有「循环体里 await 取数」这种串行形态：请求必须先进并发入口。
      // 并发入口之前只允许出现 `await http.get(.../api/libraries)` 这一次
      // 元数据请求（它本来就只有一次），不得出现按库循环的 await 取数。
      final loopStart =
          body.indexOf('await mapConcurrent<String, Map<String, dynamic>?>');
      expect(loopStart, greaterThan(0));
      final beforeLoop = body.substring(0, loopStart);
      // 只禁止**带块的**循环（`for (...) { ... await ... }` 那种串行取数）；
      // 列表推导里的 `for (final lib in list)` 只是构造 id 列表，不是请求。
      expect(RegExp(r'for \(final lib in list\) \{').hasMatch(beforeLoop),
          isFalse,
          reason: '串行循环取数已改为并发');
      expect('await http'.allMatches(beforeLoop).length, lessThanOrEqualTo(1),
          reason: '并发入口之前只该有库列表那一次请求');
    });
  });
}
