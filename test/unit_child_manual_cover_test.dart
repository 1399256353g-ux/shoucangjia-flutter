import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/unit_library.dart';

/// owner 2026-11-28：
/// > 「看起来自动取下级单元库封面只能取到下级的自动封面，下级改成手动后
/// >   还是取的下级的自动封面」
///
/// 根因：`unit-covers.json` 里可以在**没被设为单元库**的目录上设手动封面。
/// 这类目录不生成卡片（owner 同日要求），因此不在树的节点里；上级遍历子树
/// 找不到它，只能落到下级自动封面。指针现在随所属节点的 `childCoverUrls`
/// 带进来。
void main() {
  UnitLibrary unit(String rel, {String cover = '', Map<String, String>? kids, List<UnitLibrary> children = const []}) =>
      UnitLibrary(
        node: LibNode(
          id: 'node:$rel',
          rel: rel,
          name: rel.split('/').last,
          coverUrl: cover,
          childCoverUrls: kids ?? const <String, String>{},
        ),
        basics: const <BasicLib>[],
        children: children,
      );

  test('下级节点自己的手动封面：上级自动封面能取到（既有行为）', () {
    final top = unit('A', children: [unit('A/B', cover: '/media/x/_cover/c.jpg')]);
    expect(top.firstManualCover, '/media/x/_cover/c.jpg');
  });

  test('下级是「非节点目录」的手动封面：上级也要能取到（本轮修复）', () {
    final top = unit('A', kids: const {
      'A/B/C': '/media/x/_cover/c2.jpg',
    });
    expect(top.firstManualCover, '/media/x/_cover/c2.jpg');
  });

  test('自己没有、子节点与别名都没有 → 空串（不编造）', () {
    expect(unit('A').firstManualCover, '');
  });

  test('自己设了手动封面时优先于别名', () {
    final top = unit('A',
        cover: '/media/x/_cover/self.jpg',
        kids: const {'A/B': '/media/x/_cover/kid.jpg'});
    expect(top.firstManualCover, '/media/x/_cover/self.jpg');
  });
}
