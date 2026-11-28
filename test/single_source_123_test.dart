/// 0.9.378（第一百二十三批）契约：
///  1. 本机持久化的 JSON 表只有一条「读盘 → 能不能用」的判断
///     （`prefs_json.decodePrefJson`）。此前连接表 / 库绑定 / 观看进度 /
///     继续观看 / 播放量 / 头像覆盖表各写一遍 `if (raw == null || ...)
///     try { jsonDecode } catch`，空串判定一处 `isEmpty` 一处 `trim()`。
///  2. 库卡片封面预热不再自己「去重 → 查鉴权头 → 造 provider → 排队」，
///     排队只有 `thumb_prefetch.prefetchThumbItems` 一处。
///  3. 两个作者挂载入口共用一个写请求出口（地址 / Content-Type / 超时档
///     是协议的一部分，不能各抄一份）。
///  4. 播放页切条时，停靠旧槽位的 `await` 之后写状态前必须有 `mounted` 守卫。
///
/// 判据全部是源码结构与真实调用行为，不涉及任何作者名 / 文件内容。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:shoucangjia/author_avatar_store.dart';
import 'package:shoucangjia/continue_watching.dart';
import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/prefs_json.dart';
import 'package:shoucangjia/unit_author_groups.dart';
import 'package:shoucangjia/unit_author_post.dart';
import 'package:shoucangjia/watch_progress.dart';
import 'package:shoucangjia/work_plays.dart';

