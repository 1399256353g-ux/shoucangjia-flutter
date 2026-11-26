import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';

/// owner 2026-11-26：
/// > 「不是所有的单元库自动封面都有效，有些虽然选了自动但不会自动取优先级高
/// >   的下级单元库封面，也可能是下级单元库改为手动封面了但上级单元库取不到」
///
/// 根因：自动封面链只看「本机播放量最高的作品」，从不看下级单元库设过的
/// 手动封面。于是「下级设手动、上级选自动」时上级显示一张无关作品图或空白。
///
/// 修法：`firstManualCover` / `firstManualCoverUnit` 按树序向下找第一个设过
/// 手动封面（`node.coverUrl`）的单元库。**只读指针，不动任何目录**。
void main() {
  BasicLib basic(String id) => BasicLib(
      id: id, name: id, rel: id, bigId: '', authors: 1, works: 1);

  UnitLibrary unit(String id, String rel,
          {String coverUrl = '', List<UnitLibrary> children = const []}) =>
      UnitLibrary(
        node: LibNode(
            id: id, rel: rel, name: id, coverUrl: coverUrl, serverBase: 'http://nas:8090'),
        basics: <BasicLib>[basic('lib-$id')],
        children: children,
      );

  group('firstManualCover：向下找第一个手动封面', () {
    test('自己设了就用自己', () {
      final u = unit('A', 'A', coverUrl: '/media/lib-A/_cover/a.jpg');
      expect(u.firstManualCover, '/media/lib-A/_cover/a.jpg');
      expect(u.firstManualCoverUnit?.id, 'A');
    });

    test('自己没设、下级设了 → 取下级（owner 报的那个场景）', () {
      final child = unit('B', 'A/B', coverUrl: '/media/lib-B/_cover/b.jpg');
      final parent = unit('A', 'A', children: <UnitLibrary>[child]);
      expect(parent.firstManualCover, '/media/lib-B/_cover/b.jpg');
      expect(parent.firstManualCoverUnit?.id, 'B',
          reason: '还要能拿到那个节点，跨连接时要借它的 base 拼地址');
    });

    test('三级嵌套：取最近的一个有手动封面的', () {
      final leaf = unit('C', 'A/B/C', coverUrl: '/media/lib-C/_cover/c.jpg');
      final mid = unit('B', 'A/B', children: <UnitLibrary>[leaf]);
      final top = unit('A', 'A', children: <UnitLibrary>[mid]);
      expect(top.firstManualCover, '/media/lib-C/_cover/c.jpg');
    });

    test('都没有时为空串（交给自动链兜底）', () {
      final child = unit('B', 'A/B');
      final parent = unit('A', 'A', children: <UnitLibrary>[child]);
      expect(parent.firstManualCover, '');
      expect(parent.firstManualCoverUnit, isNull);
    });

    test('自己与下级都有时，优先自己', () {
      final child = unit('B', 'A/B', coverUrl: '/media/lib-B/_cover/b.jpg');
      final parent = unit('A', 'A',
          coverUrl: '/media/lib-A/_cover/a.jpg',
          children: <UnitLibrary>[child]);
      expect(parent.firstManualCover, '/media/lib-A/_cover/a.jpg');
    });
  });
}
