import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';
import 'package:shoucangjia/cover_admin.dart';

void main() {
  group('coverUrlOf / libOfMediaPath', () {
    test('节点 cover.u 是唯一认的单元库封面写法', () {
      expect(coverUrlOf({'u': '/media/lib-008/a/b.jpg'}), '/media/lib-008/a/b.jpg');
      expect(coverUrlOf({'url': ' /media/lib-001/x.png '}), '/media/lib-001/x.png');
    });

    test('非媒体路径、旧版字符串指针都不当单元库封面', () {
      expect(coverUrlOf({'u': 'lib-008/a.jpg'}), '');
      expect(coverUrlOf({'u': ''}), '');
      expect(coverUrlOf({'v': 'v1', 'e': 'jpg'}), '');
      expect(coverUrlOf('v1.jpg'), '');
      expect(coverUrlOf(null), '');
    });

    test('媒体路径取库 id，用于路由到对应服务器', () {
      expect(libOfMediaPath('/media/lib-008/a/b.jpg'), 'lib-008');
      expect(libOfMediaPath(' /media/lib-001/x.png '), 'lib-001');
      expect(libOfMediaPath('/api/thumb/a'), '');
      expect(libOfMediaPath('/media/'), '');
      expect(libOfMediaPath('/media/lib-008'), '');
    });
  });

  group('节点解析与卡片取图', () {
    test('nodesFromMarks 把 cover.u 带进 LibNode.coverUrl', () {
      // owner 2026-11-28：手动模式的节点只来自 `/api/nodes`（`nodesFromMarks`），
      // 不再读 `libraries.json` 的 `nodes`（旧自动节点残留会把未勾选的目录
      // 变成卡片）。因此“节点带封面”的契约改在这里验。
      final nodes = nodesFromMarks(
        const ['(1) A', '(2) B'],
        covers: const {
          '(1) A': '/media/lib-008/a/cover.jpg',
        },
        serverBase: 'http://nas:8090',
        serverId: 's1',
      );
      expect(nodes.first.coverUrl, '/media/lib-008/a/cover.jpg');
      expect(nodes.last.coverUrl, '');
    });

    test('nodesFromV2 手动模式不再从 json.nodes 造节点', () {
      final json = {
        'nodesMode': 'manual',
        'nodes': [
          {'id': 'nd-001', 'rel': '(1) A', 'name': '(1) A'},
        ],
        'bigLibraries': <dynamic>[],
        'groups': <dynamic>[],
      };
      expect(nodesFromV2(json), isEmpty);
    });

    test('没有播放记录时，手动单元库封面仍优先于空自动封面', () {
      const unit = UnitLibrary(
        node: LibNode(
          id: 'u1',
          rel: '(1) A',
          name: '(1) A',
          coverUrl: '/media/lib-008/a/cover.jpg',
          serverBase: 'http://192.168.2.4:8090/',
        ),
        basics: <BasicLib>[],
        children: <UnitLibrary>[],
      );
      expect(unitCoverUrl(unit), 'http://192.168.2.4:8090/media/lib-008/a/cover.jpg');
    });

    test('调用方解析好的地址依然最优先', () {
      const unit = UnitLibrary(
        node: LibNode(
          id: 'u1',
          rel: '(1) A',
          name: '(1) A',
          coverUrl: '/media/lib-008/a/cover.jpg',
          serverBase: 'http://192.168.2.4:8090',
        ),
        basics: <BasicLib>[],
        children: <UnitLibrary>[],
      );
      expect(unitCoverUrl(unit, customUrl: 'http://x/custom.jpg'),
          'http://x/custom.jpg');
    });
  });

  group('手动节点模式（/api/nodes）下的单元库封面', () {
    test('nodes 字符串列表 + covers 映射 → 节点带 coverUrl 与 serverBase', () {
      final nodes = nodesFromMarks(
        const ['(1) A', '(1) A/(2) B', '(3) C'],
        covers: const {
          '(1) A': '/media/lib-008/a/cover.jpg',
          '(3) C': 'lib-009/x.jpg',
        },
        serverBase: 'http://192.168.2.4:8090/',
      );
      expect(nodes.map((n) => n.rel),
          ['(1) A', '(1) A/(2) B', '(3) C']);
      expect(nodes[0].coverUrl, '/media/lib-008/a/cover.jpg');
      expect(nodes[0].serverBase, 'http://192.168.2.4:8090/');
      // 没设过封面 / 非媒体路径 → 不当封面，避免半截地址被请求。
      expect(nodes[1].coverUrl, '');
      expect(nodes[2].coverUrl, '');
    });

    test('不带 covers 时与旧行为一致（全部空封面）', () {
      final nodes = nodesFromMarks(const ['(1) A', '(2) B']);
      expect(nodes.length, 2);
      expect(nodes.every((n) => n.coverUrl.isEmpty), isTrue);
      expect(nodes.every((n) => n.serverBase.isEmpty), isTrue);
    });

    test('手动模式节点经 buildUnitTree 后，自定义封面仍优先于自动封面', () {
      final tree = buildUnitTree(
        nodes: nodesFromMarks(
          const ['(1) A'],
          covers: const {'(1) A': '/media/lib-008/a/cover.jpg'},
          serverBase: 'http://192.168.2.4:8090',
        ),
        basics: const [
          BasicLib(
              id: 'l1',
              name: 'A',
              rel: '(1) A/a',
              bigId: '',
              authors: 1,
              works: 2,
              serverBase: 'http://192.168.2.4:8090'),
        ],
      )!;
      final unit = tree.children.first;
      expect(unitCoverUrl(unit),
          'http://192.168.2.4:8090/media/lib-008/a/cover.jpg');
    });
  });

  group('单元库封面请求', () {
    test('设置走 /api/cover/unit，请求体与基础库同形', () {
      const r = CoverRequest.set(
          scope: CoverScope.unit, lib: 'lib-008', work: '7401');
      expect(r.scope.path, '/api/cover/unit');
      expect(r.toBody(), {'lib': 'lib-008', 'work': '7401'});
      expect(r.doneText, contains('单元库'));
    });

    test('清除只带 clear 标记，文案区分单元库', () {
      const r = CoverRequest.clear(lib: 'lib-008', scope: CoverScope.unit);
      expect(r.toBody(), {'lib': 'lib-008', 'clear': true});
      expect(r.doneText, contains('已清除该单元库封面'));
      expect(r.failText, '清除单元库封面失败');
    });

    test('默认仍是基础库封面，旧行为不变', () {
      const r = CoverRequest.set(lib: 'lib-001', work: '7401');
      expect(r.scope, CoverScope.basic);
      expect(r.scope.path, '/api/cover/set');
      expect(r.doneText, contains('已设为该库封面'));
      expect(r.failText, '设置封面失败');
    });
  });
}
