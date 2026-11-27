/// 第八十七批契约（0.9.323）：
///  1. **元数据读取的「哪台服务器」由猜改成显式参数**——`LibMeta.load(lib)`
///     一律走 `cfg.u` / `cfg.headersFor` / `cfg.baseFor`（绑定表），而绑定表
///     只在首页聚合库列表时建立：从设置页直接进入时是空的，第二台服务端的
///     库 id 就被拿去请求默认服务器。现在 `MetaSource` 显式带连接。
///  2. **元数据缓存键要带连接**——两台服务端各有一个 `lib-1` 时只按 `lib`
///     做键，后到的一份会把先到的一份顶掉。
///  3. **作废一个库要清掉它在所有连接上的副本**，不能只清默认那一份。
///  4. **页面级 `http.Client` 必须与页面同寿命**——此前
///     `widget.client ?? http.Client()` 是每个请求各建一个、从不关闭。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/meta_source.dart';
import 'package:shoucangjia/server_origin.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _body(String src, String start, String end) {
  final a = src.indexOf(start);
  final b = a < 0 ? -1 : src.indexOf(end, a);
  if (a < 0 || b <= a) throw StateError('片段定位失败：$start → $end');
  return src.substring(a, b);
}

void main() {
  group('MetaSource：来源显式化', () {
    test('未指定来源时一切回落到调用方（旧行为不变）', () {
      const s = MetaSource.none;
      expect(s.isEmpty, isTrue);
      expect(s.isScoped, isFalse);
      expect(s.apiUri('lib-1', '/api/x'), isNull);
      expect(s.headers(), isNull);
    });

    test('指定来源时地址按该 base 拼、鉴权用该连接的账号', () {
      const s = MetaSource(
          serverId: 's2', base: 'http://10.0.0.2:8090', user: 'u2', pass: 'p2');
      final uri = s.apiUri('lib-1', '/api/libraries')!;
      expect(uri.toString(), 'http://10.0.0.2:8090/api/libraries?lib=lib-1');
      expect(s.headers()!['Authorization'], startsWith('Basic '));
    });

    test('空地址视为未指定（不能拿空串去拼请求）', () {
      const s = MetaSource(serverId: 's2', base: '   ', user: 'u', pass: 'p');
      expect(s.isEmpty, isTrue);
      expect(s.apiUri('lib-1', '/api/x'), isNull);
      expect(s.headers(), isNull);
    });

    test('显式 headerOverride 优先于账号密码', () {
      final s = MetaSource.ofBase(
          'http://a:8090', const {'Authorization': 'Basic XXX'});
      expect(s.headers()!['Authorization'], 'Basic XXX');
    });

    test('从记录构造：五个来源字段一次性读对', () {
      final record = withServerOrigin(<String, dynamic>{'id': 'lib-1'},
          id: 's2', base: 'http://b:8090', label: 'B', user: 'ub', pass: 'pb');
      final s = MetaSource.ofOrigin(record);
      expect(s.serverId, 's2');
      expect(s.base, 'http://b:8090');
      expect(s.user, 'ub');
      expect(s.pass, 'pb');
    });

    test('无来源字段的记录 → none（不编造连接）', () {
      expect(MetaSource.ofOrigin(<String, dynamic>{'id': 'lib-1'}).isEmpty,
          isTrue);
      expect(MetaSource.ofOrigin(null).isEmpty, isTrue);
    });
  });

  group('元数据缓存键：视图带连接', () {
    test('未指定来源时就是库 id（与旧缓存键逐字相同）', () {
      expect(metaCacheKey('lib-1', MetaSource.none), 'lib-1');
      expect(metaCacheKey('  lib-1  ', MetaSource.none), 'lib-1');
    });

    test('两台服务端的同名库得到两个键（互不覆盖）', () {
      const a = MetaSource(serverId: 's1', base: 'http://a:8090');
      const b = MetaSource(serverId: 's2', base: 'http://b:8090');
      expect(metaCacheKey('lib-1', a), isNot(metaCacheKey('lib-1', b)));
      expect(metaCacheKey('lib-1', a), startsWith('lib-1'));
    });

    test('有地址无 id 时用地址做作用域（仍不允许跨服务器共用）', () {
      const s = MetaSource(base: 'http://a:8090');
      expect(metaCacheKey('lib-1', s), contains('http://a:8090'));
      expect(metaCacheKey('lib-1', s), isNot('lib-1'));
    });

    test('键不会因为库 id 带分隔符而与另一个库的键相撞', () {
      const s1 = MetaSource(serverId: 'a', base: 'http://a');
      const s2 = MetaSource(serverId: 'b', base: 'http://b');
      expect(metaCacheKey('x', s1), isNot(metaCacheKey('x\u0001a', s2)));
    });
  });

  group('作废：按库清掉全部连接的副本', () {
    test('metaKeyIsFor 认得裸键与带连接键，不误伤前缀相近的另一个库', () {
      expect(metaKeyIsFor('lib-1', 'lib-1'), isTrue);
      expect(metaKeyIsFor('lib-1\u0001s1', 'lib-1'), isTrue);
      expect(metaKeyIsFor('lib-10', 'lib-1'), isFalse);
      expect(metaKeyIsFor('lib-10\u0001s1', 'lib-1'), isFalse);
      expect(metaKeyIsFor('lib-1', ''), isFalse);
    });

    test('LibMeta.invalidate 三张表都按 metaKeyIsFor 清', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'static void invalidate([String? lib]) {',
          'static Future<LibMeta> load(');
      expect(body.contains('metaKeyIsFor(k, lib)'), isTrue);
      expect(body.contains('cache.remove(lib)'), isFalse,
          reason: '只清默认那一份，别的连接留着旧树');
      expect(RegExp(r'metaKeyIsFor\(k, lib\)').allMatches(body).length, 3,
          reason: 'cache / _loading / _cachedAt 三张表都要清');
    });
  });

  group('LibMeta.load：来源与缓存键', () {
    test('签名带 source，且缓存读写都用带连接的键', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'static Future<LibMeta> load(',
          'String labelFor(String mediaPath, String fallback)');
      expect(body.contains('MetaSource source = MetaSource.none'), isTrue);
      expect(body.contains('final key = metaCacheKey(lib, source);'), isTrue);
      expect(body.contains('cache[key]'), isTrue);
      expect(body.contains('_cachedAt[key] = DateTime.now();'), isTrue);
      expect(body.contains('_loading.putIfAbsent(key'), isTrue);
    });

    test('地址/鉴权/节点归属都优先取显式来源', () {
      final main = _code('lib/main.dart');
      final body = _body(main, 'static Future<LibMeta> load(',
          'String labelFor(String mediaPath, String fallback)');
      expect(body.contains('source.isScoped'), isTrue);
      expect(body.contains('libApiUrl(source.base, path, lib)'), isTrue);
      expect(body.contains('hdr ?? cfg.headersFor(lib)'), isTrue);
      expect(body.contains('serverBase: source.isScoped'), isTrue);
      expect(body.contains('serverId: source.isScoped'), isTrue);
    });
  });

  group('页面级 http.Client 与页面同寿命', () {
    test('五个项目页都不再每个请求新建客户端', () {
      for (final f in const [
        'lib/collection_sync_panel.dart',
        'lib/sync_log_panel.dart',
        'lib/unit_crawler_page.dart',
        'lib/unit_author_mount_page.dart',
        'lib/author_mount_sheet.dart',
      ]) {
        final body = _code(f);
        expect(body.contains('widget.client ?? http.Client()'), isFalse,
            reason: '$f 仍是每个请求各建一个客户端');
        expect(body.contains('_ownClient ??= http.Client()'), isTrue,
            reason: '$f 没有在页面里复用客户端');
        expect(body.contains('_ownClient?.close()'), isTrue,
            reason: '$f dispose 没有关闭自建客户端');
      }
    });
  });
}
