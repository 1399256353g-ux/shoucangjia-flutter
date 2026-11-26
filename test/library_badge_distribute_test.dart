import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';

// P1 分发规则（owner 2026-11-27 改口径）：**任何单元库**设的色都会向下分发，
// 从直接上级逐级上行、第一个设过色的那层即分发源。
//
// 旧规则「只有末梢单元库分发、非末梢只作用本层」已经推翻，因此本文件不再
// 维护 `leafUnits` / `canDistribute` 那一套表——判定只看 `parentOfUnit` 链与
// 各层的自定义色。约定：全部判定只读树结构，不看任何目录名文本。

UnitLibrary _tree() {
  BasicLib b(String id) =>
      BasicLib(id: id, name: id, rel: id, bigId: '', authors: 0, works: 0);
  LibNode n(String rel) =>
      LibNode(id: rel, rel: rel, name: rel); // 名称只作结构占位，不参与判定

  final leaf = UnitLibrary(
    node: n('TOP/MID/LEAF'),
    basics: [b('basic-under-leaf')],
    children: const [],
  );
  final mid = UnitLibrary(
    node: n('TOP/MID'),
    basics: [b('basic-under-mid')],
    children: [leaf],
  );
  return UnitLibrary(
    node: const LibNode(id: 'secret', rel: '', name: 'SECRET'),
    basics: const [],
    children: [
      UnitLibrary(node: n('TOP'), basics: const [], children: [mid]),
    ],
  );
}

void main() {
  setUp(() {
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.topOfUnit.clear();
    LibraryBadge.parentOfUnit.clear();
    UnitBadgeRegistry.topOf.clear();
  });

  test('最下级单元库设色向下分发给它的基础库', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.parentOfUnit.addAll(parentOfUnitIds(root));

    LibraryBadge.custom['TOP/MID/LEAF'] = 0xFF00AA55;
    expect(LibraryBadge.basicColorFor('basic-under-leaf', 'TOP/MID/LEAF'),
        0xFF00AA55);
  });

  // owner 2026-11-27：「上级结构生成的词条要分发给下级啊，305 还没搞定」。
  //
  // 旧规则是「非末梢单元库设色只作用本层」，用户明确要求改成**逐级向下分发**：
  // 从直接上级开始一级级往上找第一个设过色的那层。这条测试因此反转。
  test('中间层单元库设色要分发给下级基础库（规则已改）', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.parentOfUnit.addAll(parentOfUnitIds(root));

    LibraryBadge.topCustom['TOP'] = 0xFF112233;
    // 中间层（有下级）设了一个很显眼的色
    LibraryBadge.custom['TOP/MID'] = 0xFFFF0000;

    // 本层词条用它自己的色
    expect(LibraryBadge.colorForUnit('TOP/MID'), 0xFFFF0000);
    // 它下面的基础库现在应该吃中间层这个色（而不是跳回顶级）
    expect(
        LibraryBadge.basicColorFor('basic-under-mid', 'TOP/MID'), 0xFFFF0000);
    // 更深的末级基础库同样逐级上行拿到最近的设色层
    expect(LibraryBadge.basicColorFor('basic-under-leaf', 'TOP/MID/LEAF'),
        0xFFFF0000);
  });

  test('基础库自己的自定义色仍然优先级最高（高于分发）', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.parentOfUnit.addAll(parentOfUnitIds(root));

    LibraryBadge.custom['TOP/MID/LEAF'] = 0xFF00AA55;
    LibraryBadge.basicCustom['basic-under-leaf'] = 0xFF778899;
    expect(LibraryBadge.basicColorFor('basic-under-leaf', 'TOP/MID/LEAF'),
        0xFF778899);
  });

  test('撤销单元库设色后，基础库回到顶级继承/自动，不残留', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.parentOfUnit.addAll(parentOfUnitIds(root));

    LibraryBadge.custom['TOP/MID/LEAF'] = 0xFF00AA55;
    expect(LibraryBadge.basicColorFor('basic-under-leaf', 'TOP/MID/LEAF'),
        0xFF00AA55);
    LibraryBadge.custom.remove('TOP/MID/LEAF');
    expect(LibraryBadge.basicColorFor('basic-under-leaf', 'TOP/MID/LEAF'),
        isNot(0xFF00AA55));
  });

  test('注册表 setFrom 刷新 topOf / parentOf，两者同源且无第三份表', () {
    final root = _tree();
    UnitBadgeRegistry.setFrom(root);
    expect(UnitBadgeRegistry.topOf['TOP/MID/LEAF'], 'TOP');
    expect(LibraryBadge.parentOfUnit['TOP/MID/LEAF'], 'TOP/MID');
    expect(LibraryBadge.parentOfUnit['TOP/MID'], 'TOP');
    expect(LibraryBadge.topOfUnit['TOP/MID'], 'TOP');
  });
}