/// 去掉整行注释与空行后的源码（用于「第二份实现」扫描）。
String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('1. 读盘 JSON 只有一个入口', () {
    test('decodePrefJson：空 / 纯空格 / 坏 JSON 都是 null', () {
      expect(decodePrefJson(null), isNull);
      expect(decodePrefJson(''), isNull);
      expect(decodePrefJson('   '), isNull);
      expect(decodePrefJson('{bad'), isNull);
      expect(decodePrefJson('[]'), isEmpty);
      expect(decodePrefJson('{"a":1}'), {'a': 1});
      // 合法标量也要原样返回：是不是表由调用方判（那才是结构差异）。
      expect(decodePrefJson('3'), 3);
    });

    test('用它的两张表行为不变：坏数据退化为空，不抛', () {
      expect(parseWatchProgress('{bad'), isEmpty);
      expect(parseWatchProgress('   '), isEmpty);
      expect(parseWorkPlays('[1,2]'), isEmpty);
      expect(parseContinueItems('{"a":1}'), isEmpty);
      expect(parseAuthorAvatarOverrides('junk'), isEmpty);
      expect(decodeServers('{"a":1}'), isEmpty);
      expect(decodeBindings('[]'), isEmpty);
      // 正常数据仍能读回（回归而不是放宽）。
      final servers = decodeServers('[{"id":"s1","base":"http://x:1"}]');
      expect(servers.single.id, 's1');
    });

    test('六张表不得再各写一遍 try { jsonDecode } catch', () {
      for (final f in const [
        'lib/watch_progress.dart',
        'lib/work_plays.dart',
        'lib/continue_watching.dart',
        'lib/author_avatar_store.dart',
        'lib/multi_server.dart',
      ]) {
        final src = _code(f);
        expect(src.contains('jsonDecode('), isFalse,
            reason: '$f 又自己解 JSON 了，读盘判定应只有 decodePrefJson');
      }
      final prefs = _code('lib/prefs_json.dart');
      expect(prefs.contains('jsonDecode('), isTrue,
          reason: '唯一实现必须在 prefs_json');
      expect(prefs.contains('Object? decodePrefJson('), isTrue);
    });
  });

  group('2. 库卡片封面预热复用同一个排队入口', () {
    test('lib_card_prefetch 不再自己构造 provider / 调 ThumbPrefetch', () {
      final src = _code('lib/lib_card_prefetch.dart');
      expect(src.contains('ThumbPrefetch.instance.run('), isFalse,
          reason: '排队只允许在 thumb_prefetch');
      expect(src.contains('thumbImageProvider('), isFalse,
          reason: 'provider 构造只允许在 thumb_prefetch');
      expect(src.contains('prefetchThumbItems('), isTrue);
      expect(RegExp(r'\bDiziCache\b').hasMatch(src), isFalse,
          reason: '缓存管理器只允许在排队那一层取');
    });

    test('排队实现本身只有一处', () {
      var runs = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = _code(f.path);
        runs += RegExp(r'ThumbPrefetch\.instance\.run\(').allMatches(src).length;
      }
      expect(runs, 1, reason: '整仓只允许 thumb_prefetch 里排一次队');
    });
  });

  group('3. 作者挂载写请求只有一个出口', () {
    test('两个入口都转发 postUnitAuthorRequest，不再自己 post', () {
      for (final f in const [
        'lib/author_mount_sheet.dart',
        'lib/unit_author_mount_page.dart',
      ]) {
        final src = _code(f);
        expect(src.contains('postUnitAuthorRequest('), isTrue, reason: f);
        // 写请求的「拼请求体 + 发出去」只能有一份（另一个手拼的 POST 是
        // `unitAuthorCreateUrl` 的逐库建目录，409 有独立语义，不在此列）。
        expect(src.contains('jsonEncode(req.toBody())'), isFalse,
            reason: '$f 又自己发了一次挂载写请求');
      }
      // 挂载页的 GET 仍走同一个地址函数（那是读，不是写请求的第二份）；
      // 作者页面板连地址也不该自己拼。
      expect(_code('lib/author_mount_sheet.dart').contains('unitAuthorGroupsUrl('),
          isFalse,
          reason: '作者页面板不应自己拼挂载地址');
    });

    test('真实发出去：POST 到 /api/unit-author-groups.json?unit=…', () async {
      Uri? seen;
      Map<String, String>? head;
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        seen = req.url;
        head = req.headers;
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      });
      await postUnitAuthorRequest(
        client,
        base: 'http://nas:8090',
        unit: 'unit-1',
        headers: const {'Authorization': 'Basic x'},
        req: const UnitAuthorRequest(
          unit: 'unit-1',
          action: UnitAuthorAction.merge,
          files: [AuthorGroupFile(lib: 'lib-1', authorDir: '@a')],
        ),
      );
      expect(seen!.path, '/api/unit-author-groups.json');
      expect(seen!.queryParameters['unit'], 'unit-1');
      expect(head!['Content-Type'], contains('application/json'));
      expect(head!['Authorization'], 'Basic x');
      expect(body!['action'], 'merge');
      expect(body!['unit'], 'unit-1');
    });

    test('服务端说失败时抛出可读原因，不静默成功', () async {
      final client = MockClient((req) async =>
          http.Response('{"ok":false,"error":"不能把整组都拆走"}', 200));
      await expectLater(
        postUnitAuthorRequest(
          client,
          base: 'http://nas:8090',
          unit: 'u',
          headers: const {},
          req: const UnitAuthorRequest(unit: 'u', action: UnitAuthorAction.delete),
        ),
        throwsA(predicate((e) => '$e'.contains('不能把整组都拆走'))),
      );
    });
  });

  group('4. 播放页停靠旧槽位后写状态有 mounted 守卫', () {
    test('setState 之前紧邻 mounted 判断', () {
      final src = _code('lib/main.dart');
      // 停靠分支的锚点：先算好 _mediaToken，再写 pos/dur。
      final idx = src.indexOf('_mediaToken = my;');
      expect(idx, greaterThan(0), reason: '找不到停靠分支的锚点');
      final window = src.substring(idx, idx + 400);
      expect(
          RegExp(r'_mediaToken = my;[\s\S]{0,200}if \(!mounted\) return;[\s\S]{0,120}setState\(')
              .hasMatch(window),
          isTrue,
          reason: 'await pause/setVolume 之后页面可能已 pop，写状态前必须判活');
    });
  });
}
