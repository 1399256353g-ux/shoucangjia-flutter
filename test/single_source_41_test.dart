/// 第六十一批：**同一条记录的身份字段、同一个请求体、同一张卡的代表库**
/// 各被抄成多份。
///
/// 前三批抓的是「规则被抄成两份」。这一批换个形态：**一份数据在写入时
/// 只有一处，但读取时的字段名与归一化在 5 处各写一遍**——正常数据看不出来，
/// 只有在「某个字段补了 trim、另一个没补」时才翻车，而每处单独看都对。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_admin.dart';
import 'package:shoucangjia/cover_history.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/server_origin.dart';
import 'package:shoucangjia/source_lib.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 只保留非注释行，避免文档里的「旧写法」被契约扫描当成现役代码。
String _lib(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///');
    })
    .join('\n');

ServerConn _conn({
  String id = 's1',
  String base = 'http://a:8090',
  String label = '家里',
  String user = 'u',
  String pass = 'p',
}) =>
    ServerConn(id: id, label: label, base: base, user: user, pass: pass);

void main() {
  group('项 1 · 来源连接字段：一处写、一处读', () {
    test('withServerOrigin 写出的键就是 serverOriginOf 读的那些', () {
      final m = withServerOrigin(
        const <String, dynamic>{'id': 'lib-1'},
        id: ' s1 ',
        base: ' http://a:8090 ',
        label: ' 家里 ',
        user: 'u',
        pass: 'p',
      );
      expect(m['id'], 'lib-1', reason: '原有字段必须保留');
      final o = serverOriginOf(m);
      expect(o.id, 's1');
      expect(o.base, 'http://a:8090');
      expect(o.label, '家里');
      expect(o.user, 'u');
      expect(o.pass, 'p');
      expect(o.isEmpty, isFalse);
    });

    test('缺失字段一律空串（不返回 null、不返回 "null"）', () {
      final o = serverOriginOf(const <String, dynamic>{'id': 'x'});
      expect(o.id, '');
      expect(o.base, '');
      expect(o.label, '');
      expect(o.user, '');
      expect(o.pass, '');
      expect(o.isEmpty, isTrue);
    });

    test('账号/密码：区分「没写这个键」与「写了空串」', () {
      // 旧格式（离线快照）没有 _serverUser/_serverPass：应用当前连接的账号。
      final legacy = serverOriginOf(const <String, dynamic>{
        '_serverBase': 'http://a:8090',
      });
      expect(legacy.hasUser, isFalse);
      expect(legacy.hasPass, isFalse);

      // 写了但为空：这条连接确实不需要鉴权，不能回落到当前连接。
      final anonymous = serverOriginOf(const <String, dynamic>{
        '_serverBase': 'http://a:8090',
        '_serverUser': '',
        '_serverPass': '',
      });
      expect(anonymous.hasUser, isTrue);
      expect(anonymous.hasPass, isTrue);
      expect(anonymous.user, '');
      expect(anonymous.pass, '');
    });

    test('非 Map 输入给空来源，不抛异常', () {
      expect(serverOriginOf(null).isEmpty, isTrue);
      expect(serverOriginOf('x').isEmpty, isTrue);
      expect(serverOriginOf(const <dynamic>[]).isEmpty, isTrue);
    });

    test('_tag 产出的五个键与 serverOriginOf 完全对称', () {
      final merged = mergeLibraryTrees([
        ServerLibraries(
          server: _conn(),
          libraries: const <Map<String, dynamic>>[],
          tree: const <String, dynamic>{
            'bigLibraries': <dynamic>[],
            'basicLibraries': <dynamic>[
              <String, dynamic>{'id': 'lib-1', 'rel': 'A'},
            ],
          },
        ),
      ]);
      final basic = (merged!['basicLibraries'] as List).single as Map;
      final o = serverOriginOf(basic);
      expect(o.id, 's1');
      expect(o.base, 'http://a:8090');
      expect(o.label, '家里');
      expect(o.user, 'u');
      // 密码只用于切换时重绑，不进展示模型；这里只确认读写对称。
      expect(o.pass, 'p');
    });

    test('契约：五个键名不出现在 server_origin.dart 之外', () {
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('server_origin.dart')) continue;
        final s = _lib(f.path);
        for (final k in const [
          '_serverId',
          '_serverBase',
          '_serverLabel',
          '_serverUser',
          '_serverPass',
        ]) {
          if (s.contains("'$k'")) offenders.add('${f.path}: $k');
        }
      }
      expect(offenders, isEmpty);
    });

    test('契约：fc 只在 firstWorkCoverOf 里读', () {
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('server_origin.dart')) continue;
        if (_lib(f.path).contains("['fc']")) offenders.add(f.path);
      }
      expect(offenders, isEmpty);
    });
  });

  group('项 2 · 封面请求体：lib + unitRel + 附加字段', () {
    test('unitRel 为空时不带这个键', () {
      final b = coverScopeBody(lib: 'l1');
      expect(b.containsKey('unitRel'), isFalse);
      expect(b['lib'], 'l1');
    });

    test('unitRel 归一后才发（反斜杠 / 点段 / 空段）', () {
      expect(coverScopeBody(lib: 'l', unitRel: r'A\B')['unitRel'], 'A/B');
      expect(coverScopeBody(lib: 'l', unitRel: 'A//./B')['unitRel'], 'A/B');
      // 归一后为空串 → 等同于没有单元库作用域，不能写出 'unitRel': ''。
      expect(
          coverScopeBody(lib: 'l', unitRel: './')['unitRel'], isNull);
    });

    test('lib 也 trim（服务端按 id 精确匹配）', () {
      expect(coverScopeBody(lib: ' l1 ')['lib'], 'l1');
    });

    test('附加字段与作用域字段合并，不能互相覆盖 lib/unitRel', () {
      final b = coverScopeBody(
        lib: 'l1',
        unitRel: 'A/B',
        extra: const <String, dynamic>{'v': 'v1', 'e': 'png'},
      );
      expect(b, containsPair('lib', 'l1'));
      expect(b, containsPair('unitRel', 'A/B'));
      expect(b, containsPair('v', 'v1'));
      expect(b, containsPair('e', 'png'));
      // unitRel 归一后落在键上，附加字段不会把作用域换掉。
      final e = coverScopeBody(
        lib: 'l1',
        unitRel: 'A',
        extra: const <String, dynamic>{'unitRel': 'zzz'},
      );
      expect(e['unitRel'], 'zzz', reason: 'extra 在后，显式覆盖是有意的');
    });

    test('上传/回滚/清除三条请求体都走同一个拼装（不各自手写 map）', () async {
      Map<String, dynamic>? seen;
      final client = MockClient((r) async {
        seen = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      });
      await restoreCoverVersion(
        url: Uri.parse('http://nas/api/cover/restore'),
        headers: const <String, String>{},
        libId: 'l1',
        unitRel: r'A\B',
        version: 'v1',
        ext: 'png',
        client: client,
      );
      expect(seen!['unitRel'], 'A/B', reason: '回滚也走归一');

      await clearCustomCover(
        url: Uri.parse('http://nas/api/cover/clear'),
        headers: const <String, String>{},
        libId: 'l1',
        unitRel: './',
        hard: true,
      );
    });

    test('契约：四处请求体不再各自写 unitRel 三元', () {
      for (final p in const [
        'lib/cover_history.dart',
        'lib/cover_upload.dart',
      ]) {
        final s = _lib(p);
        expect(s.contains("if (unitRel.isNotEmpty) 'unitRel'"), isFalse,
            reason: '$p 仍在手拼作用域键');
      }
    });
  });

  group('项 3 · 单元库的「代表基础库」只有一个判定', () {
    BasicLib b(String id, String rel) => BasicLib(
          id: id,
          name: id,
          rel: rel,
          bigId: '',
          authors: 1,
          works: 1,
        );

    UnitLibrary unit(String rel,
            {List<BasicLib> basics = const <BasicLib>[],
            List<UnitLibrary> children = const <UnitLibrary>[]}) =>
        UnitLibrary(
          node: LibNode(id: rel, rel: rel, name: rel),
          basics: basics,
          children: children,
        );

    test('直属基础库优先于子树更深处的', () {
      final u = unit('A',
          basics: [b('own', 'A')],
          children: [unit('A/x', basics: [b('deep', 'A/x')])]);
      expect(u.coverLib?.id, 'own');
    });

    test('没有直属时按深度优先取第一个', () {
      final u = unit('A', children: [
        unit('A/x', basics: [b('first', 'A/x')]),
        unit('A/y', basics: [b('second', 'A/y')]),
      ]);
      expect(u.coverLib?.id, 'first');
    });

    test('整棵子树没有基础库时给 null（不是抛异常、不是空 id）', () {
      expect(unit('A').coverLib, isNull);
    });

    test('封面地址按代表基础库路由（与鉴权头同一个库）', () {
      // 这条钉住「封面来自 A 库、鉴权用 B 库」那类分裂：两者都读 coverLib。
      final u = unit('A', children: [
        unit('A/x', basics: [b('only', 'A/x')]),
      ]);
      expect(u.coverLib?.id, 'only');
    });

    test('契约：allBasics.isNotEmpty ? ...first.id 不再出现在 lib/', () {
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = _lib(f.path);
        if (s.contains('allBasics.isNotEmpty ?') &&
            s.contains('.allBasics.first')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('项 4 · 来源字段在四个模型里同一口径', () {
    test('basicLibraries 的 _server* 落到 BasicLib 三个字段', () {
      final tree = LibraryTree.parse(const <String, dynamic>{
        'bigLibraries': <dynamic>[
          <String, dynamic>{
            'id': 'big-1',
            'name': 'B',
            '_serverId': ' s1 ',
          },
        ],
        'basicLibraries': <dynamic>[
          <String, dynamic>{
            'id': 'lib-1',
            'rel': 'A',
            'big_id': 'big-1',
            'fc': ' /media/lib-1/A/x.jpg ',
            '_serverId': ' s1 ',
            '_serverBase': ' http://a:8090 ',
            '_serverLabel': ' 家里 ',
          },
        ],
      })!;
      final bl = tree.allBasics.single;
      expect(bl.serverId, 's1');
      expect(bl.serverBase, 'http://a:8090');
      expect(bl.serverLabel, '家里');
      expect(bl.firstCover, '/media/lib-1/A/x.jpg', reason: 'fc 也 trim 一次');
      expect(tree.bigs.single.serverId, 's1',
          reason: '大库自己那份 _server* 也要落到模型上');
    });

    test('基础库只有一个模型：basicsUnderBase 与 LibraryTree.parse 来源字段一致', () {
      final raw = <String, dynamic>{
        'id': 'lib-1',
        'name': 'A',
        'rel': 'A',
        'path': '/root/A',
        'fc': '/media/lib-1/A/x.jpg',
        '_serverId': 's1',
        '_serverBase': 'http://a:8090',
        '_serverLabel': '家里',
      };
      final ref = basicsUnderBase(<String, dynamic>{
        'root': '/root',
        'basicLibraries': <dynamic>[raw],
      }, '/root').single;
      final lib = LibraryTree.parse(<String, dynamic>{
        'bigLibraries': <dynamic>[
          <String, dynamic>{'id': 'big-1', 'name': 'A', 'path': '/root/A'},
        ],
        'basicLibraries': <dynamic>[
          <String, dynamic>{...raw, 'big_id': 'big-1'},
        ],
      })!
          .allBasics
          .single;
      expect(lib.serverId, ref.serverId);
      expect(lib.serverBase, ref.serverBase);
      expect(lib.serverLabel, ref.serverLabel);
      expect(lib.firstCover, ref.firstCover);
    });

    test('单元库节点与基础库的来源字段同一套规则', () {
      final nodes = nodesFromV2(const <String, dynamic>{
        'nodes': <dynamic>[
          <String, dynamic>{
            'id': 'n1',
            'rel': 'A',
            '_serverId': ' s1 ',
            '_serverBase': ' http://a:8090 ',
            '_serverLabel': ' 家里 ',
          },
        ],
      });
      expect(nodes.single.serverId, 's1');
      expect(nodes.single.serverBase, 'http://a:8090');
      expect(nodes.single.serverLabel, '家里');
    });
  });
}
