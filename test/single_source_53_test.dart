/// 第七十五批契约（0.9.303）：**同一条判定被写在四个调用点上**。
///
/// 前几批抓过「同一数字两份」「同一模型两份」「参数名同、含义不同」。
/// 这一批抓的是最小也最隐蔽的一类：**判定本身很短、短到每个调用点都
/// 愿意自己写一遍**。
///
/// ```
/// letters.length > 1                   ← 索引条是否可见，写了 4 遍
/// iconSize: 18 + tightFor(30, 30)      ← 卡片操作按钮规格，写了 4 遍
/// width: 84 + height: 84 + 44 + 16     ← 字母浮层尺寸，写了 2 遍（宽高各一）
/// ```
///
/// 每一处都「自己算得出正确答案」，所以不报错、没有第二个实现可对比、
/// 界面上也看不出错。只有把两个调用点摆在一起才看得出它们描述的是同一件事。
/// 这类代码的代价不是当下，而是下一次有人只改其中一处：
///
///  - 索引条门槛改了一处 → 条带画出来但网格没让位，最后一列被压住、点击被抢；
///  - 按钮规格改了一处 → 同一排按钮里一个更小，点击热区跟着变；
///  - 浮层尺寸改了一处 → 方块变长条，或字号溢出方块。
library;

import 'dart:io';

import 'package:flutter/material.dart'
    show
        Center,
        Icons,
        IconButton,
        MaterialApp,
        ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_index.dart';
import 'package:shoucangjia/author_letter_bar.dart';
import 'package:shoucangjia/card_action_button.dart';

String _src(String name) => File('lib/$name').readAsStringSync();

void main() {
  group('索引条可见性只有一处判定', () {
    test('authorIndexBarVisible：≥2 个字母才显示', () {
      expect(authorIndexBarVisible(const []), isFalse);
      expect(authorIndexBarVisible(const ['A']), isFalse,
          reason: '一个字母点了也不移动，不该占右侧 34dp');
      expect(authorIndexBarVisible(const ['A', 'B']), isTrue);
      expect(authorIndexBarVisible(const ['A', '#']), isTrue);
    });

    test('基础库页不再自己写 letters.length > 1', () {
      final src = _src('basic_lib_page.dart');
      expect(src.contains('.length > 1'), isFalse,
          reason: '索引条门槛又写回调用点了：四处各判一次必然有一处改漏');
      expect('authorIndexBarVisible('.allMatches(src).length, greaterThanOrEqualTo(2),
          reason: '网格点与预热点都应读这一个出口');
    });

    test('索引条宽度只有一个数字：28 不再出现在页面与浮层里', () {
      final page = _src('basic_lib_page.dart');
      expect(page.contains('width: 28'), isFalse,
          reason: '条带宽度应读 kAuthorIndexBarWidth');
      final bar = _src('author_letter_bar.dart');
      expect(bar.contains('this.width = 28'), isFalse,
          reason: '默认宽度应读 kAuthorIndexBarWidth');
      expect(bar.contains('left: 28,'), isFalse,
          reason: '浮层起点应读 kAuthorIndexBarWidth');
    });
  });

  group('字母浮层尺寸立名，不留内联字面量', () {
    test('常量值与浮层实际使用一致', () {
      expect(kAuthorLetterHudSize, 84);
      expect(kAuthorLetterHudRadius, 16);
      expect(kAuthorLetterHudFontSize, 44);
    });

    test('浮层里没有 width: 84 / height: 84 / 字号 44 的字面量', () {
      final src = _src('author_letter_bar.dart');
      expect(src.contains('width: 84'), isFalse);
      expect(src.contains('height: 84'), isFalse);
      expect(src.contains('fontSize: 44'), isFalse);
      // 三个常量都被真正引用（不是只声明）
      expect(src.contains('kAuthorLetterHudSize'), isTrue);
      expect(src.contains('kAuthorLetterHudRadius'), isTrue);
      expect(src.contains('kAuthorLetterHudFontSize'), isTrue);
    });
  });

  group('卡片操作按钮：一处规格，四处调用', () {
    test('卡片的四个操作按钮都走 cardActionButton', () {
      final src = _src('unit_library_view.dart');
      // 四遍内联规格已消失：不再有 iconSize: 18 / tightFor(30, 30)
      expect(src.contains('iconSize: 18'), isFalse,
          reason: '按钮规格又写回调用点了');
      expect(src.contains('tightFor(width: 30, height: 30)'), isFalse);
      expect('cardActionButton('.allMatches(src).length, 4,
          reason: '顶级卡片 3 个（封面/选图/爬虫）+ 基础库卡片 1 个（封面）');
    });

    test('操作区内缩也只有一个数字', () {
      final src = _src('unit_library_view.dart');
      expect(src.contains('top: 6,'), isFalse,
          reason: '右上角内缩应读 kCardActionInset');
      expect(src.contains('right: 6,'), isFalse);
    });

    testWidgets('生成的按钮规格一致：图标 18、点击框 30×30', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: cardActionButton(
            buttonKey: const ValueKey('probe'),
            tooltip: '测试',
            icon: Icons.image_outlined,
            onPressed: () {},
          ),
        ),
      ));
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.iconSize, kCardActionIconSize);
      final c = btn.constraints!;
      expect(c.minWidth, kCardActionHitSize);
      expect(c.minHeight, kCardActionHitSize);
      expect(c.maxWidth, kCardActionHitSize);
      // 画出来的方框是 30dp；Material 3 会在此基础上各边再加
      // `VisualDensity.compact` 之后的最小点击区，所以实际渲染尺寸更大。
      // 这里只钉「规格来源唯一」：两个按钮的渲染尺寸必须完全相同
      // （此前四处各写一遍，改漏一处就是同排按钮一大一小）。
      final a = tester.getSize(find.byKey(const ValueKey('probe')));
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: cardActionButton(
            buttonKey: const ValueKey('probe2'),
            tooltip: '测试2',
            icon: Icons.settings_ethernet,
            onPressed: () {},
          ),
        ),
      ));
      expect(tester.getSize(find.byKey(const ValueKey('probe2'))), a,
          reason: '换图标/提示/回调不应改变按钮尺寸');
    });

    test('kCardActionInset 与角标内缩是两个独立决定', () {
      // 6 与 6 数值相同，但语义不同：一个是按钮点击框到边缘，
      // 一个是角标方块到边缘。合并会让「只想挪按钮」变成「连角标一起挪」。
      expect(kCardActionInset, 6);
    });
  });
}
