import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';

/// owner 2026-11-27：
/// > 「上级结构生成的词条要分发给下级啊，305 还没搞定」
///
/// 旧实现的分发链只有两种走法：末梢单元库分发 / 否则一下跳到媒体库根。
/// **中间层单元库**（有下级、自己也设了色）的色因此谁都拿不到——下级跳过它
/// 直达根。现在改成从直接上级逐级上行找第一个设过色的那层。
void main() {
  BasicLib basic(String id) => BasicLib(
      id: id, name: id, rel: id, bigId: '', authors: 1, works: 1);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.colorSource.clear();
    LibraryBadge.basicSource.clear();
    LibraryBadge.topOfUnit.clear();
    LibraryBadge.parentOfUnit.clear();
    LibraryBadge.leafUnits.clear();
    await LibraryBadge.load();
  });

  /// TOP ── MID ── LEAF 三级；basic 挂在 LEAF 下。
  UnitLibrary buildTree() {
    final leaf = UnitLibrary(
      node: const LibNode(id: 'LEAF', rel: 'TOP/MID/LEAF', name: 'LEAF'),
      basics: <BasicLib>[basic('lib-leaf')],
      children: const <UnitLibrary>[],
    );
    final mid = UnitLibrary(
      node: const LibNode(id: 'MID', rel: 'TOP/MID', name: 'MID'),
      basics: const <BasicLib>[],
      children: <UnitLibrary>[leaf],
    );
    final top = UnitLibrary(
      node: const LibNode(
          id: 'TOP', rel: 'TOP', name: 'TOP', serverId: 's1', serverBase: 'http://n'),
      basics: const <BasicLib>[],
      children: <UnitLibrary>[mid],
    );
    return UnitLibrary(
      node: const LibNode(
          id: 'media:s1', rel: '', name: 'NAS', serverId: 's1', serverBase: 'http://n'),
      basics: const <BasicLib>[],
      children: <UnitLibrary>[top],
    );
  }

  test('中间层单元库设色 → 末梢单元库能取到', () async {
    final root = buildTree();
    LibraryBadge.parentOfUnit.addAll(parentOfUnitIds(root));
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.leafUnits.addAll(leafUnitIds(root));

    const midColor = 0xFF123456;
    await LibraryBadge.setColor('MID', midColor);

    expect(LibraryBadge.colorForUnit('LEAF'), midColor,
        reason: '中间层设的色必须能分发给它的下级（这是 owner 报的那条）');
  });

  test('中间层设色 → 其下基础库也能取到', () async {
    final root = buildTree();
    LibraryBadge.parentOfUnit.addAll(parentOfUnitIds(root));
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.leafUnits.addAll(leafUnitIds(root));

    const midColor = 0xFF654321;
    await LibraryBadge.setColor('MID', midColor);
    expect(LibraryBadge.basicColorFor('lib-leaf', 'LEAF'), midColor);
  });

  test('下级自己也设了色 → 用自己的，不被上级覆盖', () async {
    final root = buildTree();
    LibraryBadge.parentOfUnit.addAll(parentOfUnitIds(root));
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.leafUnits.addAll(leafUnitIds(root));

    await LibraryBadge.setColor('MID', 0xFF111111);
    await LibraryBadge.setColor('LEAF', 0xFF999999);
    expect(LibraryBadge.colorForUnit('LEAF'), 0xFF999999);
  });

  test('中间层与媒体库根都设色 → 取最近的（中间层）', () async {
    final root = buildTree();
    LibraryBadge.parentOfUnit.addAll(parentOfUnitIds(root));
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.leafUnits.addAll(leafUnitIds(root));

    await LibraryBadge.setTopColor('media:s1', 0xFF0000AA);
    await LibraryBadge.setColor('MID', 0xFF00AA00);
    expect(LibraryBadge.colorForUnit('LEAF'), 0xFF00AA00,
        reason: '逐级上行的第一个设色层优先，不能跳过中间层直达根');
  });

  test('都没有设色 → 走自动配色（不抛、不为空）', () async {
    final root = buildTree();
    LibraryBadge.parentOfUnit.addAll(parentOfUnitIds(root));
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.leafUnits.addAll(leafUnitIds(root));
    expect(LibraryBadge.colorForUnit('LEAF'), isNotNull);
  });
}
