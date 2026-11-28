/// 0.9.380（第一百二十五批）契约：连接表键名 / 「激活的是哪一条」 /
/// 诊断页超时 / 四张本机表的读盘，各收成一处。
///
///  1. `'servers_v1'` / `'lib_bindings_v1'` / `'active_server_v1'` / `'lib'`
///     四个键在 `main` 与 `connection_status` 里散着十处字面量。写的时候
///     一处、读的时候另一处，改一个键名就会变成「写进去读不回来」——
///     与 `hidden_works_v1` 那次一样的坏法。现在只有 `ConnPrefsKeys`。
///  2. 「读 `active_server_v1` → 在列表里找 id → 找不到取第一条」抄了四遍，
///     其中一份「找不到返回 null」。现在只有 `activeServerOf`。
///  3. `resize_cache_api` 的 8s / 20s 是 `api_timeout` 档位之外的第二套上限。
///  4. `watch_progress` / `continue_watching` / `work_plays` /
///     `author_avatar_store` 四张表仍自己 `getInstance()` + `getString`
///     再各写一遍 try/catch；现在只转发 `readPrefString`。
///
/// 判据是源码结构与真实读盘行为；新增测试只用合成库 id（`lib-1`）与
/// 合成地址（`a:8090`），不涉及任何作者名 / 文件内容。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shoucangjia/author_avatar_store.dart';
import 'package:shoucangjia/continue_watching.dart';
import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/prefs_json.dart';
import 'package:shoucangjia/resize_cache_api.dart';
import 'package:shoucangjia/watch_progress.dart';
import 'package:shoucangjia/work_plays.dart';

/// 去掉整行注释后的源码（用于「第二份实现」扫描）。
String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

Iterable<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

