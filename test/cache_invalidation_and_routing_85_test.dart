import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0.9.321 第八十五批（项 2 / 项 3）：
///
/// **项 2 · 缓存只有写入、没有失效**：`LibMeta.cache`（TTL 5 分钟）与
/// `_authorTypeCache`（进程级，无 TTL）都只有 `putIfAbsent`。卡片「快速刷新」
/// 重建了 `lib/<id>/index.json` 与单元库节点，缓存却原样留着——刷新按钮报
/// 「已刷新 · N 个作品」，筛选面板与单元库树还是旧数据，直到重启 App。
///
/// **项 3 · 地址按 lib 路由、鉴权头/节点归属却按当前库**：
/// `startServerSync` / `sendDrop` 用 `cfg.u(..., lib: lib)` 拼地址，头却取
/// `cfg.headers`（当前库的账号）；`LibMeta.load` 建节点时写 `cfg.base` /
/// `cfg.serverIdFor(cfg.lib)`，而这条请求是按 `lib` 发的。跨连接时同步与
/// 小水滴记到别人的服务器上，节点卡片拿着错的 base 去挂载/取封面。
String _codeNoComments(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// `cfg.headers` 后不能紧跟 `For`，否则 `cfg.headersFor(...)` 也被算进来。
int _currentLibHeaderUses(String body) =>
    RegExp(r'cfg\.headers(?!For)').allMatches(body).length;

String _body(String src, String start, String end) {
  final a = src.indexOf(start);
  final b = src.indexOf(end, a);
  expect(a, greaterThan(0), reason: '找不到起点：$start');
  expect(b, greaterThan(a), reason: '找不到终点：$end');
  return src.substring(a, b);
}

void main() {
  final main = _codeNoComments('lib/main.dart');

  group('地址与鉴权头同源（同步 / 小水滴 / 节点归属）', () {
    test('startServerSync 按 lib 取头', () {
      final body = _body(main, 'Future<Map<String, dynamic>?> startServerSync(',
          'Future<Map<String, dynamic>?> serverSyncStatus(');
      expect(_currentLibHeaderUses(body), 0,
          reason: '同步请求打到 B，凭据却是 A 的 → 401 或记到错的服务端');
      expect(body.contains('cfg.headersFor(lib)'), isTrue);
    });

    test('sendDrop 按 lib 取头', () {
      final body = _body(main, 'Future<Map<String, dynamic>?> sendDrop(',
          'Set<String> toggleWorkSelection(');
      expect(_currentLibHeaderUses(body), 0,
          reason: '小水滴要记在作品所属服务器上');
      expect(body.contains('cfg.headersFor(lib)'), isTrue);
    });

    test('LibMeta 建节点时连接字段也按 lib 取', () {
      final body = _body(main, 'static Future<LibMeta> load(',
          'String labelFor(String mediaPath');
      expect(body.contains('serverBase: cfg.base,'), isFalse,
          reason: '节点 base 用了当前库的服务器');
      expect(body.contains('serverId: cfg.serverIdFor(cfg.lib)'), isFalse,
          reason: '节点归属用了当前库的连接 id');
      // 0.9.323：节点归属改成「有显式来源就用来源连接的 base/id」，
      // 没来源时才回落 `cfg.baseFor(lib)`——两条分支都必须按同一个 lib，
      // 不能有一支写 `cfg.base`（当前库）。
      expect(body.contains('serverBase: source.isScoped'), isTrue);
      expect(body.contains('serverId: source.isScoped'), isTrue);
      expect(body.contains(': cfg.baseFor(lib)'), isTrue);
      expect(body.contains(': cfg.serverIdFor(lib)'), isTrue);
      expect(body.contains(': cfg.serverLabelFor(lib)'), isTrue);
    });

    test('图文作品取图按作品所属库取头', () {
      final body = _body(main, 'Widget picView(String path, {String? lib})',
          'void _setPicIndex(int v)');
      expect(_currentLibHeaderUses(body), 0,
          reason: '跨连接进入的图文会 401，界面只说「图片加载失败」');
      expect(body.contains('final imgHeaders = cfg.headersFor(lib);'), isTrue);
      expect('imgHeaders'.allMatches(body).length, greaterThanOrEqualTo(3),
          reason: 'GIF 与缓存图两条分支都要用它');
    });
  });

  group('缓存必须有失效入口（刷新一次就该看到新数据）', () {
    test('LibMeta.invalidate 三个表一起清，并可只清一个库', () {
      final body = _body(main, 'static void invalidate([String? lib])',
          'static Future<LibMeta> load(');
      expect(body.contains('cache.clear()'), isTrue);
      expect(body.contains('_cachedAt.clear()'), isTrue);
      expect(body.contains('_loading.clear()'), isTrue);
      // 0.9.323：键可能带来源连接（同一库在两台服务器各有一份元数据），
      // 「作废这个库」必须清掉**全部**副本。旧的 `cache.remove(lib)` 只清
      // 默认那一份，另一台的旧树会留到 TTL 到期。三张表都按
      // `metaKeyIsFor` 清。
      expect(RegExp(r'\w+\.removeWhere\(\(k, _\) => metaKeyIsFor\(k, lib\)\)')
          .allMatches(body).length, 3,
          reason: 'cache / _loading / _cachedAt 三张表都要按库清');
      expect(body.contains('cache.remove(lib)'), isFalse,
          reason: '只清默认那一份');
    });

    test('类型索引缓存有唯一清入口', () {
      final body = _body(main, 'void clearAuthorTypeCache(String lib,',
          'Future<Map<String, Set<String>>> loadAuthorTypes(');
      expect(body.contains('_authorTypeCache.clear()'), isTrue);
      // 0.9.331：键带连接，所以「作废这个库」按库清**全部连接**的副本
      // （`authorTypeCacheKeyIsFor`），并允许只清指定连接的那一份。
      expect(body.contains('authorTypeCacheKeyIsFor(k, l)'), isTrue,
          reason: '只清裸库 id 会留下另一台服务器那份旧 kinds');
    });

    test('快速刷新两处缓存一起作废（唯一的调用点）', () {
      final body = _body(main, 'Future<String?> _quickRefresh(',
          'Future<void> load() async {');
      expect(body.contains('clearAuthorTypeCache(id)'), isTrue,
          reason: '重建索引后类型筛选还用旧 kinds');
      expect(body.contains('LibMeta.invalidate(id)'), isTrue,
          reason: '重建索引后单元库树还用旧 meta');
    });

    test('契约：缓存表不得只剩 putIfAbsent（有写入无失效）', () {
      final src = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(RegExp(r'class LibMeta').hasMatch(src), isTrue);
      expect(src.contains('static void invalidate('), isTrue);
    });
  });
}
