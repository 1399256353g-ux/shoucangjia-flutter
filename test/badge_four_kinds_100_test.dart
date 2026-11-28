import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/author_badge_row.dart';
import 'package:shoucangjia/library_badge.dart';

/// 0.9.359：渲染层把底纹与边框拆成两层（边框不参与布局测量），
/// `LibraryBadge.decorationFor` 已删。测试要「一眼看形状」时用这个本地合成体：
/// 圆角取两层中任一（两层的圆角必须相同），边框取前景层，底纹取填充层。
BoxDecoration _entryDeco(LibEntryKind kind, int argb) {
  final fill = LibraryBadge.fillDecorationFor(kind, argb);
  final border = LibraryBadge.borderDecorationFor(kind);
  return BoxDecoration(
    color: fill.color,
    borderRadius: fill.borderRadius,
    border: border.border,
  );
}


/// 第一百批（0.9.345）：**第四类词条（作者）没有独立外观**、
/// **继承来源只认媒体库根**、**「继承顶级」这个界面上不该出现的叫法**、
/// **空格有两条归属**、**折叠摘要按色表计数而不是按生效来源**。
///
/// 这一批的共同点：每一条都能在界面上看到一个与规则相反的结论——
///
/// | 现象 | 真正的来源 |
/// |---|---|
/// | 设置页写着「四种词条」，作者那一档调了没有任何东西变 | 等级词条没传 kind |
/// | 基础库的色明明来自中间层单元库，设置页说「没有继承」 | 只查 topOfUnit 一跳 |
/// | 界面上写「继承顶级」 | 术语规则：日常一律叫「媒体库」 |
/// | 播放页空格暂停，但空格明明「未绑定」 | 固定分支 + 绑定表两处都接 |
/// | 折叠摘要「已自定义 5 项」，进去每行都写自动分配 | 摘要查色表、列表看来源 |
void main() {
  String libRaw(String f) => File(f).readAsStringSync();

  setUp(() {
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.colorSource.clear();
    LibraryBadge.basicSource.clear();
    LibraryBadge.topOfUnit.clear();
    LibraryBadge.parentOfUnit.clear();
    LibraryBadge.emoji.clear();
    AppSettings.resetDefaults();
  });

  group('四种词条：作者一档是独立外观，不是 unit 的副本', () {
    test('枚举四种齐全，没有复活 other', () {
      expect(LibEntryKind.values.map((e) => e.name).toList(),
          <String>['top', 'unit', 'basic', 'author']);
    });

    test('四种圆角完全一致（形状一致是硬约束）', () {
      final radii = <double>{
        for (final k in LibEntryKind.values)
          (_entryDeco(k, 0xFF336699).borderRadius
                  as BorderRadius)
              .topLeft
              .x,
      };
      expect(radii, <double>{kEntryRadius});
    });

    test('作者档的边宽/底纹既不等于单元库也不等于基础库', () {
      // 「差异化」不是「互不相同就行」：作者词条与单元库/基础库放在同一排里，
      // 若与其中一档完全相同，用户还是分不出「这是等级还是库归属」。
      double w(LibEntryKind k) => LibraryBadge.styleFor(k).borderWidth;
      double fa(LibEntryKind k) => LibraryBadge.styleFor(k).fillAlpha;
      expect(w(LibEntryKind.author), isNot(w(LibEntryKind.unit)));
      expect(w(LibEntryKind.author), isNot(w(LibEntryKind.basic)));
      expect(fa(LibEntryKind.author), isNot(fa(LibEntryKind.unit)));
      expect(fa(LibEntryKind.author), isNot(fa(LibEntryKind.basic)));
      // 三档仍然保持「媒体库最粗 → 单元库 → 作者 → 基础库最细」的相对关系，
      // 这不影响 owner 认可的现有观感，只是把第四档塞进已有的梯度里。
      expect(w(LibEntryKind.top), greaterThan(w(LibEntryKind.unit)));
      expect(w(LibEntryKind.unit), greaterThan(w(LibEntryKind.author)));
      expect(w(LibEntryKind.author), greaterThan(w(LibEntryKind.basic)));
    });

    test('作者档可以单独自定义，并且不影响其它三档', () async {
      await LibraryBadge.setStyle(LibEntryKind.author,
          const EntryStyle(borderWidth: 2.2, borderAlpha: 0.9, fillAlpha: 0.3));
      expect(LibraryBadge.isStyleCustom(LibEntryKind.author), isTrue);
      for (final k in <LibEntryKind>[
        LibEntryKind.top,
        LibEntryKind.unit,
        LibEntryKind.basic
      ]) {
        expect(LibraryBadge.isStyleCustom(k), isFalse, reason: k.name);
      }
      await LibraryBadge.resetStyle(LibEntryKind.author);
      expect(LibraryBadge.isStyleCustom(LibEntryKind.author), isFalse);
    });

    testWidgets('作者词条行里的等级词条用的是 author 外观', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AuthorBadgeRow(unitLabel: '单元库A', grade: 'S'),
          ),
        ),
      ));
      final chips = tester.widgetList<LibBadgeChip>(find.byType(LibBadgeChip));
      final kinds = [for (final c in chips) c.kind];
      expect(kinds, contains(LibEntryKind.author),
          reason: '等级词条默认落到 unit，则设置页的「作者」一档永远调不到它');
      expect(kinds, contains(LibEntryKind.unit));
    });

    test('设置页四种都有可点的行，且层级名是日常叫法', () {
      final main = libRaw('lib/main.dart');
      // 0.9.359：层级中文名只允许有一份表（`lib/level_names.dart`）。
      final names = libRaw('lib/level_names.dart');
      for (final label in <String>['媒体库', '单元库', '基础库', '作者']) {
        expect(names.contains("'$label'"), isTrue, reason: label);
        // 中文名不得在 main.dart 的**层级标签表**里再写一份。页面标题
        // （首页 AppBar 的「媒体库」）是另一件事，不算层级标签。
        expect(
            RegExp("LibEntryKind\\.\\w+:\\s*'$label'").hasMatch(main), isFalse,
            reason: '$label 的层级标签不得在 main.dart 再写一份');
        expect(
            RegExp("LibBadgeKind\\.\\w+:\\s*'$label'").hasMatch(main), isFalse,
            reason: '$label 的角标标签不得在 main.dart 再写一份');
      }
      expect(names.contains('LibEntryKind.author:'), isTrue);
      // 设置页遍历的必须是全部四档（少一档 = 少一个可点入口）。
      expect(main.contains('for (final kind in LibEntryKind.values)'), isTrue);
      // 两处标签入口都读同一份表（角标页与词条外观页）。
      expect(main.contains('levelName('), isTrue);
    });
  });

  group('继承来源：与分发链同一条（不再只认媒体库根）', () {
    test('媒体库根设色：下级「有继承」且来源是媒体库', () {
      LibraryBadge.topOfUnit['TOP'] = 'TOP';
      LibraryBadge.topOfUnit['TOP/MID'] = 'TOP';
      LibraryBadge.parentOfUnit['TOP/MID'] = 'TOP';
      LibraryBadge.topCustom['TOP'] = 0xFF112233;
      expect(LibraryBadge.inheritsTopColor('TOP/MID'), isTrue);
      expect(LibraryBadge.inheritedColorFrom('TOP/MID'), 'TOP');
    });

    test('中间层设色：下级来源指向中间层而不是媒体库根', () {
      // owner 2026-11-27 之后，中间层单元库的颜色会向下分发。设置页说
      // 「继承上级」但说不出是谁，用户在列表里找不到该改哪一行。
      LibraryBadge.topOfUnit['TOP'] = 'TOP';
      LibraryBadge.topOfUnit['TOP/MID'] = 'TOP';
      LibraryBadge.parentOfUnit['TOP/MID'] = 'TOP';
      LibraryBadge.parentOfUnit['TOP/MID/LEAF'] = 'TOP/MID';
      LibraryBadge.topCustom['TOP'] = 0xFF112233;
      LibraryBadge.custom['TOP/MID'] = 0xFF445566;
      // 更近的一层优先（与 colorForUnit 一致）
      expect(LibraryBadge.inheritedColorFrom('TOP/MID/LEAF'), 'TOP/MID');
      expect(LibraryBadge.colorForUnit('TOP/MID/LEAF'),
          LibraryBadge.colorForUnit('TOP/MID'));
    });

    test('本层自己设了色：不算继承，来源为空', () {
      LibraryBadge.parentOfUnit['A'] = 'TOP';
      LibraryBadge.topCustom['TOP'] = 0xFF112233;
      LibraryBadge.custom['A'] = 0xFF445566;
      expect(LibraryBadge.inheritsTopColor('A'), isFalse);
      expect(LibraryBadge.inheritedColorFrom('A'), isEmpty);
    });

    test('来源选「自动分配」：不继承，且不向下传', () {
      LibraryBadge.parentOfUnit['A'] = 'TOP';
      LibraryBadge.topCustom['TOP'] = 0xFF112233;
      LibraryBadge.colorSource['A'] = 'auto';
      expect(LibraryBadge.inheritsTopColor('A'), isFalse);
      expect(LibraryBadge.inheritedColorFrom('A'), isEmpty);
    });

    test('基础库的继承来源也是逐级上行（含所属单元库本层）', () {
      LibraryBadge.parentOfUnit['TOP/MID'] = 'TOP';
      LibraryBadge.topCustom['TOP'] = 0xFF112233;
      expect(LibraryBadge.inheritedColorFromBasic('b1', 'TOP'), 'TOP');
      LibraryBadge.custom['TOP/MID'] = 0xFF445566;
      expect(LibraryBadge.inheritedColorFromBasic('b2', 'TOP/MID'), 'TOP/MID');
      // 基础库自己有色 → 不从任何人继承
      LibraryBadge.basicCustom['b3'] = 0xFF778899;
      expect(LibraryBadge.inheritedColorFromBasic('b3', 'TOP/MID'), isEmpty);
    });

    test('继承来源为「自己」时不算继承（环 / 顶级自身的保护）', () {
      LibraryBadge.topOfUnit['T1'] = 'T1';
      LibraryBadge.topCustom['T1'] = 0xFF112233;
      expect(LibraryBadge.inheritsTopColor('T1'), isFalse);
      expect(LibraryBadge.inheritedColorFrom('T1'), isEmpty);
    });
  });

  group('文案：界面不再出现「继承顶级」，且继承时说出是谁', () {
    test('没有来源名时是「继承上级」', () {
      expect(
          LibraryBadge.sourceLabelOf(BadgeColorSource.inheritTop,
              hasOwn: false, inherits: true),
          '继承上级');
    });

    test('有来源名时带出具体来源', () {
      expect(
          LibraryBadge.sourceLabelOf(BadgeColorSource.inheritTop,
              hasOwn: false, inherits: true, sourceName: ' 媒体库A '),
          '继承 媒体库A');
    });

    test('自动就是自动、自定义就是自定义（不因有没有继承改变叫法）', () {
      expect(
          LibraryBadge.sourceLabelOf(BadgeColorSource.autoAssign,
              hasOwn: false, inherits: true, sourceName: 'X'),
          '自动分配');
      expect(
          LibraryBadge.sourceLabelOf(BadgeColorSource.inheritTop,
              hasOwn: true, inherits: false, sourceName: 'X'),
          '自定义');
    });

    test('界面文案里不再有「继承顶级」（含分段按钮与来源标签）', () {
      // PROJECT_RULES §1：日常、界面、文案一律叫「媒体库」；
      // 「顶级单元库」只在设计结构设置页内部使用。
      //
      // 只扫**字符串字面量**：注释里引用 owner 原话（「…继承顶级锁死…」）
      // 是历史记录，按规则必须逐字保留，不能当成界面文案改掉。
      for (final f in <String>[
        'lib/main.dart',
        'lib/library_badge.dart',
      ]) {
        final src = libRaw(f);
        expect(src.contains("'继承顶级'"), isFalse, reason: f);
        expect(src.contains('"继承顶级"'), isFalse, reason: f);
      }
      // 分段按钮与来源标签都读同一个短名出口（0.9.359）：界面上的字样
      // 来自 `sourceShortLabel`，main.dart 不再自己写这三个词。
      final main = libRaw('lib/main.dart');
      expect(main.contains('LibraryBadge.sourceShortLabel('), isTrue);
      expect(LibraryBadge.sourceShortLabel(BadgeColorSource.inheritTop)
          .contains('上级'), isTrue);
    });
  });

  group('空格只有一条归属：绑定表', () {
    test('UI 层不再把空格写死在固定分支里', () {
      // 播放页 onKey 里若同时有「固定空格暂停」与「绑定表查 playPause」，
      // 用户把 playPause 改绑到别的键后空格仍然暂停——同一个键两个主人。
      final main = libRaw('lib/main.dart');
      final start = main.indexOf('KeyEventResult onKey(FocusNode node');
      expect(start, greaterThan(0));
      final body = main.substring(start, start + 2600);
      expect(body.contains('LogicalKeyboardKey.space'), isFalse,
          reason: '空格必须只由绑定表决定；固定分支会让改绑失效');
    });

    test('空格仍可改绑，且默认就是播放/暂停', () {
      expect(AppSettings.keyBindings[PlayerAction.playPause]!.keyId,
          LogicalKeyboardKey.space.keyId);
      expect(
          AppSettings.bindCombo(
              PlayerAction.playPause, KeyCombo(LogicalKeyboardKey.keyN.keyId)),
          isTrue);
      expect(AppSettings.keyBindings[PlayerAction.playPause]!.keyId,
          LogicalKeyboardKey.keyN.keyId);
      // 改绑后空格不再触发任何动作（这就是「一个键一个主人」）。
      expect(AppSettings.actionForCombo(LogicalKeyboardKey.space.keyId, 0),
          isNull);
    });

    test('方向键 / Esc 仍然是固定键位，不随自定义绑定变化', () {
      for (final k in <LogicalKeyboardKey>[
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.escape,
      ]) {
        expect(AppSettings.bindComboError(KeyCombo(k.keyId)), isNotNull);
      }
      final main = libRaw('lib/main.dart');
      final start = main.indexOf('KeyEventResult onKey(FocusNode node');
      final body = main.substring(start, start + 2600);
      expect(body.contains('LogicalKeyboardKey.escape'), isTrue);
      expect(body.contains('LogicalKeyboardKey.arrowDown'), isTrue);
    });
  });

  group('折叠摘要按「生效来源」计数，不按色表', () {
    test('来源=自动 + 残留色 → 不算自定义', () {
      LibraryBadge.custom['u1'] = 0xFF112233;
      LibraryBadge.colorSource['u1'] = 'auto';
      expect(LibraryBadge.hasOwnColor('u1'), isFalse);
      // 旧的摘要口径（直接查表）会把它算进「已自定义 N 项」。
      expect(LibraryBadge.customColorFor('u1'), isNotNull);
    });

    test('设置页摘要不再直接查色表', () {
      final main = libRaw('lib/main.dart');
      // 摘要块必须用 hasOwnColor / hasOwnBasicColor 计数。
      final idx = main.indexOf('final customized = <String>[');
      expect(idx, greaterThan(0));
      final block = main.substring(idx, idx + 400);
      expect(block.contains('hasOwnColor'), isTrue);
      expect(block.contains('hasOwnBasicColor'), isTrue);
      expect(block.contains('customColorFor'), isFalse);
      expect(block.contains('basicCustom['), isFalse);
      expect(block.contains('topColorFor'), isFalse);
    });
  });
}
