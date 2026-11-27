import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_badge.dart';

void main() {
  setUp(() => LibraryBadge.custom.clear());

  test('自动配色按库注册顺序分配且不同库不同色', () {
    final a = LibraryBadge.autoColorOf('douyin', order: ['douyin', 'second']);
    final b = LibraryBadge.autoColorOf('second', order: ['douyin', 'second']);
    expect(a, LibraryBadge.palette[0]);
    expect(b, LibraryBadge.palette[1]);
    expect(a, isNot(b));
  });

  test('来源=自定义时取本层色，切回自动后回到调色板', () async {
    final auto = LibraryBadge.autoColorOf('douyin', order: ['douyin']);
    await LibraryBadge.setSource('douyin', BadgeColorSource.fixedCustom);
    await LibraryBadge.setColor('douyin', 0xFF123456);
    expect(LibraryBadge.colorForUnit('douyin', order: ['douyin']), 0xFF123456);
    // 切回自动：本层自定义色被清掉，直接回调色板（不留残留色）。
    await LibraryBadge.setSource('douyin', BadgeColorSource.autoAssign);
    expect(LibraryBadge.colorForUnit('douyin', order: ['douyin']), auto);
    expect(LibraryBadge.custom.containsKey('douyin'), isFalse);
  });

  test('自动配色永不读自定义表（残留值不得冒充自动色）', () {
    // 0.9.346 删掉的 `colorFor` 第一步就查 custom：手工改过配置或从别的入口
    // 写过旧色时，用户选「自动分配」看到的仍是旧色。`autoColorOf` 必须无视它。
    final auto = LibraryBadge.autoColorOf('douyin', order: ['douyin']);
    LibraryBadge.custom['douyin'] = 0xFF123456;
    expect(LibraryBadge.autoColorOf('douyin', order: ['douyin']), auto);
    expect(LibraryBadge.colorForUnit('douyin', order: ['douyin']), auto,
        reason: '来源=继承/自动时不得落到残留自定义色');
    LibraryBadge.custom.remove('douyin');
  });

  test('未知库按 id 稳定散列，同一 id 颜色恒定', () {
    final c1 = LibraryBadge.autoColorOf('unknown-lib');
    final c2 = LibraryBadge.autoColorOf('unknown-lib', order: ['x', 'y']);
    expect(c1, c2);
    expect(LibraryBadge.palette, contains(c1));
  });

  test('词条文字颜色按底色亮度取黑或白', () {
    expect(LibraryBadge.textColorOn(0xFFFFFFFF), 0xFF111827);
    expect(LibraryBadge.textColorOn(0xFF000000), 0xFFFFFFFF);
    expect(LibraryBadge.textColorOn(0xFF2563EB), 0xFFFFFFFF);
  });

  test('词条折叠：最多两个，多余显示 +N，去重且忽略空 id', () {
    expect(LibraryBadge.labels(['a', 'b', 'c'], names: {'a': '抖音', 'b': '备份'}),
        ['抖音', '备份', '+1']);
    expect(LibraryBadge.labels(['a', 'a', '']), ['a']);
    expect(LibraryBadge.labels([]), isEmpty);
  });

  test('颜色设置解析容错并支持 #RRGGBB 文本', () {
    expect(LibraryBadge.parse('not json'), isEmpty);
    expect(LibraryBadge.parse('{"douyin": "#ff8800"}')['douyin'], 0xFFFF8800);
    expect(LibraryBadge.parse('{"douyin": 4278255360}')['douyin'], 4278255360);
    expect(LibraryBadge.parse('{"bad": "zzz"}').containsKey('bad'), false);
  });

  test('设置序列化可往返', () {
    final m = {'douyin': 0xFF112233, 'other': 0xFF445566};
    final raw = LibraryBadge.encode(source: m);
    expect(LibraryBadge.parse(raw), m);
  });

  test('单元库配色与 id 形式无关（node:rel 与 rel 同色）', () {
    final order = ['(1) A/(2) B', '(3) C'];
    final a = LibraryBadge.colorForUnit('node:(1) A/(2) B', order: order);
    final b = LibraryBadge.colorForUnit('(1) A/(2) B', order: order);
    expect(a, b);
    expect(a, LibraryBadge.palette[0]);
    expect(LibraryBadge.colorForUnit('secret'), LibraryBadge.gray);
  });

  test('单元库自定义颜色对两种 id 形式都生效', () {
    LibraryBadge.custom['node:(1) A'] = 0xFF123456;
    expect(LibraryBadge.colorForUnit('(1) A'), 0xFF123456);
    expect(LibraryBadge.colorForUnit('node:(1) A'), 0xFF123456);
  });

  group('词条变更信号（已渲染词条靠它即时生效）', () {
    test('改色 / 改外观 / 改 emoji 都递增', () async {
      final v0 = LibraryBadge.revision.value;
      await LibraryBadge.setColor('unit-a', 0xFF010203);
      final v1 = LibraryBadge.revision.value;
      expect(v1, greaterThan(v0));
      await LibraryBadge.setStyle(LibEntryKind.basic,
          const EntryStyle(borderWidth: 2, borderAlpha: 1, fillAlpha: 0.5));
      final v2 = LibraryBadge.revision.value;
      expect(v2, greaterThan(v1));
      await LibraryBadge.setEmoji('unit-a', '🔥');
      expect(LibraryBadge.revision.value, greaterThan(v2));
    });

    test('顶级继承色 / 基础库色 / 清除也递增', () async {
      var v = LibraryBadge.revision.value;
      await LibraryBadge.setTopColor('top-a', 0xFF112233);
      expect(LibraryBadge.revision.value, greaterThan(v));
      v = LibraryBadge.revision.value;
      await LibraryBadge.setBasicColor('basic-a', 0xFF445566);
      expect(LibraryBadge.revision.value, greaterThan(v));
      v = LibraryBadge.revision.value;
      await LibraryBadge.setTopColor('top-a', null);
      expect(LibraryBadge.revision.value, greaterThan(v));
    });

    test('重复写入同一个值不递增（避免无意义重建）', () async {
      await LibraryBadge.setColor('unit-b', 0xFF0A0B0C);
      final v = LibraryBadge.revision.value;
      await LibraryBadge.setColor('unit-b', 0xFF0A0B0C);
      await LibraryBadge.setEmoji('unit-b', '');
      await LibraryBadge.setStyle(
          LibEntryKind.top, LibraryBadge.styleFor(LibEntryKind.top));
      expect(LibraryBadge.revision.value, v);
    });
  });
}
