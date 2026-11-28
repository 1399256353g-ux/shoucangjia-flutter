// 第九十批（0.9.326）契约：多连接下节点文件夹各归各的连接 / 角标只剩三档。
//
// 本轮修两件「界面看着正常、实际是另一台机器的数据」的问题：
//
//  1. 首页 `_loadTree` 只读**第一条连接**的 `/api/nodes`，再用这台的
//     `serverId/base/label` 覆盖**全部**节点。第二台服务端在「文件结构」里
//     勾的节点文件夹整批不上屏（那台塌成「第一层目录当卡片」）；第一台恰好
//     有同名 rel 时，第二台的基础库被挂到第一台的节点上，封面与鉴权按第一台
//     去请求 —— 必然 404，而界面看起来只是「有卡片、没图」。
//
//  2. 角标枚举里留着 `other`（设置页写「其它（非库语境）」）。owner 反复提
//     「不明所以的文字」，而 `lib/` 里没有任何调用点会把角标画成它 ——
//     留着只会让人问「第四种角标控制哪里」。词条侧删掉 `other` 是同一个决定。
//
// 隐私：本文件的输入全部是合成的 `s1`/`s2`/`lib-1`/`A`，不涉及任何真实名称。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_corner_badge.dart';

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

/// `_loadTree` 的方法体（截到下一个方法定义前）。
String _loadTreeBody() {
  final src = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
  final start = src.indexOf('Future<void> _loadTree()');
  final end = src.indexOf('Future<void> _toggleUnitStar(', start);
  expect(start, greaterThan(0), reason: '找不到 _loadTree');
  expect(end, greaterThan(start), reason: '_loadTree 的下一个方法名变了');
  return src.substring(start, end);
}

