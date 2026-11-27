/// 第八十六批契约（0.9.322）：
///  1. **爬虫设置页的两份列表合成一份**——分节可折叠的单元库条目 + 一平铺的
///     注册库条目：同一个媒体库的设置被拆成两处，注册库那一份还完全不折叠。
///     现在两者都进 `crawler_sections.crawlerSectionsOf` 的分节。
///  2. **分节只吃默认注册库那台服务器**——`LibMeta.load(cfg.lib)` 只认识
///     默认库那棵树，第二台服务端的单元库与库在这页一条都不出现。现在按
///     在线连接逐台取，再合并。
///  3. **单元库「有没有脚本」判定写两遍**（分节标题的计数、条目置灰），
///     且键只按 rel——两台服务端同名目录互相顶掉。现在唯一判定在
///     `unitHasCrawlerScript`，键带连接（`mergeCrawlerFlags`）。
///  4. **脚本目录在无绝对路径时回落到相对路径**——同一页两行两种坐标。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/basic_auth.dart';
import 'package:shoucangjia/crawler_sections.dart';
import 'package:shoucangjia/server_origin.dart';
import 'package:shoucangjia/unit_crawler.dart';
import 'package:shoucangjia/unit_library.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

UnitLibrary _unit(String rel,
    {String serverId = '', List<UnitLibrary> children = const []}) {
  final segs = rel.split('/');
  return UnitLibrary(
    node: LibNode(
      id: rel,
      rel: rel,
      name: segs.last,
      serverId: serverId,
      serverBase: serverId.isEmpty ? '' : 'http://$serverId',
      serverLabel: serverId,
    ),
    basics: const <BasicLib>[],
    children: children,
  );
}

/// 造一份「媒体库根 + 两个单元库」的元数据视图。
CrawlerMetaUnits _meta(String serverId) {
  final a = _unit('A', serverId: serverId);
  final b = _unit('B', serverId: serverId);
  final media = UnitLibrary(
    node: LibNode(
      id: 'media:$serverId',
      rel: '',
      name: serverId == 's1' ? '媒体库一' : '媒体库二',
      serverId: serverId,
      serverBase: 'http://$serverId',
      serverLabel: serverId,
    ),
    basics: const <BasicLib>[],
    children: <UnitLibrary>[a, b],
  );
  return (tops: <UnitLibrary>[media], units: <UnitLibrary>[a, b]);
}

