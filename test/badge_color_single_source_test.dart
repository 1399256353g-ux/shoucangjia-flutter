import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shoucangjia/library_badge.dart';

/// 0.9.265 第四十六批：词条「颜色来源」的四处口径缺口。
///
/// 0.9.264 加了来源选项（继承顶级 / 自动分配 / 自定义），但**取值链与文案
/// 仍各写多份**，于是三个选项之间存在互相串味：
///
///  1. 自动配色函数末尾转发给 `colorFor`，而 `colorFor` 第一步查自定义表
///     → 「来源=自动分配」照样返回残留自定义色；
///  2. 顶级单元库的自定义色存在另一张表 `topCustom`，`colorForUnit` 只查
///     `custom` → 顶级色要靠调用方再写一遍 `topColorFor(id) ?? …` 才显示；
///  3. `setSource` 清自定义色时只清 `custom` → 顶级切「自动分配」后旧色
///     留在 `topCustom`，下级继续继承那片旧色；
///  4. 设置页文案三处各写一遍，基础库那行退回 `own ? '自定义' : '继承'`
///     → 选了「自动分配」却显示「继承」。
///
/// 这组用例只锁这四条：同一个语义不许有第二份实现。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.colorSource.clear();
    LibraryBadge.basicSource.clear();
    LibraryBadge.topOfUnit.clear();
    LibraryBadge.leafUnits.clear();
    await LibraryBadge.load();
  });

  const topRed = 0xFFFF0000;
  const staleGreen = 0xFF00FF00;

  group('自动配色不得读用户自定义表', () {
    test('单元库：来源=自动 + 残留自定义色 → 返回调色板色，不是旧色', () {
      LibraryBadge.custom['lib-a'] = staleGreen;
      LibraryBadge.colorSource['lib-a'] = 'auto';

      final c = LibraryBadge.colorForUnit('lib-a', order: const ['lib-a']);
      expect(c, LibraryBadge.autoColorAt(0));
      expect(c, isNot(staleGreen),
          reason: '自动色能等于自定义色时，「来源」这个选项名存实亡');
    });

    test('残留自定义色写在另一种 id 形式（node: 前缀）也不生效', () {
      LibraryBadge.custom['node:lib-a'] = staleGreen;
      LibraryBadge.colorSource['lib-a'] = 'auto';
      expect(LibraryBadge.colorForUnit('lib-a', order: const ['lib-a']),
          LibraryBadge.autoColorAt(0));
      expect(LibraryBadge.colorForUnit('node:lib-a', order: const ['node:lib-a']),
          LibraryBadge.autoColorAt(0));
    });

    test('基础库：来源=自动 + 残留基础库自定义色 → 返回自动色', () {
      LibraryBadge.basicCustom['base-a'] = staleGreen;
      LibraryBadge.basicSource['base-a'] = 'auto';

      final c = LibraryBadge.basicColorFor('base-a', 'lib-a',
          order: const ['base-a']);
      expect(c, LibraryBadge.autoColorAt(0));
      expect(c, isNot(staleGreen));
    });

    test('基础库来源=自动：不会被上级单元库的残留自定义色染色', () {
      LibraryBadge.topOfUnit['base-a'] = 'node:lib-a';
      LibraryBadge.topOfUnit['lib-a'] = 'lib-a';
      LibraryBadge.custom['lib-a'] = staleGreen;
      LibraryBadge.basicSource['base-a'] = 'auto';

      expect(
        LibraryBadge.basicColorFor('base-a', 'lib-a', order: const ['lib-a']),
        isNot(staleGreen),
      );
    });
  });

  group('顶级单元库的自定义色只有一条读取链', () {
    test('来源=自定义 + topCustom 有值 → colorForUnit 直接给出该色', () {
      LibraryBadge.topOfUnit['node:T1'] = 'node:T1';
      LibraryBadge.topCustom['T1'] = topRed;
      LibraryBadge.colorSource['T1'] = 'custom';

      // 调用方不再需要 `topColorFor(id) ?? colorForUnit(id)`
      expect(LibraryBadge.colorForUnit('T1'), topRed);
      expect(LibraryBadge.colorForUnit('node:T1'), topRed);
    });

    test('来源=继承顶级（缺省）时，顶级自己的自定义色同样生效', () {
      LibraryBadge.topOfUnit['T1'] = 'T1';
      LibraryBadge.topCustom['T1'] = topRed;

      expect(LibraryBadge.colorForUnit('T1'), topRed);
    });

    test('顶级不能「继承自己」：没有自定义色时走自动配色', () {
      LibraryBadge.topOfUnit['T1'] = 'T1';
      expect(LibraryBadge.colorForUnit('T1', order: const ['T1']),
          LibraryBadge.autoColorAt(0));
    });
  });

  group('来源切走后，残留色必须真的清掉（含 topCustom）', () {
    test('顶级切「自动分配」：topCustom 被清，下级不再继承旧色', () async {
      LibraryBadge.topOfUnit['node:T1'] = 'node:T1';
      LibraryBadge.topOfUnit['C1'] = 'T1';
      LibraryBadge.topCustom['T1'] = topRed;

      await LibraryBadge.setSource('T1', BadgeColorSource.autoAssign);

      expect(LibraryBadge.topCustom['T1'], isNull,
          reason: '只清 custom 时 topCustom 里的旧色原样留着');
      expect(LibraryBadge.colorForUnit('T1'), isNot(topRed));
      expect(LibraryBadge.colorForUnit('C1'), isNot(topRed),
          reason: '下级不该继承一片用户已经放弃的颜色');
    });

    test('顶级切「继承顶级」同样清掉 topCustom', () async {
      LibraryBadge.topCustom['T1'] = topRed;
      await LibraryBadge.setSource('T1', BadgeColorSource.inheritTop);
      expect(LibraryBadge.topCustom['T1'], isNull);
    });

    test('切到「自定义」不清色（用户刚挑的颜色要留住）', () async {
      LibraryBadge.topCustom['T1'] = topRed;
      await LibraryBadge.setSource('T1', BadgeColorSource.fixedCustom);
      expect(LibraryBadge.topCustom['T1'], topRed);
    });

    test('结构表未加载（冷启动）时切来源也能清掉 topCustom', () async {
      // topOfUnit 为空：isTopSelf 判不出顶级，旧实现会跳过 topCustom
      LibraryBadge.topCustom['T9'] = topRed;
      await LibraryBadge.setSource('T9', BadgeColorSource.autoAssign);
      expect(LibraryBadge.topCustom['T9'], isNull);
    });
  });

  group('顶级选「自动分配」后：残留色不得再染给下级', () {
    test('手工配置留下的 topCustom 不生效（来源说自动就是自动）', () {
      LibraryBadge.topOfUnit['T1'] = 'T1';
      LibraryBadge.topOfUnit['C1'] = 'T1';
      LibraryBadge.topCustom['T1'] = topRed;
      LibraryBadge.colorSource['T1'] = 'auto';

      expect(LibraryBadge.topEntryColor('T1'), isNull);
      expect(LibraryBadge.colorForUnit('C1'), isNot(topRed));
    });

    test('来源回到「继承顶级」后残留色恢复生效（不清表也能读）', () {
      LibraryBadge.topOfUnit['T1'] = 'T1';
      LibraryBadge.topOfUnit['C1'] = 'T1';
      LibraryBadge.topCustom['T1'] = topRed;
      LibraryBadge.colorSource['T1'] = 'auto';
      expect(LibraryBadge.colorForUnit('C1'), isNot(topRed));

      LibraryBadge.colorSource['T1'] = 'inherit';
      expect(LibraryBadge.colorForUnit('C1'), topRed);
    });
  });

  group('文案与颜色同源（单一出口）', () {
    test('基础库选自动分配：文案是「自动分配」，不是「继承」', () {
      LibraryBadge.basicSource['base-a'] = 'auto';
      final label = LibraryBadge.sourceLabelOf(
        LibraryBadge.sourceForBasic('base-a'),
        hasOwn: LibraryBadge.hasOwnBasicColor('base-a'),
        inherits: false,
      );
      expect(label, '自动分配');
    });

    test('基础库真的继承到顶级色时：「继承顶级」', () {
      LibraryBadge.topOfUnit['lib-a'] = 'T1';
      LibraryBadge.topCustom['T1'] = topRed;
      final label = LibraryBadge.sourceLabelOf(
        LibraryBadge.sourceForBasic('base-a'),
        hasOwn: LibraryBadge.hasOwnBasicColor('base-a'),
        inherits: LibraryBadge.inheritsTopColor('lib-a'),
      );
      expect(label, '继承顶级');
    });

    test('来源=自定义但色被清掉：文案不得说「自定义」', () {
      LibraryBadge.colorSource['lib-a'] = 'custom';
      final label = LibraryBadge.sourceLabelOf(
        LibraryBadge.sourceFor('lib-a'),
        hasOwn: LibraryBadge.hasOwnColor('lib-a'),
        inherits: false,
      );
      expect(label, '自动分配');
    });

    test('来源=自动 + 有残留自定义色：hasOwnColor 必须为 false', () {
      LibraryBadge.custom['lib-a'] = staleGreen;
      LibraryBadge.colorSource['lib-a'] = 'auto';
      expect(LibraryBadge.hasOwnColor('lib-a'), isFalse,
          reason: '表里有色但来源是自动 → 界面不能报「自定义」');
    });

    test('顶级自定义色被 hasOwnColor 认到（另一张表）', () {
      LibraryBadge.topCustom['T1'] = topRed;
      expect(LibraryBadge.hasOwnColor('T1'), isTrue);
    });

    test('inheritsTopColor：自己就是顶级时永远 false', () {
      LibraryBadge.topOfUnit['T1'] = 'T1';
      LibraryBadge.topCustom['T1'] = topRed;
      expect(LibraryBadge.inheritsTopColor('T1'), isFalse);
    });
  });

  group('无归属库根（secret）恒为固定灰', () {
    test('secret 不参与自动配色', () {
      expect(LibraryBadge.colorForUnit('secret', order: const ['secret']),
          LibraryBadge.gray);
    });

    test('secret 有覆盖时用覆盖色', () {
      LibraryBadge.topCustom['secret'] = topRed;
      expect(LibraryBadge.colorForUnit('secret'), topRed);
    });
  });
}
