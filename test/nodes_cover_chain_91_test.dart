// 第九十一批（0.9.327）契约：节点文件夹能按服务器设、封面指针只有一条优先级链。
//
// 本轮修两件「两个入口各算一次，各自都算对了」的问题：
//
//  1. 首页 `_loadTree` 与 `LibMeta.load` 各排过一遍封面优先级。前者取
//     `libraries.json` 整树指针 ∪ `/api/nodes` 的 covers，后者只取后者——
//     而 `/api/nodes` 的 covers 只有被标记为节点的 rel 才带指针（实测 31
//     条里 4 条）。于是同一张单元库卡片在首页有 owner 设过的封面、从设置页
//     进单元库页却回落到自动封面。现在优先级链只有 `unitCoverTable` 一处。
//
//  2. 「文件结构」页只接受一份 `urlOf/headersOf`，两个调用点分别写死
//     「首条连接」与「当前库的连接」——多连接时第二台服务器的节点文件夹
//     根本设不了（首页却照常画它的卡片）。现在页面按服务器切换。
//
// 另有两条资源口径：`/api/nodes` 逐连接读取从串行改有界并发；
// 封面菜单与缩图缓存卡片的 HTTP 客户端改成页面内复用（与周边五个页面一致）。
//
// 隐私：本文件的输入全部是合成的 `s1`/`s2`/`lib-1`/`A`，不涉及任何真实名称。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/multi_server.dart';

String _codeOf(String path) {
  final raw = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  final out = StringBuffer();
  for (final line in raw.split('\n')) {
    final t = line.trimLeft();
    if (t.startsWith('//')) continue;
    out.writeln(line);
  }
  return out.toString();
}

/// `main.dart` 里某个方法的体（截到下一个同名缩进的方法定义前）。
String _method(String name, String until) {
  final src = _codeOf('lib/main.dart');
  final start = src.indexOf(name);
  final end = src.indexOf(until, start);
  expect(start, greaterThan(0), reason: '找不到 $name');
  expect(end, greaterThan(start), reason: '$name 的下一个方法名变了');
  return src.substring(start, end);
}

