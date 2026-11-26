import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';

// P1 分发规则：只有**末梢单元库**的词条向下分发给基础库/作品/作者；
// 非末梢单元库的设色只作用于本层，不参与分发冲突。
// 约定：全部判定只读树结构（children 是否为空），不看任何目录名文本。

UnitLibrary _tree() {
  BasicLib b(String id) => BasicLib(
      id: id, name: id, rel: id, bigId: '', authors: 0, works: 0);
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
      UnitLibrary(
          node: n('TOP'), basics: const [], children: [mid]),
    ],
  );
}

void main() {
  setUp(() {
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.topOfUnit.clear();
    LibraryBadge.leafUnits.clear();
    UnitBadgeRegistry.topOf.clear();
    UnitBadgeRegistry.leaf.clear();
  });

  test('末梢判定只看结构：没有下级单元库才是末梢', () {
    final leafMap = leafUnitIds(_tree());
    expect(leafMap['TOP'], isFalse);
    expect(leafMap['TOP/MID'], isFalse);
    expect(leafMap['TOP/MID/LEAF'], isTrue);
    // `node:` 两种 id 形式都登记，查询端不必归一
    expect(leafMap['node:TOP/MID'], isFalse);
    expect(leafMap['node:TOP/MID/LEAF'], isTrue);
    // 根 SECRET 不在表里（它不是任何连接的媒体库根）
    expect(leafMap.containsKey('secret'), isFalse);
  });

  test('末梢单元库设色向下分发给它的基础库', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.leafUnits.addAll(leafUnitIds(root));

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
    LibraryBadge.leafUnits.addAll(leafUnitIds(root));

    LibraryBadge.topCustom['TOP'] = 0xFF112233;
    // 中间层（非末梢）设了一个很显眼的色
    LibraryBadge.custom['TOP/MID'] = 0xFFFF0000;

    // 本层词条用它自己的色
    expect(LibraryBadge.colorForUnit('TOP/MID'), 0xFFFF0000);
    // 它下面的基础库现在应该吃中间层这个色（而不是跳回顶级）
    expect(LibraryBadge.basicColorFor('basic-under-mid', 'TOP/MID'),
        0xFFFF0000);
    // 更深的末梢基础库同样逐级上行拿到最近的设色层
    expect(LibraryBadge.basicColorFor('basic-under-leaf', 'TOP/MID/LEAF'),
        0xFFFF0000);
  });

  test('基础库自己的自定义色仍然优先级最高（高于末梢分发）', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.leafUnits.addAll(leafUnitIds(root));

    LibraryBadge.custom['TOP/MID/LEAF'] = 0xFF00AA55;
    LibraryBadge.basicCustom['basic-under-leaf'] = 0xFF778899;
    expect(LibraryBadge.basicColorFor('basic-under-leaf', 'TOP/MID/LEAF'),
        0xFF778899);
  });

  test('撤销末梢单元库设色后，基础库回到顶级继承/自动，不残留', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.leafUnits.addAll(leafUnitIds(root));

    LibraryBadge.custom['TOP/MID/LEAF'] = 0xFF00AA55;
    expect(LibraryBadge.basicColorFor('basic-under-leaf', 'TOP/MID/LEAF'),
        0xFF00AA55);
    LibraryBadge.custom.remove('TOP/MID/LEAF');
    expect(LibraryBadge.basicColorFor('basic-under-leaf', 'TOP/MID/LEAF'),
        isNot(0xFF00AA55));
  });

  test('结构未加载时不阻断（冷启动不退化成自动色）', () {
    // 注册表为空：canDistribute 返回 true，避免启动阶段把所有库判成非末梢
    expect(LibraryBadge.canDistribute('任意单元库'), isTrue);
    expect(LibraryBadge.canDistribute(''), isFalse);
  });

  test('注册表 setFrom 同时刷新 topOf 与 leaf，两者同源', () {
    final root = _tree();
    UnitBadgeRegistry.setFrom(root);
    expect(UnitBadgeRegistry.topOf['TOP/MID/LEAF'], 'TOP');
    expect(UnitBadgeRegistry.leaf['TOP/MID/LEAF'], isTrue);
    expect(UnitBadgeRegistry.leaf['TOP/MID'], isFalse);
    expect(LibraryBadge.leafUnits['TOP/MID'], isFalse);
    expect(LibraryBadge.topOfUnit['TOP/MID'], 'TOP');
  });
}
