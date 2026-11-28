import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0.9.325 第八十九批：
///
/// 1. **搜索页按库路由地址、却用当前库的账号** —— `_libWorks` 里
///    `cfg.u(..., lib: lib)` 配 `cfg.headers`。搜索范围切到另一台服务器上的库时，
///    请求打到 B 却带 A 的密码：全部 401，界面显示「这个库一条作品都没有」
///    （空列表与真的没有作品长得一模一样）。
/// 2. **类型索引的失败结果被永久缓存** —— `_authorTypeCache` 是进程级、无 TTL，
///    一次超时/401 也被当成「这个库的作者都没有类型」写进表里，于是
///    「按类型筛选」直到重启 App 之前都是空结果。
/// 3. **同步源保存没有超时** —— `_client.post` 是唯一走注入客户端的写请求，
///    0.9.324 的统一扫描只认 `http.post`，漏了它；断网时界面永远停在「保存中…」。
///
/// 只用合成 id / 地址，不涉任何真实目录或媒体内容。
// 行尾归一：Windows CI 检出的是 CRLF，而下面 `_body` 的锚点里有 `\n`
// 字面量（例如 '@override\n  Widget build(...)'）——不归一就永远 indexOf
// 不到，本地 LF 绿、Windows 红。产品代码无关。
String _code(String p) =>
    File(p).readAsStringSync().replaceAll('\r\n', '\n');

String _body(String src, String startMark, String endMark) {
  final s = src.indexOf(startMark);
  final e = src.indexOf(endMark, s);
  expect(s, greaterThanOrEqualTo(0), reason: '找不到起点：$startMark');
  expect(e, greaterThan(s), reason: '找不到终点：$endMark');
  return src.substring(s, e);
}

void main() {
  group('1. 搜索页作品请求：地址与账号同一个 lib', () {
    test('_libWorks 用 headersFor(lib)，不再用当前库的 cfg.headers', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'Future<List<dynamic>> _libWorks(',
          '// ---- J11：作者筛选');
      expect(body.contains("lib: lib"), isTrue,
          reason: '地址按 lib 路由是既有约定');
      expect(body.contains('headers: cfg.headersFor(lib)'), isTrue,
          reason: '地址按 B 路由、账号却是 A 的 → 401 → 空列表');
      expect(body.contains('headers: cfg.headers)'), isFalse,
          reason: 'cfg.headers 是当前库那条连接的账号');
    });

    test('搜索页每条作品的来源标记仍按请求时的 lib 写入', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'Future<void> loadAll() async {',
          '/// 分页拉取一个基础库的全部作品');
      expect(body.contains("'_lib': j.lib"), isTrue,
          reason: '来源标记与请求地址必须同一个 lib');
    });
  });

  group('2. 类型索引缓存：只有成功才进缓存', () {
    test('四种读失败都走 _typesFailed（摘掉缓存条目）', () {
      final main = _code('lib/main.dart');
      final body = _body(main,
          'Future<Map<String, Set<String>>> _authorTypesForLib(String lib,',
          '/// 读失败：把这条缓存摘掉再返回空表。');
      // 0.9.324 起缓存键带 serverId，参数名从 lib 改成 key；
      // 四条失败分支仍必须走同一个出口。
      expect('_typesFailed(key)'.allMatches(body).length, 4,
          reason: '注册表非 200 / 索引非 200 / base 为空或载荷非法 / 抛异常');
      expect(body.contains('return <String, Set<String>>{};'), isFalse,
          reason: '空表直接返回就等价于「缓存一个失败结果」');
    });

    test('_typesFailed 真的从表里摘掉条目', () {
      final main = _code('lib/main.dart');
      final body = _body(
          main, 'Map<String, Set<String>> _typesFailed(String cacheKey) {',
          'Future<Map<String, Set<String>>> _typesFromLibIndex(');
      expect(body.contains('_authorTypeCache.remove(cacheKey)'), isTrue);
      expect(body.contains('return <String, Set<String>>{};'), isTrue,
          reason: '摘掉之后给调用方一张空表，本次筛选照常进行');
    });

    test('契约：这个函数里不得再出现裸的空表返回', () {
      final main = _code('lib/main.dart');
      // 只看 `_authorTypesForLib` 自身；它后面紧跟 `_typesFailed` 的定义
      // （空表返回本来就该在那里出现一次）。
      final body = _body(main,
          'Future<Map<String, Set<String>>> _authorTypesForLib(String lib,',
          '/// 读失败：把这条缓存摘掉再返回空表。');
      expect(body.contains('return <String, Set<String>>{};'), isFalse,
          reason: '业务分支自己返回空表 = 失败又被缓存一次');
      expect('_typesFailed(key)'.allMatches(body).length, 4,
          reason: '四条失败分支都必须走统一出口');
    });

    test('_typesFailed 之外没有第二处「空表 + 摘缓存」实现', () {
      final main = _code('lib/main.dart');
      final all = _body(main,
          'final Map<String, Future<Map<String, Set<String>>>> _authorTypeCache',
          '/// [libs] 的每一条各自属于哪台连接');
      // `_typesFailed` 自己一处 + `_typesFromLibIndex` 的两处（单库索引失败，
      // 那里没有缓存条目可摘，只是本次跳过该库）。
      expect('return <String, Set<String>>{};'.allMatches(all).length, 3,
          reason: '业务分支自己返回空表 = 失败又被缓存一次');
    });
  });

  group('3. 走注入客户端的写请求也有超时', () {
    test('collection_sync_panel._save 的 POST 带 timeout', () {
      final src = _code('lib/collection_sync_panel.dart');
      final save = src.substring(src.indexOf('Future<void> _save() async {'));
      expect(save.contains('_client'), isTrue);
      expect(save.contains('.timeout(const Duration(seconds: 15))'), isTrue,
          reason: '断网时这个 POST 永不返回，界面停在「保存中…」');
    });

    test('lib/ 内所有 _client 请求都有超时', () {
      final missing = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync().replaceAll('\r\n', '\n');
        for (final m in RegExp(r'_client\s*\.\s*(get|post|put|delete)\s*\(')
            .allMatches(src)) {
          final end = src.indexOf(';', m.start);
          final seg = src.substring(m.start, end < 0 ? src.length : end);
          if (seg.contains('.timeout')) continue;
          final line = src.substring(0, m.start).split('\n').length;
          missing.add('${f.path}:$line');
        }
      }
      expect(missing, isEmpty, reason: '这些请求没有上限：\n${missing.join('\n')}');
    });
  });

  group('4. 注册新库：地址与账号取同一条连接', () {
    test('_add 的鉴权头来自激活连接，不再用当前库的 cfg.headers', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'Future<void> _add() async {',
          '@override\n  Widget build(BuildContext context) {\n    if (widget.embedded)');
      expect(body.contains('basicAuthHeader(at.user, at.pass)'), isTrue,
          reason: '地址取激活连接、账号却取当前库 → 拿 A 的密码敲 B 的门');
      expect(body.contains("{...cfg.headers, 'Content-Type': 'application/json'}"),
          isFalse,
          reason: 'cfg.headers 是当前库那条连接的账号');
    });

    test('注册库是服务器级动作：不再附带 lib 查询参数', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'Future<void> _add() async {',
          "showToast(this, '媒体库已添加')");
      expect(body.contains("_u('/api/libraries', '', atBase)"), isTrue,
          reason: '空 lib 表示「不带 lib=」，由该服务器自己决定');
      expect(body.contains("_u('/api/libraries', null, atBase)"), isFalse,
          reason: 'null 会回落成当前库 id，把服务器级请求绑到某个库上');
    });
  });
}
