import 'package:flutter/material.dart' show Border, BorderRadius, Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';

UnitLibrary _tree() {
  BasicLib b(String id, String name, String rel) =>
      BasicLib(id: id, name: name, rel: rel, bigId: '', authors: 0, works: 0);
  LibNode n(String rel) => LibNode(id: rel, rel: rel, name: rel);

  final deep = UnitLibrary(
    node: n('TOP/MID'),
    basics: [b('basic-deep', 'Deep', 'TOP/MID/Deep')],
    children: const [],
  );
  final mid = UnitLibrary(
    node: n('TOP'),
    basics: [b('basic-mid', 'Mid', 'TOP/Mid')],
    children: [deep],
  );
  final other = UnitLibrary(
    node: n('OTHER'),
    basics: [b('basic-other', 'Other', 'OTHER/Thing')],
    children: const [],
  );
  return UnitLibrary(
    node: const LibNode(id: 'secret', rel: '', name: 'SECRET'),
    basics: const [],
    children: [mid, other],
  );
}

void main() {
  setUp(() {
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.topOfUnit.clear();
  });

  test('顶级单元库色向下继承给其下单元库（结构表，不看名称文本）', () {
    final root = _tree();
    final topOf = topOfUnitIds(root);
    expect(topOf['TOP'], 'TOP');
    expect(topOf['TOP/MID'], 'TOP');
    expect(topOf['OTHER'], 'OTHER');
    // 根自身（SECRET）没有上级
    expect(topOf.containsKey('secret'), isFalse);

    LibraryBadge.topOfUnit.addAll(topOf);
    LibraryBadge.topCustom['TOP'] = 0xFF112233;

    // 未设自定义色的下级单元库继承顶级色
    expect(LibraryBadge.colorForUnit('TOP/MID'), 0xFF112233);
    // 另一个顶级单元库不受影响
    expect(LibraryBadge.colorForUnit('OTHER'), isNot(0xFF112233));
  });

  test('单元库自定义色优先于继承色', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.topCustom['TOP'] = 0xFF112233;
    LibraryBadge.custom['TOP/MID'] = 0xFFAABBCC;
    expect(LibraryBadge.colorForUnit('TOP/MID'), 0xFFAABBCC);
    expect(LibraryBadge.colorForUnit('node:TOP/MID'), 0xFFAABBCC);
  });

  test('基础库自定义色优先级最高：本库 > 单元库 > 顶级 > 自动', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.topCustom['TOP'] = 0xFF112233;

    // 只有继承
    expect(LibraryBadge.basicColorFor('basic-deep', 'TOP/MID'), 0xFF112233);
    // 单元库自定义
    LibraryBadge.custom['TOP/MID'] = 0xFF445566;
    expect(LibraryBadge.basicColorFor('basic-deep', 'TOP/MID'), 0xFF445566);
    // 基础库自定义最高
    LibraryBadge.basicCustom['basic-deep'] = 0xFF778899;
    expect(LibraryBadge.basicColorFor('basic-deep', 'TOP/MID'), 0xFF778899);
  });

  test('撤销顶级色后回到自动配色（不残留继承）', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    LibraryBadge.topCustom['TOP'] = 0xFF112233;
    expect(LibraryBadge.colorForUnit('TOP/MID'), 0xFF112233);
    LibraryBadge.topCustom.remove('TOP');
    // 撤销后不再继承，回到自动配色（TOP/MID 不在 order 里 → id 稳定散列）
    expect(LibraryBadge.colorForUnit('TOP/MID'),
        LibraryBadge.colorFor('TOP/MID'));
  });

  test('词条层级判定：顶级 / 单元库 / 其它', () {
    final root = _tree();
    LibraryBadge.topOfUnit.addAll(topOfUnitIds(root));
    expect(LibraryBadge.entryKindOfUnit('TOP'), LibEntryKind.top);
    expect(LibraryBadge.entryKindOfUnit('TOP/MID'), LibEntryKind.unit);
    expect(LibraryBadge.entryKindOfUnit('OTHER'), LibEntryKind.top);
    expect(LibraryBadge.entryKindOfUnit('secret'), LibEntryKind.other);
    expect(LibraryBadge.entryKindOfUnit(''), LibEntryKind.other);
    expect(LibraryBadge.entryKindOfUnit('未知库'), LibEntryKind.other);
  });

  test('四层级词条外观：圆角与内边距一致，只有边框/底纹不同', () {
    final kinds = LibEntryKind.values;
    final decos = [
      for (final k in kinds) LibraryBadge.decorationFor(k, 0xFF336699)
    ];
    // 圆角完全一致（形状一致）
    final radii = {
      for (final d in decos) (d.borderRadius as BorderRadius).topLeft.x
    };
    expect(radii.length, 1);
    // 边框宽度两两不同（顶级最粗、基础库最细）
    final widths = [for (final d in decos) (d.border as Border).top.width];
    expect(widths[0] > widths[1], isTrue);
    expect(widths[1] > widths[2], isTrue);
    // 底纹透明度各不相同
    final alphas = {
      for (final d in decos) (d.color as Color).a
    };
    expect(alphas.length, kinds.length);
  });
}
