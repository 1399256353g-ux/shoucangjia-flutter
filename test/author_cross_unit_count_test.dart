import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/unit_author_groups.dart';

/// owner 2026-11-26：
/// > 「跨单元库数量计算有问题啊，有个明明一个都没有跨，还显示跨了 2 个」
/// > 「什么叫跨单元库呢，跨过上面的直接单元库叫跨单元库，但跨库数量你是怎么
/// >   算的……这个计算规则都没讲清」
///
/// 实测确认的根因：作者文件分别落在 `A` 与 `A/B`（B 是 A 的下级）时，
/// 旧实现按「去重后的 rel 条数」算，得到 2 —— 但它一步都没走出 A。
///
/// 现在把规则写死并锁住：
///   **祖先被后代覆盖**：X 是 Y 的前缀时只算 Y；折叠后剩几个就是跨了几个。
void main() {
  AuthorMountItem item(String lib, String unitRel) => AuthorMountItem(
        lib: lib,
        authorDir: '@作者',
        unitRel: unitRel,
      );

  group('跨单元库计数：父子关系不得算成两处', () {
    test('A + A/B → 1 个（这是 owner 报的那个 bug）', () {
      final m = AuthorMounts(items: [item('lib-1', 'A'), item('lib-2', 'A/B')]);
      expect(m.units, hasLength(1));
      expect(m.sameUnitOnly, isTrue, reason: '一步都没走出 A，不该说跨库');
    });

    test('A/B + A/B/C → 1 个', () {
      final m = AuthorMounts(
          items: [item('lib-1', 'A/B'), item('lib-2', 'A/B/C')]);
      expect(m.units, hasLength(1));
    });

    test('A + A/B + A/B/C → 1 个（三级嵌套仍是一处）', () {
      final m = AuthorMounts(items: [
        item('lib-1', 'A'),
        item('lib-2', 'A/B'),
        item('lib-3', 'A/B/C'),
      ]);
      expect(m.units, hasLength(1));
    });
  });

  group('真的要跨库时才计数', () {
    test('A/B + A/C → 2 个（同一个父下的不同单元库）', () {
      final m =
          AuthorMounts(items: [item('lib-1', 'A/B'), item('lib-2', 'A/C')]);
      expect(m.units, hasLength(2));
      expect(m.sameUnitOnly, isFalse);
    });

    test('A + X → 2 个（两棵不同的子树）', () {
      final m = AuthorMounts(items: [item('lib-1', 'A'), item('lib-2', 'X')]);
      expect(m.units, hasLength(2));
    });

    test('A/B + X/Y → 2 个', () {
      final m =
          AuthorMounts(items: [item('lib-1', 'A/B'), item('lib-2', 'X/Y')]);
      expect(m.units, hasLength(2));
    });
  });

  group('边界：前缀只看段边界，不做字符串包含', () {
    test('A/BC 不是 A/B 的下级（不能被「以 A/B 开头」误判）', () {
      final m =
          AuthorMounts(items: [item('lib-1', 'A/B'), item('lib-2', 'A/BC')]);
      expect(m.units, hasLength(2),
          reason: 'A/BC 与 A/B 是两个不同目录，字符串前缀会误并成一个');
    });

    test('空 unitRel 不参与计数（没归属不算一个库）', () {
      final m = AuthorMounts(items: [
        item('lib-1', 'A'),
        item('lib-2', ''),
      ]);
      expect(m.units, hasLength(1));
      expect(m.sameUnitOnly, isTrue);
    });

    test('重复同一 rel 只算一次', () {
      final m = AuthorMounts(items: [
        item('lib-1', 'A/B'),
        item('lib-2', 'A/B'),
        item('lib-3', 'A/B'),
      ]);
      expect(m.units, hasLength(1));
    });
  });

  group('库数 ≠ 单元库数（两个口径分别保留）', () {
    test('同一单元库内两个基础库：libCount=2，units=1', () {
      final m = AuthorMounts(items: [
        item('lib-1', 'A/B'),
        item('lib-2', 'A/B'),
      ]);
      expect(m.libCount, 2, reason: '确实分布在两个基础库');
      expect(m.units, hasLength(1), reason: '但同属一个单元库');
      expect(m.sameUnitOnly, isTrue);
    });
  });
}