void main() {
  group('1. 节点文件夹按连接分别读取与归属', () {
    test('_loadTree 不再存在「只取第一条连接」的取数口径', () {
      // 只看代码行：注释里引用旧写法是允许的（那是在解释为什么改）。
      final body = _codeOf('lib/main.dart');
      final start = body.indexOf('Future<void> _loadTree()');
      final end = body.indexOf('Future<void> _toggleUnitStar(', start);
      final fn = body.substring(start, end);
      // 唯一允许的 `servers.first` 是「全局库根名只由首条连接写」那一处
      // （旧页面没有 meta 时用它）。任何拿它当**节点归属**的写法都必须没有。
      for (final bad in const [
        'firstServer',
        'servers.first?.id',
        'servers.first.base',
        'servers.first.cardLabel',
      ]) {
        expect(fn.contains(bad), isFalse,
            reason: '_loadTree 又把节点归给第一条连接了（$bad）：第二台勾的'
                '节点整批不上屏，同名 rel 还会把第二台的基础库挂到第一台');
      }
      expect(fn.contains('_fetchNodesPerServer()'), isTrue,
          reason: '节点必须逐条连接读取（每台有自己的 /api/nodes）');
    });

    test('节点自带「它自己那条连接」的 base / label，不是别人的', () {
      final body = _loadTreeBody();
      // 构造点在 `nodesOfServer(ServerConn s)` 里，字段必须读 s.xxx。
      expect(body.contains('serverId: s.id'), isTrue,
          reason: '节点的连接标识必须是它自己的连接 id');
      expect(body.contains('serverBase: s.base'), isTrue,
          reason: '节点的地址必须是它自己的连接（否则封面/鉴权打到另一台）');
      expect(body.contains('serverLabel: s.cardLabel'), isTrue,
          reason: '节点的显示名必须是它自己的连接');
    });

    test('封面指针按「这一条连接」查，不按某条全局连接查', () {
      final body = _loadTreeBody();
      // 0.9.327：优先级链收进 `multi_server.unitCoverTable`（首页与
      // `LibMeta.load` 共用），但作用域仍是**这一条连接**——调用处必须把
      // `serverId: s.id` 传进去。只按 rel 查会让 B 的卡片拿到 A 的指针。
      expect(body.contains('unitCoverTable('), isTrue,
          reason: '封面指针必须走唯一优先级链（与 LibMeta.load 同源）');
      expect(body.contains('serverId: s.id'), isTrue,
          reason: '封面表的作用域必须是本连接 id');
      expect(body.contains('treeCovers: treeCovers'), isTrue,
          reason: '整树指针要传进去：/api/nodes 的 covers 只覆盖被标记的节点');
      expect(body.contains('nodesCovers: payload.covers'), isTrue,
          reason: '节点权威来源是 /api/nodes 的 covers');
      // owner 2026-11-28：带封面但**未被勾选**的目录不得再被造节点。
      // 旧断言要求这里存在「按本连接反向补 rel」的写法（`nodeKeyHasServer`）；
      // 那正是「没设成单元库的文件夹却出现卡片」的成因，已删除。
      // 现在 rels 只能来自 `/api/nodes`。
      // owner 2026-11-28：`nodeKeyHasServer` 现在只用于把「非节点目录的手动
      // 封面」挂到最近祖先（`childCoverUrls`），**不再**用来反推节点。
      // 「未勾选的目录不得变成卡片」这条仍由 `payload.rels` 单独保证。
      expect(body.contains('payload.rels'), isTrue,
          reason: '节点来源只能是 /api/nodes 的勾选列表');
      expect(body.contains('childCoverUrls'), isTrue,
          reason: '非节点目录的手动封面要能挂到祖先，供上级取用');
    });

    test('逐连接读取真的发给每一条连接（不是换个名字照旧读一条）', () {
      final src = _codeOf('lib/main.dart');
      final start = src.indexOf(
          'Future<Map<String, NodesPayload>> _fetchNodesPerServer()');
      expect(start, greaterThan(0), reason: '找不到 _fetchNodesPerServer');
      final body = src.substring(start, start + 1400);
      // 0.9.327：遍历改成有界并发（`mapConcurrent`，与爬虫设置页同一口径），
      // 覆盖范围仍是**全部**连接；串行版会让 N 台服务器白等 N×8s。
      expect(body.contains('mapConcurrent<ServerConn, NodesPayload?>('),
          isTrue,
          reason: '必须把全部连接都发出去（并发，不是只读一条）');
      expect(body.contains('servers, 4,'), isTrue,
          reason: '并发入口的输入必须是整张连接表');
      expect(body.contains('/api/nodes'), isTrue,
          reason: '取数地址必须是节点文件夹接口');
      expect(body.contains('_authFor(s)'), isTrue,
          reason: '每次请求都要带那台自己的账号');
      expect(body.contains('.timeout('), isTrue,
          reason: '请求必须有上限（与其它页面同一条口径）');
      // 单条失败不能变成「那一台没有节点」以外的任何东西。
      expect(body.contains('return null;'), isTrue,
          reason: '读不到就缺席，不造假条目');
    });

    test('只读一条连接的旧实现已整体删除（不留第二份口径）', () {
      final src = _codeOf('lib/main.dart');
      expect(src.contains('_fetchMarkedNodesUnused'), isFalse,
          reason: '不能留下「换个名字照旧只读 first」的第二份实现');
      expect(src.contains('class MarkedNodes'), isFalse,
          reason: '逐连接读取后 MarkedNodes 已无调用点，删掉比留着更清楚');
    });
  });

  group('2. 角标只剩三档（other 删除）', () {
    test('枚举只有 top / unit / basic', () {
      expect(LibBadgeKind.values.length, 3);
      expect(LibBadgeKind.values.map((e) => e.name).toList(),
          ['top', 'unit', 'basic']);
    });

    test('默认图案与默认颜色表都只剩三档', () {
      expect(kDefaultCornerPattern.length, 3);
      expect(kDefaultCornerColor.length, 3);
      for (final k in LibBadgeKind.values) {
        expect(kDefaultCornerPattern.containsKey(k), isTrue);
        expect(kDefaultCornerColor.containsKey(k), isTrue);
      }
    });

    test('lib/ 与设置页都不再出现「其它（非库语境）」这类文案', () {
      expect(_codeOf('lib/main.dart').contains('其它（非库语境）'), isFalse);
      expect(_codeOf('lib/library_corner_badge.dart').contains('非库语境'), isFalse);
      final offenders = <String>[];
      for (final f in Directory('lib').listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (_codeOf(f.path).contains('LibBadgeKind.other')) {
          offenders.add(f.uri.pathSegments.last);
        }
      }
      expect(offenders, isEmpty, reason: 'other 又被引用了: $offenders');
    });

    test('三档默认图案互不相同（形状一致只靠图案区分）', () {
      final patterns =
          LibBadgeKind.values.map(LibraryCornerBadge.patternFor).toList();
      expect(patterns.toSet().length, 3);
    });

    test('设置页按枚举遍历：三档就只画三项，硬编码四行会立刻不一致', () {
      final src = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final start = src.indexOf('class _CornerBadgeSettingsPageState');
      final end = src.indexOf('Widget _kindTile(', start);
      final body = src.substring(start, end);
      expect(body.contains('for (final kind in LibBadgeKind.values)'), isTrue,
          reason: '设置页条目必须由枚举驱动，不得手写死第四项');
    });
  });
}
