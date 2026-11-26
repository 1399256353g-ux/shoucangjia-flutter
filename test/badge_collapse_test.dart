import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_badge_row.dart';
import 'package:shoucangjia/library_badge.dart';

/// owner 2026-11-26：
/// > 「基础库词条的出现是配合文件夹挂载机制的，若在播放页作者卡等地方显示
/// >   过长可留一个小展开显示按键，平日里可把基础库等词条隐藏起来……
/// >   或者点媒体库词条显现所有下级词条也行」
/// > 「记住单元库词条还是最下级的单元库有生成资格，以前的规则不变」
///
/// 这组用例锁住三件事：
///  1. 常态只显示媒体库 + 单元库两级，基础库词条被收纳成一个小展开键
///  2. 点展开键能看到全部；点媒体库词条同样能展开（两种入口）
///  3. 只有基础库词条时不能被藏空
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  BadgeChipSpec chip(String label, LibEntryKind kind) =>
      BadgeChipSpec(label: label, color: 0xFF336699, kind: kind);

  group('折叠：基础库词条常态隐藏', () {
    testWidgets('三档齐全时，折叠态看不到基础库词条', (t) async {
      await t.pumpWidget(host(CollapsibleBadgeWrap(chips: [
        chip('媒体库A', LibEntryKind.top),
        chip('单元库B', LibEntryKind.unit),
        chip('基础库C', LibEntryKind.basic),
        chip('基础库D', LibEntryKind.basic),
      ])));

      // 媒体库、单元库常态可见。
      expect(find.text('媒体库A'), findsOneWidget);
      expect(find.text('单元库B'), findsOneWidget);
      // 基础库词条被收纳。
      expect(find.text('基础库C'), findsNothing);
      expect(find.text('基础库D'), findsNothing);
      // 末尾有展开键，且数字是「被藏起来的条数」。
      final expand = find.byKey(const ValueKey('badge-expand'));
      expect(expand, findsOneWidget);
      expect(find.descendant(of: expand, matching: find.text('2')),
          findsOneWidget);
    });

    testWidgets('展开键点开后，基础库词条全部出现', (t) async {
      await t.pumpWidget(host(CollapsibleBadgeWrap(chips: [
        chip('媒体库A', LibEntryKind.top),
        chip('单元库B', LibEntryKind.unit),
        chip('基础库C', LibEntryKind.basic),
      ])));
      await t.tap(find.byKey(const ValueKey('badge-expand')));
      await t.pumpAndSettle();

      expect(find.text('基础库C'), findsOneWidget);
      // 展开后不再需要展开键。
      expect(find.byKey(const ValueKey('badge-expand')), findsNothing);
    });

    testWidgets('点媒体库词条也能展开全部下级（第二种入口）', (t) async {
      await t.pumpWidget(host(CollapsibleBadgeWrap(chips: [
        chip('媒体库A', LibEntryKind.top),
        chip('基础库C', LibEntryKind.basic),
      ])));
      expect(find.text('基础库C'), findsNothing);
      await t.tap(find.text('媒体库A'));
      await t.pumpAndSettle();
      expect(find.text('基础库C'), findsOneWidget);
    });
  });

  group('边界：不能把卡片藏空', () {
    testWidgets('只有基础库词条时，折叠也要显示出来', (t) async {
      await t.pumpWidget(host(CollapsibleBadgeWrap(chips: [
        chip('基础库C', LibEntryKind.basic),
      ])));
      // 全藏起来会让卡片上什么都不显示——宁可显示也不留白。
      expect(find.text('基础库C'), findsOneWidget);
      expect(find.byKey(const ValueKey('badge-expand')), findsNothing);
    });

    testWidgets('没有基础库词条时不出展开键', (t) async {
      await t.pumpWidget(host(CollapsibleBadgeWrap(chips: [
        chip('媒体库A', LibEntryKind.top),
        chip('单元库B', LibEntryKind.unit),
      ])));
      expect(find.byKey(const ValueKey('badge-expand')), findsNothing);
    });

    testWidgets('空列表时占位为零尺寸', (t) async {
      await t.pumpWidget(host(const CollapsibleBadgeWrap(chips: [])));
      expect(find.byType(Wrap), findsNothing);
    });
  });

  group('规则不变：单元库词条仍由最下级单元库生成', () {
    test('entryKindOfUnit 仍按树结构判定，不因加了基础库词条而改变', () {
      LibraryBadge.topOfUnit.clear();
      LibraryBadge.leafUnits.clear();
      // 没有结构表时，任何库都不被认成媒体库（退回单元库档）。
      expect(LibraryBadge.entryKindOfUnit('某个单元库'), LibEntryKind.unit);
    });
  });
}
