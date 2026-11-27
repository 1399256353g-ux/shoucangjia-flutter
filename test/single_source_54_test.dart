/// 第七十六批契约（0.9.306）：
///  「同一个数字在骨架与真实布局里各写一遍」——上一批抓的是「判定写给每个
///  调用点」，这一批抓「同一个数字被两个人各写一次」。两类都不到报错的程度：
///  骨架与真实头部在**不同时间**出现在屏幕上（先骨架、后真实），所以没有
///  第二份副本可以并排对照，只有「加载完成」那一瞬间的跳动。
///
///  1. 作者主页头部内边距 / 头像尺寸 / 头像-文字间距：真实头部与
///     `_AuthorPageSkeleton` 各一份（`all(14)` / 64 / 32 / 12）。
///  2. 基础库页作者 tab 的搜索框高度 38 与卡片内边距 `fromLTRB(10,12,10,10)`
///     是页面里唯一一份、也不与任何常量同名，改网格行高时不会有人提醒。
///  3. 词条层级只剩三种（owner 2026-11-26），但文案与注释里还写着「四种」。
///  4. 真缺陷：`LibBadges` 的早退只判 `labels` 与 `grade`，于是「单元库归属
///     算不出来的多基础库作者」的基础库词条被整段丢掉。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_badge_row.dart';
import 'package:shoucangjia/card_metrics.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/main.dart' show LibBadges;

