import 'dart:io';

import 'package:flutter/material.dart' show Border, BorderRadius, Color;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/author_filter.dart';
import 'package:shoucangjia/level_names.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_corner_badge.dart';

// 0.9.359 第一百一十二批：层级中文名两份表 / 合成装饰器只活在测试里 /
// 颜色来源短名两份 / 两个零调用 API。
//
// 判据全部是「读源码断言唯一实现」与「纯函数返回值」，不涉及任何 UI 截图、
// 目录名或媒体内容。

String libRaw(String rel) => File(rel).readAsStringSync();

/// 去掉整行注释后的源码：注释里**提到**某个字面量不算「又写了一份」。
String libCode(String rel) => libRaw(rel)
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LibraryBadge.load();
    await AppSettings.load();
  });

  group('1. 四个层级的中文名只有一份表', () {
    test('level_names 覆盖全部四档，且没有 other', () {
      expect(kLevelNames.length, LibEntryKind.values.length);
      for (final k in LibEntryKind.values) {
        expect(kLevelNames.containsKey(k), isTrue, reason: k.name);
      }
      expect(kLevelNames[LibEntryKind.top], '媒体库');
      expect(kLevelNames[LibEntryKind.unit], '单元库');
      expect(kLevelNames[LibEntryKind.basic], '基础库');
      expect(kLevelNames[LibEntryKind.author], '作者');
    });

    test('日常叫法里没有已废除的「大库」「顶级节点」', () {
      for (final name in kLevelNames.values) {
        expect(name.contains('大库'), isFalse, reason: name);
        expect(name.contains('顶级节点'), isFalse, reason: name);
      }
    });

    test('lib/ 内不再有第二份层级标签表', () {
      // 「<枚举>: '中文'」这种映射只允许出现在 level_names.dart。
      final pattern = RegExp(r"LibEntryKind\.\w+:\s*'[\u4e00-\u9fff]");
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('level_names.dart')) continue;
        final hit = pattern.firstMatch(f.readAsStringSync());
        expect(hit, isNull, reason: '${f.path} 里又写了一份层级标签');
      }
    });

    test('筛选摘要读同一份表，不再写死三个字面量', () {
      final f = AuthorFilterState();
      f.toggleTop('top-1');
      f.toggleUnit('unit-1');
      f.toggleBasic('basic-1');
      final s = f.summary(
        topNames: const {'top-1': 'T'},
        unitNames: const {'unit-1': 'U'},
        basicNames: const {'basic-1': 'B'},
      );
      expect(s.contains(levelName(LibEntryKind.top)), isTrue);
      expect(s.contains(levelName(LibEntryKind.unit)), isTrue);
      expect(s.contains(levelName(LibEntryKind.basic)), isTrue);
      expect(
          libCode('lib/author_filter.dart')
              .contains("_namesPart('媒体库'"),
          isFalse,
          reason: '摘要里不该出现写死的层级名');
    });
  });

  group('2. 颜色来源短名只有一份（片段按钮与列表同源）', () {
    test('三个来源都有短名，且与摘要用的词一致', () {
      expect(LibraryBadge.sourceShortLabel(BadgeColorSource.inheritTop),
          '继承上级');
      expect(LibraryBadge.sourceShortLabel(BadgeColorSource.autoAssign),
          '自动分配');
      expect(LibraryBadge.sourceShortLabel(BadgeColorSource.fixedCustom),
          '自定义');
    });

    test('来源=自动时摘要也显示「自动分配」，不会显示成「继承」', () {
      expect(
          LibraryBadge.sourceLabelOf(BadgeColorSource.autoAssign,
              hasOwn: false, inherits: true),
          LibraryBadge.sourceShortLabel(BadgeColorSource.autoAssign));
      // 声明了自定义但色被清掉：真实生效的是自动配色。
      expect(
          LibraryBadge.sourceLabelOf(BadgeColorSource.fixedCustom,
              hasOwn: false, inherits: false),
          LibraryBadge.sourceShortLabel(BadgeColorSource.autoAssign));
    });

    test('设置页的片段按钮读 sourceShortLabel，不再手写字面量', () {
      final main = libCode('lib/main.dart');
      expect(main.contains('LibraryBadge.sourceShortLabel('), isTrue);
      // 只看颜色来源选择器那一段：`'自定义'` 在设置首层还有另一个含义
      // （自定义分类页标题），那是另一个东西，不该被这条断言连坐。
      final at = main.indexOf('SegmentedButton<BadgeColorSource>');
      expect(at, greaterThan(0));
      final seg = main.substring(at, main.indexOf('onSelectionChanged', at));
      for (final lit in <String>["'继承上级'", "'自动分配'", "'自定义'"]) {
        expect(seg.contains(lit), isFalse,
            reason: '来源片段里不该再写死 $lit');
      }
    });
  });

  group('3. 合成装饰器已删：渲染层只有底纹与边框两层', () {
    test('LibraryBadge 不再提供 decorationFor', () {
      final s = libCode('lib/library_badge.dart');
      expect(RegExp(r'static BoxDecoration decorationFor\(').hasMatch(s),
          isFalse);
      // 两层仍在，且边框不进 decoration（不参与布局测量）。
      expect(s.contains('static BoxDecoration fillDecorationFor('), isTrue);
      expect(s.contains('static BoxDecoration borderDecorationFor('), isTrue);
    });

    test('词条组件把边框画在前景层，占位面积与边框粗细无关', () {
      final s = libRaw('lib/library_badge.dart');
      final chip = s.substring(s.indexOf('class LibBadgeChip'));
      expect(chip.contains('foregroundDecoration:'), isTrue,
          reason: '边框必须在不参与测量的层');
      // 内边距是固定值，不随边框变化。
      expect(chip.contains('padding: const EdgeInsets.symmetric('), isTrue);
    });

    test('改边框粗细不改变底纹与圆角', () {
      final before = LibraryBadge.fillDecorationFor(LibEntryKind.unit, 0xFF123456);
      LibraryBadge.entryStyle[LibEntryKind.unit] =
          LibraryBadge.styleFor(LibEntryKind.unit).copyWith(borderWidth: 3);
      final after = LibraryBadge.fillDecorationFor(LibEntryKind.unit, 0xFF123456);
      expect((after.color as Color).a, (before.color as Color).a);
      expect((after.borderRadius as BorderRadius).topLeft.x, kEntryRadius);
      final border = LibraryBadge.borderDecorationFor(LibEntryKind.unit);
      expect((border.border as Border).top.width, 3.0);
    });
  });

  group('3b. 角标色块：默认色必须自带一格', () {
    test('三档默认色都在候选清单里（恢复默认后仍有高亮）', () async {
      for (final kind in LibBadgeKind.values) {
        await LibraryCornerBadge.resetKind(kind);
        final choices = LibraryCornerBadge.colorChoices(
            kind: kind, palette: LibraryBadge.palette);
        expect(choices, contains(LibraryCornerBadge.colorFor(kind)),
            reason: kind.name);
      }
    });

    test('已在调色板里的颜色不重复加格', () async {
      await LibraryCornerBadge.setColor(LibBadgeKind.basic, LibraryBadge.palette[2]);
      final choices = LibraryCornerBadge.colorChoices(
          kind: LibBadgeKind.basic, palette: LibraryBadge.palette);
      expect(choices.where((c) => c == LibraryBadge.palette[2]).length, 1);
      expect(choices.length, LibraryBadge.palette.length);
    });

    test('角标设置页走 colorChoices（词条边框色板仍可直接铺 palette）', () {
      final main = libCode('lib/main.dart');
      expect(main.contains('LibraryCornerBadge.colorChoices('), isTrue);
      // 角标设置页那一段（`_CornerBadgeSettingsPageState`）里不得再直接铺调色板。
      final at = main.indexOf('class _CornerBadgeSettingsPageState');
      expect(at, greaterThan(0));
      final tail = main.substring(at);
      final end = tail.indexOf('class CollectionAdminPage');
      final page = end > 0 ? tail.substring(0, end) : tail;
      expect(page.contains('for (final c in LibraryBadge.palette)'), isFalse,
          reason: '角标页的色块清单只能来自 colorChoices');
    });
  });

  group('4. 两个零调用 API 已删', () {
    test('KeyCombo.copyWith 不再存在', () {
      final s = libCode('lib/app_settings.dart');
      expect(RegExp(r'KeyCombo\s+copyWith\(').hasMatch(s), isFalse);
    });

    test('isComboTakenByOther 不再存在（占用判定只有 conflictOwner）', () {
      final s = libCode('lib/app_settings.dart');
      expect(s.contains('isComboTakenByOther'), isFalse);
      final fsKey = AppSettings.keyBindings[PlayerAction.fullscreen]!;
      expect(AppSettings.conflictOwner(PlayerAction.mute, fsKey),
          PlayerAction.fullscreen);
    });
  });

  group('5. 组合键准入规则保持不变（P0 回归）', () {
    test('修饰键不能单独绑定；保留键不能绑定；越界掩码被拒', () {
      expect(
          AppSettings.bindComboError(
              KeyCombo(LogicalKeyboardKey.shiftLeft.keyId)),
          isNotNull);
      expect(
          AppSettings.bindComboError(
              KeyCombo(LogicalKeyboardKey.escape.keyId)),
          isNotNull);
      expect(
          AppSettings.bindComboError(
              KeyCombo(LogicalKeyboardKey.keyJ.keyId, 16)),
          isNotNull);
      expect(
          AppSettings.bindComboError(
              KeyCombo(LogicalKeyboardKey.keyJ.keyId, KeyCombo.modCtrl)),
          isNull);
    });

    test('单键与组合精确匹配，互不触发', () {
      final j = LogicalKeyboardKey.keyJ.keyId;
      AppSettings.bindCombo(PlayerAction.mute, KeyCombo(j));
      AppSettings.bindCombo(PlayerAction.prev, KeyCombo(j, KeyCombo.modCtrl));
      expect(AppSettings.actionForCombo(j, 0), PlayerAction.mute);
      expect(AppSettings.actionForCombo(j, KeyCombo.modCtrl), PlayerAction.prev);
      expect(AppSettings.comboLabel(AppSettings.keyBindings[PlayerAction.prev]!),
          'Ctrl+J');
    });
  });
}