void main() {
  group('1. 单元库封面指针只有一条优先级链', () {
    test('整树指针优先、节点表兜底，且作用域是连接', () {
      final table = unitCoverTable(
        serverId: 's1',
        rels: const ['A', 'B'],
        treeCovers: {unitCoverKey('s1', 'A'): '/media/lib-1/a.jpg'},
        nodesCovers: const {'A': '/media/lib-1/old.jpg', 'B': '/media/lib-1/b.jpg'},
      );
      expect(table['A'], '/media/lib-1/a.jpg',
          reason: '整树指针（全部层级都有）必须压过 /api/nodes 的旧值');
      expect(table['B'], '/media/lib-1/b.jpg',
          reason: '树里没有指针时才用节点表');
    });

    test('另一台服务器的同名 rel 不会被认领', () {
      final table = unitCoverTable(
        serverId: 's2',
        rels: const ['A'],
        treeCovers: {unitCoverKey('s1', 'A'): '/media/lib-1/a.jpg'},
        nodesCovers: const {},
      );
      expect(table, isEmpty,
          reason: 's1 的指针不能给 s2 的同名目录，否则卡片去另一台机器取图');
    });

    test('空串与未归一化的 rel 都不进表', () {
      final table = unitCoverTable(
        serverId: 's1',
        rels: const ['A\\B', '  ', ''],
        treeCovers: {unitCoverKey('s1', 'A/B'): ' /media/lib-1/x.jpg '},
        nodesCovers: const {},
      );
      expect(table.keys.toList(), ['A/B'],
          reason: 'rel 归一化与服务端 unitRelKey 同一套规则');
      expect(table['A/B'], '/media/lib-1/x.jpg', reason: '值要 trim');
    });

    test('collectUnitCovers 是公开的唯一收集口（两个入口共用）', () {
      final src = _codeOf('lib/multi_server.dart');
      expect(src.contains('void collectUnitCovers('), isTrue);
      expect(src.contains('void _collectUnitCovers('), isFalse,
          reason: '私有版会让 LibMeta.load 只能再写一份');
      final main = _codeOf('lib/main.dart');
      expect(main.contains('collectUnitCovers('), isTrue,
          reason: 'LibMeta.load 也必须读整树指针，否则单元库页封面与首页不一致');
      expect(main.contains('unitCoverTable('), isTrue);
    });

    test('首页与单库作用域都用同一条链，不再各查各的表', () {
      final body = _method(
          'Future<Map<String, NodesPayload>> _fetchNodesPerServer()',
          'void _openRegisteredLibs()');
      expect(body.contains('mapConcurrent<ServerConn, NodesPayload?>('), isTrue,
          reason: '逐连接读取要有界并发：串行时 N 台服务器白等 N×8s');
      expect(body.contains('servers, 4,'), isTrue,
          reason: '输入必须是整张连接表');
      // 覆盖范围不变：仍然每台一次、单条失败就缺席。
      expect(body.contains('/api/nodes'), isTrue);
      expect(body.contains('_authFor(s)'), isTrue);
    });

    test('两条读取路径都不再自己拼封面表的键', () {
      final main = _codeOf('lib/main.dart');
      // 键的拼装只有 nodeKey / unitCoverKey；页面里出现 `\u0001` 说明又手拼了。
      expect(main.contains(r'\u0001'), isFalse,
          reason: '连接分隔符不得出现在页面代码里（唯一拼装口在 node_key）');
    });
  });

  group('2. 文件结构页按服务器工作', () {
    test('页面接受全部连接，而不是一份写死的地址', () {
      final src = _codeOf('lib/folder_structure_page.dart');
      expect(src.contains('List<FolderSource> sources'), isTrue);
      expect(src.contains('final Uri Function(String path) urlOf;'), isFalse,
          reason: '旧的单一 urlOf 入口已删除（它只能指向一条连接）');
      expect(src.contains('Uri _urlOf(String path) => _src.urlOf(path);'), isTrue);
      expect(src.contains('Map<String, String> _headers() => _src.headersOf();'),
          isTrue);
    });

    test('切换服务器会清掉上一台的勾选状态', () {
      final src = _codeOf('lib/folder_structure_page.dart');
      final start = src.indexOf('Future<void> _switchServer(int index)');
      expect(start, greaterThan(0));
      final body = src.substring(start, start + 900);
      for (final cleared in const [
        'nodes.clear()',
        'saved.clear()',
        'expanded.clear()',
        'basicRels = <String>{}',
      ]) {
        expect(body.contains(cleared), isTrue,
            reason: '切服务器必须清掉 $cleared：节点列表属于各自服务器的 nodes.json');
      }
      expect(body.contains('_confirmDiscard('), isTrue,
          reason: '有未保存改动时先确认，不静默丢弃');
    });

    test('两个入口都传全部在线连接（不再是 first / 当前库）', () {
      final src = _codeOf('lib/main.dart');
      final first = src.indexOf('Future<void> _openFolders() async {');
      final second = src.indexOf('Future<void> _openFolders() async {', first + 10);
      expect(first, greaterThan(0));
      expect(second, greaterThan(first), reason: '两个入口都要改');
      final a = src.substring(first, first + 900);
      final b = src.substring(second, second + 1500);
      expect(a.contains('for (final s in servers)'), isTrue,
          reason: '库页：把本页已知的在线连接全部交给页面');
      expect(b.contains('loadServersFromPrefs()'), isTrue,
          reason: '首页：从偏好读全部连接（不是只看 cfg）');
      expect(b.contains('liveServers('), isTrue,
          reason: '断连的连接不能出现在可切换列表里');
      for (final body in [a, b]) {
        expect(body.contains('servers.first.base'), isFalse,
            reason: '又写死第一条连接了');
        expect(body.contains('urlOf: (path)'), isFalse,
            reason: '旧入口已删除');
      }
    });

    test('连接表的读取收成一个函数（不再抄第六份）', () {
      final ms = _codeOf('lib/multi_server.dart');
      expect(ms.contains('Future<List<ServerConn>> loadServersFromPrefs('),
          isTrue);
      expect(ms.contains('migrateLegacy('), isTrue,
          reason: '旧版单 base 的迁移必须保留');
    });
  });

  group('3. 请求客户端与页面同寿命', () {
    test('封面菜单四条请求共用页面客户端', () {
      final src = _codeOf('lib/main.dart');
      expect(src.contains('final http.Client _coverClient = http.Client();'),
          isTrue);
      final start = src.indexOf('CoverMenuActions? _coverMenuFor(');
      final body = src.substring(start, start + 3000);
      // 四条：历史列表 + 回滚 + 恢复自动 + 清除全部。
      expect('client: client'.allMatches(body).length, 4,
          reason: '封面菜单的四条请求都必须带同一个客户端');
      expect(src.contains('_coverClient.close();'), isTrue,
          reason: '页面销毁要关闭，否则客户端泄漏');
    });

    test('cover_history 的两个函数可注入客户端，不传时自己关', () {
      final src = _codeOf('lib/cover_history.dart');
      for (final fn in const [
        'Future<CoverListResult> fetchCoverVersions(',
        'Future<CoverActionResult> clearCustomCover(',
      ]) {
        final start = src.indexOf(fn);
        expect(start, greaterThan(0), reason: '找不到 $fn');
        final body = src.substring(
            start, start + 2600 > src.length ? src.length : start + 2600);
        expect(body.contains('http.Client? client'), isTrue,
            reason: '$fn 要接受注入客户端');
        expect(body.contains('if (client == null) c.close();'), isTrue,
            reason: '$fn 只在自建客户端时关闭（注入的由调用方管理）');
      }
    });

    test('缩图缓存卡片自己持有客户端并在 dispose 关闭', () {
      final src = _codeOf('lib/crash_reports_page.dart');
      expect(src.contains('late final http.Client _client = http.Client();'),
          isTrue);
      expect(src.contains('_client.close();'), isTrue);
      expect(src.contains('client: _client'), isTrue,
          reason: '统计与清理都要复用同一个客户端');
    });
  });
}