/// 去掉整行注释后再扫描：注释里提到「四种」是历史说明，不算第二份实现。
String _code(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _raw(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('作者主页头部几何：骨架与真实头部同一份常量', () {
    test('真实头部读 card_metrics 的三个常量，不再写 14 / 12', () {
      final main = _code('lib/main.dart');
      expect(main.contains('EdgeInsets.all(kAuthorHeaderPadding)'), isTrue);
      // 作者主页信息头那段的间距必须走常量：整文件里 `SizedBox(width: 12)`
      // 还有别处（弹窗按钮行），所以只锁定「出现 kAuthorHeaderAvatarGap」。
      expect(main.contains('SizedBox(width: kAuthorHeaderAvatarGap)'), isTrue);
    });

    test('骨架头像与真实头像同尺寸、同圆角、同内边距', () {
      final main = _code('lib/main.dart');
      final i = main.indexOf('class _AuthorPageSkeleton');
      expect(i, greaterThan(0));
      final body = main.substring(i, i + 1200);
      // 骨架的占位块必须按真实头像边长铺，圆角是边长的一半（圆形头像）。
      expect(body.contains('width: kAvatarHeaderSize'), isTrue);
      expect(body.contains('height: kAvatarHeaderSize'), isTrue);
      expect(body.contains('Radius.circular(kAvatarHeaderSize / 2)'), isTrue);
      expect(body.contains('EdgeInsets.all(kAuthorHeaderPadding)'), isTrue);
      expect(body.contains('SizedBox(width: kAuthorHeaderAvatarGap)'), isTrue);
      // 旧的字面量不得再出现（名字行的占位块宽度 64 与头像尺寸无关，
      // 不做连带检查；这里只钉头像块自己的尺寸与圆角）。
      expect(body.contains('height: 64'), isFalse,
          reason: '头像占位块必须按 kAvatarHeaderSize 铺');
      expect(body.contains('circular(32)'), isFalse);
      expect(body.contains('EdgeInsets.all(14)'), isFalse);
    });

    test('常量值本身与头像尺寸一致（骨架=真实的前提）', () {
      expect(kAvatarHeaderSize, 64);
      expect(kAuthorHeaderPadding, 14);
      expect(kAuthorHeaderAvatarGap, 12);
    });
  });

  group('基础库页作者 tab：搜索框与卡片留白立名', () {
    test('页面里不再出现 38 与 fromLTRB(10, 12, 10, 10)', () {
      final basic = _code('lib/basic_lib_page.dart');
      expect(basic.contains('height: kBasicAuthorSearchHeight'), isTrue);
      expect(basic.contains('height: 38'), isFalse);
      expect(basic.contains('padding: kBasicAuthorCardPadding'), isTrue);
      expect(basic.contains('fromLTRB(10, 12, 10, 10)'), isFalse);
    });

    test('卡片内边距是「上多下少」，不是四边同值', () {
      expect(kBasicAuthorCardPadding.top, 12);
      expect(kBasicAuthorCardPadding.bottom, 10);
      expect(kBasicAuthorCardPadding.left, 10);
      expect(kBasicAuthorCardPadding.right, 10);
      expect(kBasicAuthorSearchHeight, 38);
    });
  });

  group('词条只剩三种：文案与注释一致', () {
    test('lib/ 内不再有「四种层级 / 四层级 / 四级词条」的措辞', () {
      for (final f in const [
        'lib/main.dart',
        'lib/library_badge.dart',
        'lib/author_badge_row.dart',
        'lib/unit_library_view.dart',
      ]) {
        final src = _raw(f);
        expect(src.contains('四种层级'), isFalse, reason: f);
        expect(src.contains('四层级'), isFalse, reason: f);
        expect(src.contains('四种词条'), isFalse, reason: f);
      }
    });

    test('设置页只列三种层级，且预览用的是真实外观', () {
      expect(LibEntryKind.values.length, 3);
      final main = _code('lib/main.dart');
      expect(main.contains('三层级边框'), isTrue);
      expect(main.contains('三种词条形状与尺寸一致'), isTrue);
    });
  });

  group('真缺陷：换作品时折叠态不能串到下一条', () {
    BadgeChipSpec chip(String label, LibEntryKind kind) =>
        BadgeChipSpec(label: label, color: 0xFF336699, kind: kind);
    Widget host(List<BadgeChipSpec> chips) => MaterialApp(
          home: Scaffold(
              body: Center(child: CollapsibleBadgeWrap(chips: chips))),
        );

    testWidgets('词条条数相同但内容不同 → 回落为常态折叠', (t) async {
      await t.pumpWidget(host([
        chip('媒体库A', LibEntryKind.top),
        chip('基础库C', LibEntryKind.basic),
      ]));
      await t.tap(find.byKey(const ValueKey('badge-expand')));
      await t.pumpAndSettle();
      expect(find.text('基础库C'), findsOneWidget);

      // 换到另一条作品：条数恰好也是 2，但内容不同。
      await t.pumpWidget(host([
        chip('媒体库B', LibEntryKind.top),
        chip('基础库D', LibEntryKind.basic),
      ]));
      await t.pumpAndSettle();
      expect(find.text('媒体库B'), findsOneWidget);
      expect(find.text('基础库D'), findsNothing,
          reason: '上一条作品的展开态不得带过来');
      expect(find.byKey(const ValueKey('badge-expand')), findsOneWidget);
    });

    testWidgets('内容完全相同（同一条作品重建）时保持展开', (t) async {
      final chips = [
        chip('媒体库A', LibEntryKind.top),
        chip('基础库C', LibEntryKind.basic),
      ];
      await t.pumpWidget(host(chips));
      await t.tap(find.byKey(const ValueKey('badge-expand')));
      await t.pumpAndSettle();
      await t.pumpWidget(host(List<BadgeChipSpec>.from(chips)));
      await t.pumpAndSettle();
      expect(find.text('基础库C'), findsOneWidget,
          reason: '同一条作品重建不应把用户的展开动作收回去');
    });
  });

  group('真缺陷：展开键在浅色主题下仍看得见', () {
    testWidgets('文字/图标用主题前景色，不写死白色', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Scaffold(
            body: CollapsibleBadgeWrap(chips: const [
          BadgeChipSpec(
              label: '媒体库A', color: 0xFF336699, kind: LibEntryKind.top),
          BadgeChipSpec(
              label: '基础库C', color: 0xFF336699, kind: LibEntryKind.basic),
        ])),
      ));
      final text = t.widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('badge-expand')),
          matching: find.text('1')));
      final scheme = Theme.of(t.element(find.byType(CollapsibleBadgeWrap)))
          .colorScheme;
      expect(text.style!.color!.a, closeTo(0.75, 0.02));
      expect(Colors.white.withValues(alpha: 0.75).toARGB32(),
          isNot(scheme.onSurface.withValues(alpha: 0.75).toARGB32()));
      expect(text.style!.color!.toARGB32(),
          scheme.onSurface.withValues(alpha: 0.75).toARGB32(),
          reason: '展开键必须跟主题前景色，不能写死白');
    });
  });

  group('真缺陷：基础库词条不能被早退丢掉', () {
    testWidgets('只有基础库词条（无单元库、无等级）时仍然渲染', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibBadges(
            libIds: const <String>[],
            grade: '',
            basicChips: const <BadgeChipSpec>[
              BadgeChipSpec(
                  label: '基础库C', color: 0xFF336699, kind: LibEntryKind.basic),
            ],
          ),
        ),
      ));
      // 折叠规则允许「只剩基础库」时照常显示（不能把卡片藏空）。
      expect(find.text('基础库C'), findsOneWidget);
    });

    testWidgets('真的什么都没有时才占位为零尺寸', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: LibBadges(libIds: const <String>[])),
      ));
      expect(find.byType(Wrap), findsNothing);
    });
  });
}
