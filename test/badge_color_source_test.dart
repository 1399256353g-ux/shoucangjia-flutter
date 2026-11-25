import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shoucangjia/library_badge.dart';

/// owner 2026-11-25：
/// > 「还有默认为什么是继承顶级锁死，好歹给几个选项吧，比如自动分配颜色」
///
/// 原来的解析链写死成「自定义 → 继承顶级 → 自动」：清掉自定义色后第一步就
/// 落回继承顶级，顶级设过色就永远是同一个颜色——看起来就是「恢复自动没反应」。
///
/// 这组用例锁住三件事：
///  1. 来源可选，且缺省仍是继承顶级（不改变既有观感）；
///  2. 选「自动分配」时**不再**被顶级色盖住；
///  3. 「恢复自动」写入的来源是继承顶级，不是把当前色存成自定义。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.colorSource.clear();
    LibraryBadge.basicSource.clear();
    LibraryBadge.topOfUnit.clear();
    await LibraryBadge.load();
  });

  const topBlue = 0xFF1E88E5;
  const unitRed = 0xFFE53935;

  group('颜色来源：缺省行为不变', () {
    test('没记录来源时是「继承顶级」', () {
      expect(LibraryBadge.sourceFor('lib-001'), BadgeColorSource.inheritTop);
      expect(LibraryBadge.sourceForBasic('base-001'),
          BadgeColorSource.inheritTop);
    });

    test('空 id 不抛异常，回落继承顶级', () {
      expect(LibraryBadge.sourceFor(''), BadgeColorSource.inheritTop);
      expect(LibraryBadge.sourceForBasic(''), BadgeColorSource.inheritTop);
    });

    test('顶级设色 + 未设来源 → 继承顶级色（旧观感保持不变）', () {
      LibraryBadge.topOfUnit['lib-001'] = 'top-1';
      LibraryBadge.topCustom['top-1'] = topBlue;
      expect(
        LibraryBadge.colorForUnit('lib-001', order: const ['lib-001']),
        topBlue,
      );
    });
  });

  group('自动分配：不再被顶级色锁死', () {
    test('选自动分配后拿的是自动色，不是顶级色', () {
      LibraryBadge.topOfUnit['lib-001'] = 'top-1';
      LibraryBadge.topCustom['top-1'] = topBlue;
      LibraryBadge.colorSource['lib-001'] = 'auto';

      final c =
          LibraryBadge.colorForUnit('lib-001', order: const ['lib-001']);
      expect(c, isNot(topBlue),
          reason: '继承顶级是默认来源，不是唯一来源；选了自动就必须真的自动');
    });

    test('自动分配对同一个库稳定，不随调用次变化', () {
      LibraryBadge.colorSource['lib-001'] = 'auto';
      final a =
          LibraryBadge.colorForUnit('lib-001', order: const ['lib-001']);
      final b =
          LibraryBadge.colorForUnit('lib-001', order: const ['lib-001']);
      expect(a, b);
    });

    test('不同库在自动分配下拿到不同色（同屏可区分）', () {
      LibraryBadge.colorSource['lib-001'] = 'auto';
      LibraryBadge.colorSource['lib-002'] = 'auto';
      final a = LibraryBadge.colorForUnit('lib-001',
          order: const ['lib-001', 'lib-002']);
      final b = LibraryBadge.colorForUnit('lib-002',
          order: const ['lib-001', 'lib-002']);
      expect(a, isNot(b));
    });
  });

  group('自定义：仍按用户选的颜色', () {
    test('来源=自定义且设了色 → 用自定义色', () {
      LibraryBadge.topOfUnit['lib-001'] = 'top-1';
      LibraryBadge.topCustom['top-1'] = topBlue;
      LibraryBadge.colorSource['lib-001'] = 'custom';
      LibraryBadge.custom['lib-001'] = unitRed;

      expect(
        LibraryBadge.colorForUnit('lib-001', order: const ['lib-001']),
        unitRed,
      );
    });

    test('来源=自定义但色被清掉 → 回落自动配色，不留空壳状态', () {
      LibraryBadge.colorSource['lib-001'] = 'custom';
      final c =
          LibraryBadge.colorForUnit('lib-001', order: const ['lib-001']);
      expect(c, LibraryBadge.autoColorAt(0));
    });
  });

  group('setSource 写入语义', () {
    test('切到自动分配会清掉本层自定义色（否则看起来还是没变）', () async {
      LibraryBadge.custom['lib-001'] = unitRed;
      await LibraryBadge.setSource('lib-001', BadgeColorSource.autoAssign);

      expect(LibraryBadge.customColorFor('lib-001'), isNull);
      expect(LibraryBadge.sourceFor('lib-001'), BadgeColorSource.autoAssign);
    });

    test('切到继承顶级也会清掉本层自定义色', () async {
      LibraryBadge.custom['lib-001'] = unitRed;
      await LibraryBadge.setSource('lib-001', BadgeColorSource.inheritTop);

      expect(LibraryBadge.customColorFor('lib-001'), isNull);
      expect(LibraryBadge.sourceFor('lib-001'), BadgeColorSource.inheritTop);
    });

    test('切到自定义不会删掉已设的色', () async {
      LibraryBadge.custom['lib-001'] = unitRed;
      await LibraryBadge.setSource('lib-001', BadgeColorSource.fixedCustom);

      expect(LibraryBadge.customColorFor('lib-001'), unitRed);
      expect(LibraryBadge.sourceFor('lib-001'), BadgeColorSource.fixedCustom);
    });

    test('基础库来源走独立表，不与单元库串色', () async {
      await LibraryBadge.setSource('same-id', BadgeColorSource.autoAssign);
      expect(LibraryBadge.sourceForBasic('same-id'),
          BadgeColorSource.inheritTop,
          reason: '单元库与基础库同名字符串必须分开存');

      await LibraryBadge.setSource('same-id', BadgeColorSource.fixedCustom,
          basic: true);
      expect(LibraryBadge.sourceForBasic('same-id'),
          BadgeColorSource.fixedCustom);
      expect(LibraryBadge.sourceFor('same-id'), BadgeColorSource.autoAssign);
    });

    test('空 id 直接返回，不写脏数据', () async {
      await LibraryBadge.setSource('', BadgeColorSource.autoAssign);
      expect(LibraryBadge.colorSource.isEmpty, isTrue);
    });
  });

  group('基础库颜色也遵来源', () {
    test('基础库选自动分配时不被上级/顶级色盖住', () {
      LibraryBadge.topOfUnit['lib-001'] = 'top-1';
      LibraryBadge.topCustom['top-1'] = topBlue;
      LibraryBadge.basicSource['base-001'] = 'auto';

      final c = LibraryBadge.basicColorFor('base-001', 'lib-001',
          order: const ['lib-001']);
      expect(c, isNot(topBlue));
    });
  });

  group('持久化：来源要能存下来', () {
    test('setSource 之后重新 load 仍读得回来', () async {
      await LibraryBadge.setSource('lib-001', BadgeColorSource.autoAssign);
      await LibraryBadge.setSource('base-001', BadgeColorSource.fixedCustom,
          basic: true);

      // 模拟重启：清内存后重新 load
      LibraryBadge.colorSource.clear();
      LibraryBadge.basicSource.clear();
      await LibraryBadge.load();

      expect(LibraryBadge.sourceFor('lib-001'), BadgeColorSource.autoAssign);
      expect(LibraryBadge.sourceForBasic('base-001'),
          BadgeColorSource.fixedCustom);
    });

    test('坏数据不炸，回落继承顶级', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LibraryBadge.colorSourcePrefsKey: '{not-json',
      });
      LibraryBadge.colorSource.clear();
      await LibraryBadge.load();
      expect(LibraryBadge.sourceFor('lib-001'), BadgeColorSource.inheritTop);
    });

    test('未知取值不猜，回落继承顶级', () async {
      LibraryBadge.colorSource['lib-001'] = 'who-knows';
      expect(LibraryBadge.sourceFor('lib-001'), BadgeColorSource.inheritTop);
    });
  });
}
