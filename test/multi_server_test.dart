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
    final a = _s('a', 'http://a:8090');
    final bindings = buildBindings(servers: [a], libraries: [
      {'id': 'douyin', '_serverId': 'a'}
    ]);
    expect(bindings['douyin']!['base'], 'http://a:8090');
    expect(bindings['douyin']!['server'], 'a');
    final back = decodeBindings(encodeBindings(bindings));
    expect(back['douyin']!['base'], 'http://a:8090');
    expect(back['douyin']!['user'], 'u');
    expect(decodeBindings('[]'), isEmpty);
    expect(decodeBindings('{"bad": 1}'), isEmpty);
  });

  test('新增连接 id 不重复', () {
    final list = [_s('srv-2', 'http://a:8090')];
    expect(nextServerId(list), 'srv-3');
    expect(nextServerId(const []), 'srv-1');
  });
}