void main() {
  group('按媒体库分节（唯一实现）', () {
    test('两个连接的单元库各进自己那一节，不丢、不混', () {
      final sections = crawlerSectionsOf(metas: [_meta('s1'), _meta('s2')]);
      expect(sections.length, 2);
      expect(sections.map((s) => s.top!.node.serverId).toList(), ['s1', 's2']);
      for (final s in sections) {
        expect(s.units.length, 2);
        expect(s.units.map((u) => u.node.serverId).toSet(),
            {s.top!.node.serverId});
      }
    });

    test('两台服务端同名 rel 的单元库不会合并成一条', () {
      final sections = crawlerSectionsOf(metas: [_meta('s1'), _meta('s2')]);
      final keys = <String>[
        for (final s in sections)
          for (final u in s.units) unitScopeKey(u)
      ];
      expect(keys.toSet().length, keys.length);
      expect(keys.length, 4);
    });

    test('分节键带连接：同名媒体库不会共用一个折叠开关', () {
      final sections = crawlerSectionsOf(metas: [_meta('s1'), _meta('s2')]);
      expect(sections[0].key, isNot(sections[1].key));
      expect(sections[0].key.contains('s1'), isTrue);
      expect(sections[1].key.contains('s2'), isTrue);
    });

    test('注册库条目归入所属连接的媒体库节', () {
      final sections = crawlerSectionsOf(
        metas: [_meta('s1'), _meta('s2')],
        librariesByServer: {
          's1': [
            {'id': 'lib-1', 'name': '一'}
          ],
          's2': [
            {'id': 'lib-2', 'name': '二'}
          ],
        },
      );
      expect(sections[0].libraries.single['id'], 'lib-1');
      expect(sections[1].libraries.single['id'], 'lib-2');
    });

    test('没有顶级节点的连接落到「其它」，条目一条不丢', () {
      final sections = crawlerSectionsOf(
        metas: const <CrawlerMetaUnits>[],
        librariesByServer: {
          's9': [
            {'id': 'lib-9', 'name': '九'}
          ],
        },
      );
      expect(sections.length, 1);
      expect(sections.single.isOther, isTrue);
      expect(sections.single.libraries.single['id'], 'lib-9');
      expect(sections.single.key, '');
    });

    test('媒体库之间按名称稳定排序（同名不换位）', () {
      final sections = crawlerSectionsOf(metas: [_meta('s2'), _meta('s1')]);
      expect(sections.map((s) => s.top!.name).toList(), ['媒体库一', '媒体库二']);
    });
  });

  group('「有没有爬虫脚本」：唯一判定 + 连接作用域', () {
    test('合并表按连接建键，同名 rel 互不覆盖', () {
      final merged = mergeCrawlerFlags({
        's1': {'A': true},
        's2': {'A': false},
      });
      expect(merged.length, 2);
      expect(merged[unitRelKey('s1', 'A')], isTrue);
      expect(merged[unitRelKey('s2', 'A')], isFalse);
    });

    test('rel 与 id 两种写法都必须认（服务端键是 rel，节点 id 可能带前缀）', () {
      final flags = mergeCrawlerFlags({
        's1': {'A/B': true},
      });
      final u = _unit('A/B', serverId: 's1');
      expect(unitHasCrawlerScript(flags, u), isTrue);
      final prefixed = UnitLibrary(
        node: LibNode(id: 'node:A/B', rel: 'A/B', name: 'B', serverId: 's1'),
        basics: const <BasicLib>[],
        children: const <UnitLibrary>[],
      );
      expect(unitHasCrawlerScript(flags, prefixed), isTrue);
    });

    test('反斜杠分隔的 rel 与开头的空段不影响判定', () {
      final flags = mergeCrawlerFlags({
        's1': {r'A\B': true},
      });
      expect(unitHasCrawlerScript(flags, _unit('/A//B/', serverId: 's1')), isTrue);
    });

    test('节点没带连接标识时用分节连接，绝不跨连接认领', () {
      final flags = mergeCrawlerFlags({
        's2': {'A': true},
      });
      final noSid = _unit('A');
      expect(unitHasCrawlerScript(flags, noSid, serverId: 's1'), isFalse);
      expect(unitHasCrawlerScript(flags, noSid, serverId: 's2'), isTrue);
    });

    test('空表 / 空 rel 一律 false（不猜）', () {
      expect(unitHasCrawlerScript(const {}, _unit('A')), isFalse);
      expect(unitHasCrawlerScript({'x': true}, _unit('')), isFalse);
    });
  });

  group('脚本目录只给绝对路径', () {
    test('有绝对路径时补 crawler 段，尾斜杠不重复', () {
      expect(crawlerScriptDir('/root/A'), '/root/A/crawler');
      expect(crawlerScriptDir('/root/A/'), '/root/A/crawler');
    });

    test('没有绝对路径时返回空串（不再回落相对路径）', () {
      expect(crawlerScriptDir(''), '');
      expect(crawlerScriptDir('   '), '');
    });

    test('页面的 _scriptDir 不再读 unit.rel', () {
      final body = _code('lib/unit_crawler_page.dart');
      expect(body.contains('String _scriptDir() => crawlerScriptDir(path)'),
          isTrue);
      expect(body.contains('path : widget.unit.rel'), isFalse,
          reason: '相对路径不得再作为脚本目录阖值');
      expect(body.contains('服务端未返回该目录的绝对路径'), isTrue);
    });
  });

  group('爬虫配置 / 维护检查页：地址与账号取记录自己的连接', () {
    test('记录带来源连接时，地址与鉴权都用它（绑定表为空也不串库）', () {
      final record = withServerOrigin({'id': 'lib-2'},
          id: 's2', base: 'http://other:8090', label: 'B', user: 'u', pass: 'p');
      expect(libraryBaseOf(record, 'http://default:8090'), 'http://other:8090');
      final headers = libraryHeadersOf(record, {'Authorization': 'Basic OLD'});
      expect(headers['Authorization'], isNot('Basic OLD'));
      expect(headers['Authorization'], basicAuthHeader('u', 'p'));
    });

    test('记录没有来源连接（旧数据/单连接）时回落到绑定表', () {
      final record = <String, dynamic>{'id': 'lib-1'};
      expect(libraryBaseOf(record, 'http://default:8090'), 'http://default:8090');
      expect(libraryHeadersOf(record, {'Authorization': 'Basic OLD'}),
          {'Authorization': 'Basic OLD'});
      expect(libraryBaseOf(null, 'http://d'), 'http://d');
    });

    test('两个页面都不再直接用 cfg 的地址/头', () {
      final body = _code('lib/main.dart');
      final crawler = body.substring(body.indexOf('class _CrawlerConfigPageState'),
          body.indexOf('class MaintenancePage'));
      final maint = body.substring(body.indexOf('class _MaintenancePageState'));
      for (final page in [crawler, maint]) {
        expect(page.contains('libraryBaseOf(widget.lib'), isTrue);
        expect(page.contains('libraryHeadersOf(widget.lib'), isTrue);
        expect(page.contains('headers: _headers'), isTrue);
        expect(page.contains('cfg.baseFor(libId), path, libId'), isFalse,
            reason: '地址必须优先取记录自己的连接');
      }
    });
  });

  group('页面只用唯一实现（不再自己分组/判定）', () {
    test('main 里不再有本地分组与两份脚本判定', () {
      final body = _code('lib/main.dart');
      expect(body.contains('_unitSections()'), isFalse);
      expect(body.contains('_topIdOfUnit'), isFalse);
      expect(body.contains('_unitHasScript'), isFalse);
      expect(body.contains('replaceFirst(\'node:\', \'\')'), isFalse,
          reason: '脚本键的剥前缀只有 unit_has 一处');
      expect(body.contains('crawlerSectionsOf('), isTrue);
      expect(body.contains('unitHasCrawlerScript('), isTrue);
    });

    test('页面按在线连接逐台取，不再只读默认库', () {
      final body = _code('lib/main.dart');
      final load = body.substring(
          body.indexOf('class _MediaCrawlerSettingsPageState'),
          body.indexOf('class CrawlerConfigPage'));
      expect(load.contains('liveServers('), isTrue);
      expect(load.contains('LibMeta.load(cfg.lib)'), isFalse,
          reason: '默认注册库那棵树看不到别的连接');
      expect(load.contains('libsByServer'), isTrue);
    });
  });
}
