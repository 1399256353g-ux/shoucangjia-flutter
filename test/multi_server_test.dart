import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/multi_server.dart';

ServerConn _s(String id, String base,
        {bool visible = true, String label = ''}) =>
    ServerConn(
        id: id,
        label: label,
        base: base,
        user: 'u',
        pass: 'p',
        enabled: visible);

void main() {
  test('地址规范化与连接编解码容错', () {
    expect(normalizeBase(' 192.168.2.4:8090/ '), 'http://192.168.2.4:8090');
    expect(normalizeBase('https://a.b/'), 'https://a.b');
    expect(decodeServers('not json'), isEmpty);
    final list = decodeServers(jsonEncode([
      {'id': 'a', 'base': 'http://1.2.3.4:8090', 'user': 'x', 'pass': 'y'},
      {'id': 'b', 'base': 'http://1.2.3.4:8090'},
      {'id': 'c', 'base': 'http://5.6.7.8:8090', 'visible': false},
    ]));
    expect(list.length, 2);
    expect(list.first.base, 'http://1.2.3.4:8090');
    expect(list.last.visible, false);
    final round = decodeServers(encodeServers(list));
    expect(round.length, 2);
    expect(round.last.id, 'c');

  });

  test('P5 断连：清密码、不参与聚合；旧 visible 字段仍可读', () {
    final s = _s('a', 'http://a:8090', label: '家里');
    final off = disconnectServer(s);
    expect(off.enabled, false);
    expect(off.pass, isEmpty);
    expect(off.visible, false);
    expect(liveServers([s, off]).map((e) => e.id), ['a']);
    expect(disconnectedCount([s, off]), 1);
    // 重连必须带新密码
    final back = reconnectServer(off, 'newpass');
    expect(back.enabled, true);
    expect(back.pass, 'newpass');
    // 旧格式（只有 visible）读入后按同语义，且断连时不保留密码
    final legacy =
        decodeServers('[{"id":"x","base":"http://x:1","pass":"old","visible":false}]');
    expect(legacy.single.enabled, false);
    expect(legacy.single.pass, isEmpty);
  });

  test('旧版单地址自动迁移为第一条连接', () {
    final out = migrateLegacy(
        servers: const [],
        base: '192.168.2.4:8090',
        user: 'zzx',
        pass: 'secret');
    expect(out.length, 1);
    expect(out.first.base, 'http://192.168.2.4:8090');
    expect(out.first.user, 'zzx');
    expect(
        migrateLegacy(
                servers: out, base: 'http://other:1', user: '', pass: '')
            .length,
        1);
  });

  test('多 IP 聚合去重：同库只保留一份，隐藏连接不参与', () {
    final a = _s('a', 'http://a:8090', label: '家里');
    final b = _s('b', 'http://b:8090', label: '公司');
    final c = _s('c', 'http://c:8090', visible: false, label: '离线');
    final merged = mergeRegisteredLibraries([
      ServerLibraries(server: a, libraries: [
        {'id': 'douyin', 'name': '抖音'},
        {'id': 'only-a', 'name': 'A'},
      ]),
      ServerLibraries(server: b, libraries: [
        {'id': 'douyin', 'name': '抖音镜像'},
        {'id': 'only-b', 'name': 'B'},
      ]),
      ServerLibraries(server: c, libraries: [
        {'id': 'hidden', 'name': '隐藏'},
      ]),
    ]);
    expect(merged.map((e) => e['id']), ['douyin', 'only-a', 'only-b']);
    expect(merged.first['name'], '抖音');
    expect(merged.first['_serverBase'], 'http://a:8090');
    expect(merged.first['_serverLabel'], '家里');
  });

  test('库树聚合去重并保留来源连接', () {
    final a = _s('a', 'http://a:8090');
    final b = _s('b', 'http://b:8090');
    final t1 = {
      'bigLibraries': [
        {'id': 'big-01', 'name': '大库一'}
      ],
      'basicLibraries': [
        {'id': 'lib-001', 'name': '基础一', 'big_id': 'big-01'}
      ],
    };
    final t2 = {
      'bigLibraries': [
        {'id': 'big-01', 'name': '重复大库'},
        {'id': 'big-02', 'name': '大库二'},
      ],
      'basicLibraries': [
        {'id': 'lib-001', 'name': '重复基础'},
        {'id': 'lib-002', 'name': '基础二', 'big_id': 'big-02'},
      ],
    };
    final merged = mergeLibraryTrees([
      ServerLibraries(server: a, libraries: const [], tree: t1),
      ServerLibraries(server: b, libraries: const [], tree: t2),
    ])!;
    expect((merged['bigLibraries'] as List).length, 2);
    expect((merged['basicLibraries'] as List).length, 2);
    final basic = (merged['basicLibraries'] as List).first;
    expect(basic['id'], 'lib-001');
    expect(basic['_serverId'], 'a');
    expect(basic['_serverBase'], 'http://a:8090');
  });

  test('绑定表按库记录来源连接并可往返', () {
    final a = _s('a', 'http://a:8090', label: '家里');
    final bindings = buildBindings(servers: [a], libraries: [
      {'id': 'douyin', '_serverId': 'a'}
    ]);
    expect(bindings['douyin']!['base'], 'http://a:8090');
    expect(bindings['douyin']!['server'], 'a');
    final back = decodeBindings(encodeBindings(bindings));
    expect(back['douyin']!['base'], 'http://a:8090');
    expect(back['douyin']!['user'], 'u');
    // 写进去的字段必须能读回来：此前 decodeBindings 漏读 `label`，
    // 每次重启后首页媒体库卡片上的连接名都会消失。
    expect(back['douyin']!['label'], '家里');
    expect(decodeBindings('[]'), isEmpty);
    expect(decodeBindings('{"bad": 1}'), isEmpty);
  });

  test('绑定记录只有一个拼装口（写与读的字段集合对称）', () {
    final a = _s('a', 'http://a:8090', label: '公司');
    final e = bindingEntry(a);
    expect(e.keys.toSet(),
        {'base', 'user', 'pass', 'server', 'label'});
    // 每个字段都必须经过一次往返后仍是原值（多一个没读的字段、
    // 少一个没写的字段，这条都会红）。
    final back = decodeBindings(encodeBindings({'k': e}))['k']!;
    expect(back, e);
  });

  test('新增连接 id 不重复', () {
    final list = [_s('srv-2', 'http://a:8090')];
    expect(nextServerId(list), 'srv-3');
    expect(nextServerId(const []), 'srv-1');
  });

  group('pruneBindings —— P5 断连清密码必须挺过重启', () {
    test('已断连连接的绑定（含密码）被丢掉', () {
      final on = _s('a', 'http://a:8090', label: '家里');
      final off = ServerConn(
          id: 'b', label: '公司', base: 'http://b:8090', user: 'u',
          pass: '', enabled: false);
      final kept = bindingEntry(on);
      // 断连前落盘的旧绑定：磁盘上还带着密码，指向 b。
      final stale = <String, String>{
        'base': 'http://b:8090',
        'user': 'u',
        'pass': '旧密码',
        'server': 'b',
        'label': '公司',
      };
      final out = pruneBindings(
          {'lib-ok': kept, 'lib-stale': stale}, liveServers([on, off]));
      expect(out.keys, ['lib-ok']);
      // 断连那条不能以任何形式留在表里（路由与凭据都没了）。
      expect(encodeBindings(out).contains('旧密码'), isFalse);
      expect(encodeBindings(out).contains('http://b:8090'), isFalse);
    });

    test('在线连接的绑定用当前值重建（改过的旧密码不会留下）', () {
      final a = _s('a', 'http://a:8090', label: '家里');
      final out = pruneBindings({
        'lib-1': <String, String>{
          'base': 'http://a:8090',
          'user': 'u',
          'pass': '旧密码',
          'server': 'a',
          'label': '',
        }
      }, [a]);
      expect(out['lib-1'], bindingEntry(a));
      expect(out['lib-1']!['pass'], 'p');
      expect(out['lib-1']!['label'], '家里');
    });

    test('旧格式没有 server 字段时按 base 匹配，匹配不上就丢弃', () {
      final a = _s('a', 'http://a:8090');
      final out = pruneBindings({
        'hit': <String, String>{'base': 'http://a:8090/', 'pass': 'x'},
        'miss': <String, String>{'base': 'http://gone:8090', 'pass': 'y'},
      }, [a]);
      expect(out.keys, ['hit']);
      expect(out['hit']!['server'], 'a');
    });

    test('全部在线时不动（纯函数不产生噪音写入）', () {
      final a = _s('a', 'http://a:8090', label: '家里');
      final src = {'lib-1': bindingEntry(a)};
      expect(encodeBindings(pruneBindings(src, [a])),
          encodeBindings(src));
    });
  });
}
