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
    test('nodesFromV2 把 cover.u 带进 LibNode.coverUrl', () {
      final json = {
        'nodesMode': 'manual',
        'nodes': [
          {
            'id': 'nd-001',
            'rel': '(1) A',
            'name': '(1) A',
            'cover': {'u': '/media/lib-008/a/cover.jpg', 'at': 1700000000},
          },
          {'id': 'nd-002', 'rel': '(2) B', 'name': '(2) B', 'cover': {'v': 'v3'}},
        ],
        'bigLibraries': <dynamic>[],
        'groups': <dynamic>[],
      };
      final nodes = nodesFromV2(json);
      expect(nodes.first.coverUrl, '/media/lib-008/a/cover.jpg');
      expect(nodes.first.coverVersion, '');
      expect(nodes.last.coverUrl, '');
      expect(nodes.last.coverVersion, 'v3');
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