ServerConn _s(String id, String base, {String label = '', bool enabled = true}) =>
    ServerConn(
        id: id,
        label: label,
        base: base,
        user: 'zzx',
        pass: enabled ? 'pw' : '',
        enabled: enabled);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. 连接表四个键：只有 ConnPrefsKeys 一处定义', () {
    test('键值就是原来那四个（落盘格式不变）', () {
      expect(ConnPrefsKeys.servers, 'servers_v1');
      expect(ConnPrefsKeys.bindings, 'lib_bindings_v1');
      expect(ConnPrefsKeys.active, 'active_server_v1');
      expect(ConnPrefsKeys.lib, 'lib');
      expect(ConnPrefsKeys.legacyBase, 'base');
      expect(ConnPrefsKeys.legacyUser, 'user');
      expect(ConnPrefsKeys.legacyPass, 'pass');
    });

    test('整仓只在 multi_server 出现这四个字面量，且各一次', () {
      for (final key in ['servers_v1', 'lib_bindings_v1', 'active_server_v1']) {
        final hits = <String>[];
        for (final f in _libFiles()) {
          final n = RegExp("'$key'").allMatches(_code(f.path)).length;
          if (n > 0) hits.add('${f.path}:$n');
        }
        expect(hits.length, 1,
            reason: "'$key' 只应在 ConnPrefsKeys 定义处出现，实际：$hits");
        expect(hits.single, endsWith('lib/multi_server.dart:1'),
            reason: "'$key' 的定义不在 multi_server.dart：${hits.single}");
      }
    });

    test('「当前库」键的读写都走常量（JSON 字段不算）', () {
      final main = _code('lib/main.dart');
      for (final bad in [
        "savePrefString('lib'",
        "getString('lib')",
        "readPrefString('lib')",
      ]) {
        expect(main.contains(bad), isFalse,
            reason: 'main 里仍有字面量键：$bad（应走 ConnPrefsKeys.lib）');
      }
      expect(main.contains('ConnPrefsKeys.lib'), isTrue);
    });

    test('connection_status 不再自己读 servers_v1', () {
      final src = _code('lib/connection_status.dart');
      expect(src.contains("getString('servers_v1')"), isFalse);
      expect(src.contains('decodeServers('), isFalse,
          reason: '连接表解析只走 loadServersFromPrefs');
      expect(src.contains('loadServersFromPrefs'), isTrue);
    });
  });

  group('2. activeServerOf：「激活的是哪一条」唯一判定', () {
    test('id 命中就用它', () {
      final list = [_s('a', 'http://a:8090'), _s('b', 'http://b:8090')];
      expect(activeServerOf(list, 'b')!.id, 'b');
    });

    test('id 不在列表里取第一条（不是 null）', () {
      final list = [_s('a', 'http://a:8090'), _s('b', 'http://b:8090')];
      expect(activeServerOf(list, 'gone')!.id, 'a');
    });

    test('空列表返回 null；旧两份实现在这里一致', () {
      expect(activeServerOf(const <ServerConn>[], 'a'), isNull);
    });

    test('真读盘：readActiveServerId 缺键为空串、有值原样返回', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await readActiveServerId(), '');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_server_v1': 'srv-7',
      });
      expect(await readActiveServerId(), 'srv-7');
    });

    test('activeServerFromPrefs 一步取到激活连接', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'active_server_v1': 'b',
      });
      final list = [_s('a', 'http://a:8090'), _s('b', 'http://b:8090')];
      expect((await activeServerFromPrefs(list))!.id, 'b');
    });

    test('main 里不再自己写「找 id / 找不到取第一条」的循环', () {
      final src = _code('lib/main.dart');
      expect(src.contains('activeServerOf'), isTrue);
      // 旧循环的特征行：`for (final s in servers) { if (s.id == active`。
      expect(RegExp(r'for \(final s in servers\)[\s\S]{0,60}?s\.id == active')
          .hasMatch(src), isFalse,
          reason: '激活连接的判定应走 activeServerOf，不再内联循环');
    });
  });

  group('3. 诊断页超时并入 api_timeout 档位', () {
    test('两个函数都不再有自带默认上限', () {
      final src = _code('lib/resize_cache_api.dart');
      expect(src.contains('Duration timeout = const Duration'), isFalse,
          reason: '默认值应走 kTimeout* 档位，不再写第二个常量');
      expect(src.contains('kTimeoutRead'), isTrue);
      expect(src.contains('kTimeoutWrite'), isTrue);
    });

    test('fetchResizeCacheStats 真发请求：200 解析、非 200 返回 null', () async {
      final ok = MockClient((req) async => http.Response(
          jsonEncode({
            'files': 3,
            'bytes': 2048,
            'maxBytes': 4096,
            'hit': 5,
            'miss': 5,
          }),
          200));
      final s = await fetchResizeCacheStats(
          Uri.parse('http://a:8090/api/cache/stats'), const {}, client: ok);
      expect(s, isNotNull);
      expect(s!.files, 3);
      expect(s.hitRate, closeTo(0.5, 0.0001));

      final bad = MockClient((req) async => http.Response('nope', 500));
      expect(
          await fetchResizeCacheStats(
              Uri.parse('http://a:8090/api/cache/stats'), const {},
              client: bad),
          isNull);
    });

    test('pruneResizeCache dryRun 把 dry=1 带上，且不改原 uri', () async {
      Uri? seen;
      final c = MockClient((req) async {
        seen = req.url;
        return http.Response(
            jsonEncode({'deleted': 0, 'freed': 0, 'bytesAfter': 100}), 200);
      });
      await pruneResizeCache(
          Uri.parse('http://a:8090/api/cache/prune?x=1'), const {},
          dryRun: true, client: c);
      expect(seen!.queryParameters['dry'], '1');
      expect(seen!.queryParameters['x'], '1');
    });

    test('显式传入 timeout 仍生效（不锁死档位）', () async {
      final c = MockClient((req) async => http.Response('{}', 200));
      final s = await fetchResizeCacheStats(
          Uri.parse('http://a:8090/api/cache/stats'), const {},
          client: c, timeout: const Duration(milliseconds: 1));
      expect(s, isNotNull);
    });
  });

  group('4. 四张本机表：读盘只转发 readPrefString', () {
    const files = [
      'lib/watch_progress.dart',
      'lib/continue_watching.dart',
      'lib/work_plays.dart',
      'lib/author_avatar_store.dart',
    ];

    for (final f in files) {
      test('$f 不再自己 getInstance / getString', () {
        final src = _code(f);
        expect(src.contains('SharedPreferences.getInstance()'), isFalse,
            reason: '$f 又自己拿了一次 sp');
        expect(src.contains('sp.getString('), isFalse,
            reason: '$f 又自己读了一次键（应走 readPrefString）');
        expect(src.contains('readPrefString'), isTrue);
      });
    }

    test('设置类单值也不再各拿一次 sp（theme/app_settings/cover_cache）', () {
      for (final f in const [
        'lib/app_theme.dart',
        'lib/app_settings.dart',
        'lib/cover_cache.dart',
      ]) {
        final src = _code(f);
        expect(src.contains('SharedPreferences.getInstance()'), isFalse,
            reason: '$f 仍自己拿 sp');
      }
      expect(_code('lib/app_theme.dart').contains('readPrefString'), isTrue);
      expect(_code('lib/cover_cache.dart').contains('readPrefInt'), isTrue);
      expect(_code('lib/cover_cache.dart').contains('readPrefBool'), isTrue);
    });

    test('readPrefInt / readPrefBool 缺键都是 null，正常值读回', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await readPrefInt('n_v1'), isNull);
      expect(await readPrefBool('b_v1'), isNull);

      await savePrefInt('n_v1', 7);
      await savePrefBool('b_v1', true);
      expect(await readPrefInt('n_v1'), 7);
      expect(await readPrefBool('b_v1'), isTrue);
    });

    test('存的是字符串而不是整数时 readPrefInt 返回 null 不抛', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'n_v1': 'abc'});
      expect(await readPrefInt('n_v1'), isNull);
    });

    test('整仓 getInstance 调用点只剩 prefs_json 的两处 + 确实需要 sp 的页面', () {
      final hits = <String>[];
      for (final f in _libFiles()) {
        final n =
            'SharedPreferences.getInstance()'.allMatches(_code(f.path)).length;
        if (n > 0) hits.add('${f.path.replaceAll('\\', '/')}:$n');
      }
      // 允许持有 sp 的只剩：prefs_json（读/写入口）、multi_server（拿已读
      // 的 sp 解析连接表）、main（启动时一次读齐连接表/绑定/库 id，多个键
      // 同源）。
      for (final h in hits) {
        final path = h.split(':').first;
        expect(
            path == 'lib/prefs_json.dart' ||
                path == 'lib/multi_server.dart' ||
                path == 'lib/main.dart',
            isTrue,
            reason: '多出一个自己拿 sp 的文件：$h');
      }
    });

    test('坏数据仍退化为空表（四张表逐一验证）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kWatchProgressPrefsKey: '   ',
        kContinuePrefsKey: '{oops',
        kWorkPlaysPrefsKey: '[1,2,3',
        kAuthorAvatarPrefsKey: 'null',
      });
      WatchProgressStore.resetForTest();
      await WatchProgressStore.ensureLoaded();
      expect(WatchProgressStore.items, isEmpty);

      ContinueWatchingStore.resetForTest();
      await ContinueWatchingStore.ensureLoaded();
      expect(ContinueWatchingStore.items, isEmpty);

      WorkPlaysStore.resetForTest(items: const {});
      await WorkPlaysStore.ensureLoaded();
      expect(WorkPlaysStore.items, isEmpty);

      await AuthorAvatarStore.instance.load();
      expect(AuthorAvatarStore.instance.has('anyone'), isFalse);
    });

    test('正常值仍能读回（读盘没被收窄）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kWorkPlaysPrefsKey: jsonEncode({
          'lib-1|w-1': {'n': 3}
        }),
        kWatchProgressPrefsKey: jsonEncode({
          'lib-1|w-1': {'p': 120000, 'd': 300000}
        }),
      });
      // resetForTest 把 `_loaded` 置真（它本身是「设好内存态」），所以这里
      // 直接走 ensureLoaded 用的那条链：readPrefString → parse。
      expect(
          parseWorkPlays(await readPrefString(kWorkPlaysPrefsKey)).length, 1);
      expect(
          parseWatchProgress(await readPrefString(kWatchProgressPrefsKey))
              .length,
          1);
    });

    test('readPrefString 与 decodePrefJson 的口径一致：缺键 null', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await readPrefString('nothing_v1'), isNull);
      expect(await readPrefJson('nothing_v1'), isNull);
    });
  });
}
