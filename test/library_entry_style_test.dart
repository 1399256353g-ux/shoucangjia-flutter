import 'package:flutter/material.dart' show Border, BorderRadius, Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/library_badge.dart';

// P1 剩余：四层级词条的**边框 / 底纹**可自定义，但形状与尺寸必须保持一致。
// 这里只断言结构与数值，不涉及任何 UI 截图或目录名文本。

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LibraryBadge.load();
  });

  test('默认外观：三层级圆角一致，边框与底纹逐级递减', () {
    final decos = [
      for (final k in LibEntryKind.values) LibraryBadge.decorationFor(k, 0xFF336699)
    ];
    // 圆角必须完全一致（形状硬约束）
    final radii = {
      for (final d in decos) (d.borderRadius as BorderRadius).topLeft.x
    };
    expect(radii.length, 1);
    expect(radii.first, kEntryRadius);

    // 边框画在 decoration 里（与原始实现同路径）。
    final widths = [
      for (final d in decos) (d.border as Border).top.width
    ];
    expect(widths[0] > widths[1], isTrue); // 媒体库 > 单元库
    expect(widths[1] > widths[2], isTrue); // 单元库 > 基础库
    // owner 2026-11-26：边框颜色可调，默认三档颜色也要不同。
    final colors = [
      for (final d in decos) (d.border as Border).top.color
    ];
    expect(colors.toSet().length, greaterThan(1),
        reason: '三种词条的边框颜色应能区分，不能全一样');
  });

  test('改边框粗细只影响该层级，且不改圆角', () {
    final topWidthBefore = LibraryBadge.styleFor(LibEntryKind.top).borderWidth;
    LibraryBadge.entryStyle[LibEntryKind.unit] =
        LibraryBadge.styleFor(LibEntryKind.unit).copyWith(borderWidth: 2.4);
    final after = LibraryBadge.decorationFor(LibEntryKind.unit, 0xFF336699);

    expect((after.border as Border).top.width, closeTo(2.4, 1e-9));
    expect((after.borderRadius as BorderRadius).topLeft.x, kEntryRadius);
    // 其它层级不受影响
    final topDeco = LibraryBadge.decorationFor(LibEntryKind.top, 0xFF336699);
    expect((topDeco.border as Border).top.width,
        closeTo(topWidthBefore, 1e-9));
  });

  test('底纹浓度可调，且被限制在 0–1', () {
    LibraryBadge.entryStyle[LibEntryKind.basic] = LibraryBadge
        .styleFor(LibEntryKind.basic)
        .copyWith(fillAlpha: 5.0); // 越界输入
    expect(LibraryBadge.styleFor(LibEntryKind.basic).fillAlpha, 1.0);
    final deco =
        LibraryBadge.decorationFor(LibEntryKind.basic, 0xFF336699);
    expect((deco.color as Color).a, closeTo(1.0, 1e-6));
  });

  test('边框粗细越界同样被夹紧到 0–3', () {
    const st = EntryStyle(borderWidth: 9, borderAlpha: -1, fillAlpha: -2);
    final clamped = EntryStyle.fromJson(<String, dynamic>{'w': 99, 'ba': 9, 'fa': -3},
        kDefaultEntryStyle[LibEntryKind.top]!);
    expect(clamped.borderWidth, 3.0);
    expect(clamped.borderAlpha, 1.0);
    expect(clamped.fillAlpha, 0.0);
    expect(st.copyWith().borderWidth, 3.0);
    expect(st.copyWith().borderAlpha, 0.0);
    // 直接写进映射（绕过 copyWith）也不会出现负边宽
    LibraryBadge.entryStyle[LibEntryKind.unit] = const EntryStyle(
        borderWidth: -4, borderAlpha: 2, fillAlpha: -1);
    expect(LibraryBadge.styleFor(LibEntryKind.unit).borderWidth, 0.0);
    expect(LibraryBadge.styleFor(LibEntryKind.unit).borderAlpha, 1.0);
    expect(LibraryBadge.styleFor(LibEntryKind.unit).fillAlpha, 0.0);
  });

  test('保存后重新 load 能读回自定义外观', () async {
    await LibraryBadge.setStyle(LibEntryKind.top,
        const EntryStyle(borderWidth: 2.0, borderAlpha: 0.5, fillAlpha: 0.7));
    await LibraryBadge.load();
    final st = LibraryBadge.styleFor(LibEntryKind.top);
    expect(st.borderWidth, closeTo(2.0, 1e-9));
    expect(st.borderAlpha, closeTo(0.5, 1e-9));
    expect(st.fillAlpha, closeTo(0.7, 1e-9));
    expect(LibraryBadge.isStyleCustom(LibEntryKind.top), isTrue);
  });

  test('恢复默认只影响该层级', () async {
    await LibraryBadge.setStyle(LibEntryKind.top,
        const EntryStyle(borderWidth: 2.0, borderAlpha: 0.5, fillAlpha: 0.7));
    await LibraryBadge.setStyle(LibEntryKind.basic,
        const EntryStyle(borderWidth: 0.2, borderAlpha: 0.9, fillAlpha: 0.3));
    await LibraryBadge.resetStyle(LibEntryKind.top);
    expect(LibraryBadge.styleFor(LibEntryKind.top),
        kDefaultEntryStyle[LibEntryKind.top]);
    expect(LibraryBadge.isStyleCustom(LibEntryKind.top), isFalse);
    expect(LibraryBadge.isStyleCustom(LibEntryKind.basic), isTrue);
  });

  test('坏数据不阻断启动：缺失/非法层级回落默认', () {
    LibraryBadge.applyStyleJson(<String, dynamic>{
      'top': <String, dynamic>{'w': 'x', 'ba': null},
      'unit': 42,
    });
    for (final k in LibEntryKind.values) {
      expect(LibraryBadge.styleFor(k), kDefaultEntryStyle[k]);
    }
  });

  test('形状尺寸常量没有可调入口：圆角固定 6', () {
    // 任何层级无论怎么改，圆角都取常量 kEntryRadius。
    for (final k in LibEntryKind.values) {
      LibraryBadge.entryStyle[k] = const EntryStyle(
          borderWidth: 3, borderAlpha: 1, fillAlpha: 0.1);
      final d = LibraryBadge.decorationFor(k, 0xFF112233);
      expect((d.borderRadius as BorderRadius).topLeft.x, kEntryRadius);
    }
  });
}
