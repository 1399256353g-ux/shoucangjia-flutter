/// 第六十五批契约（0.9.288）：**同一个数字的两种说法**。
///
/// 第六十三/六十四批收的是「同段代码抄多份」「同一记录两个模型」。这一批抓
/// 更静默的一类：**一个数字在两个地方各有一个名字，两边都算得出值**。
///
/// 1. `decode_plan.kLibCardDisplayWidth`(220) / `unit_library_view
///    .kUnitCardDisplayWidth`(260) 与 `grid_spec` 里两个
///    `maxCrossAxisExtent`(220/260) 是同一组数字的两种说法。改网格不改解码
///    宽度，同一张封面就有两个缓存键 → 预热白拉、进页面再解码一次。
/// 2. 卡片圆角 12 与头像边长 58/42/64 散在四个 widget 的 `static const` 与
///    页面内联字面量里（三处 12、四处 58）。作者总览卡与基础库页作者卡必须
///    视觉一致，只改一处就分叉。
/// 3. `_UnitCoverFill` 自己存一个 `displayWidth` 数字，而它所属的网格规格
///    就在调用点旁边——同一个值有两个来源。
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/card_metrics.dart';
import 'package:shoucangjia/main.dart';
import 'package:shoucangjia/grid_spec.dart';
import 'package:shoucangjia/unit_library_view.dart';
import 'package:shoucangjia/work_card_prefetch.dart';

/// 去掉整行注释后再做「有没有第二个实现」的扫描。
String _code(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('显示宽度与网格列宽是同一个数字（0.9.288）', () {
    test('规格的 displayWidth 就是列上限，不再另立常量', () {
      expect(kUnitLibGrid.displayWidth, kUnitLibGrid.maxCrossAxisExtent);
      expect(kBasicLibGrid.displayWidth, kBasicLibGrid.maxCrossAxisExtent);
      expect(kUnitLibGrid.displayWidth, 260);
      expect(kBasicLibGrid.displayWidth, 220);
    });

    test('解码宽度只经规格出口，220 与 260 得到不同值', () {
      expect(kUnitLibGrid.decodeWidth(2), 520);
      expect(kBasicLibGrid.decodeWidth(2), 440);
      // 上限仍是 3x（`ceilDim(displayWidth * 3)`），4x 屏不无限放大。
      expect(kBasicLibGrid.decodeWidth(4), 660);
      expect(kUnitLibGrid.decodeWidth(4), 780);
      // 非有限/零像素比沿用 decode_plan 的旧口径，不抛。
      expect(kBasicLibGrid.decodeWidth(double.nan), 220);
      expect(kBasicLibGrid.decodeWidth(0), 220);
    });

    test('旧的第二套说法已删除（kLibCardDisplayWidth / libCardDecodeWidth）', () {
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = _code(f.path);
        expect(src.contains('kLibCardDisplayWidth'), isFalse,
            reason: '${f.path}：显示宽度只允许来自 LibGridSpec.displayWidth');
        expect(RegExp(r'\blibCardDecodeWidth\(').hasMatch(src), isFalse,
            reason: '${f.path}：解码宽度只允许经 LibGridSpec.decodeWidth');
        expect(src.contains('kUnitCardDisplayWidth'), isFalse,
            reason: '${f.path}：260 不再另立常量');
      }
    });

    test('页面不得再自己挑 220/260 去算解码宽度', () {
      final view = _code('lib/unit_library_view.dart');
      expect(RegExp(r'libCardDecodeWidthOf\(').hasMatch(view), isFalse,
          reason: '调用点自己挑数字正是重复的来源');
      expect(RegExp(r'\.decodeWidth\(').allMatches(view).length, 5,
          reason: '卡片 1 处 + 三页预热 4 处');
    });

    test('_UnitCoverFill 不再自己存 displayWidth 数字', () {
      final view = _code('lib/unit_library_view.dart');
      expect(view.contains('final double displayWidth'), isFalse,
          reason: '网格规格就在调用点旁边，第二个来源会与它分叉');
      expect(view.contains('final LibGridSpec grid'), isTrue);
      // 基础库卡片不传 grid 时按基础库规���解码（此前内联默认 220）。
      expect(view.contains('this.grid = kBasicLibGrid'), isTrue);
    });
  });

  group('卡片几何只有一张尺寸表（0.9.288）', () {
    test('圆角：库卡片与作者卡片同一个数字，作品卡是独立决定', () {
      expect(kCardRadius, 12);
      expect(kWorkCardRadius, 10);
      expect(kLibCardRadius, kCardRadius);
      expect(AuthorGridCard.radius, kCardRadius);
      expect(AuthorAvatar.gridSize, kAvatarGridSize);
      expect(AuthorAvatar.rankSize, kAvatarRankSize);
      expect(AuthorAvatar.headerSize, kAvatarHeaderSize);
      expect(UnitLibraryCard.radius, kCardRadius);
    });

    test('头像三个边长来自尺寸表', () {
      expect(kAvatarGridSize, 58);
      expect(kAvatarRankSize, 42);
      expect(kAvatarHeaderSize, 64);
      // 基础库页作者卡与作者总览同一个边长。
      expect(kAvatarBasicAuthorSize, kAvatarGridSize);
    });

    test('页面内不得再出现圆角 12 / 头像 58 的字面量', () {
      final basic = _code('lib/basic_lib_page.dart');
      expect(RegExp(r'circular\(12\)').hasMatch(basic), isFalse,
          reason: '基础库页作者卡圆角只允许走 kCardRadius');
      expect(RegExp(r'size = 58').hasMatch(basic), isFalse,
          reason: '头像边长只允许走 kAvatarBasicAuthorSize');

      final view = _code('lib/unit_library_view.dart');
      expect(RegExp(r'circular\(12\)').hasMatch(view), isFalse);
      expect(view.contains('const double kLibCardRadius = 12'), isFalse,
          reason: '12 只允许在 card_metrics 出现一次');
    });

    test('尺寸表是唯一取值处：只有它写 58 / 42 / 64 的字面量', () {
      final metrics = _code('lib/card_metrics.dart');
      expect(metrics.contains('kAvatarGridSize = 58'), isTrue);
      expect(metrics.contains('kAvatarRankSize = 42'), isTrue);
      expect(metrics.contains('kAvatarHeaderSize = 64'), isTrue);
      for (final path in const [
        'lib/main.dart',
        'lib/basic_lib_page.dart',
        'lib/unit_library_view.dart',
      ]) {
        final src = _code(path);
        expect(RegExp(r'= 58;').hasMatch(src), isFalse, reason: path);
        expect(RegExp(r'= 42;').hasMatch(src), isFalse, reason: path);
        expect(RegExp(r'= 64;').hasMatch(src), isFalse, reason: path);
      }
    });
  });

  group('作品卡首屏预热只有一个实现（0.9.288）', () {
    test('两个页面都不再自己算张数/自己加 w=/自己排队', () {
      for (final path in const [
        'lib/basic_lib_page.dart',
        'lib/main.dart',
      ]) {
        final src = _code(path);
        // 作品网格这一层已收口；`main.dart` 里剩下的两处是**头像**预热
        // （排行榜行 / 作者网格），它们不带作品网格几何，另行处理。
        expect(RegExp(r'kBasicWorkGrid\.prefetchCount\(').hasMatch(src), isFalse,
            reason: '$path 又自己算作品网格张数');
        expect(RegExp(r'kWorkGrid\.prefetchCount\(').hasMatch(src), isFalse,
            reason: '$path 又自己算作品网格张数');
        expect(src.contains('ThumbPrefetch.instance.run('), isFalse, reason: path);
        expect(src.contains('ThumbPrefetch.instance.runWith('), isFalse, reason: path);
      }
      final basic = _code('lib/basic_lib_page.dart');
      expect(basic.contains('workCardDecodeWidth('), isFalse,
          reason: '解码宽度只允许在预热入口算一次');
    });

    test('预热入口与 WorkCard 用同一个解码宽度和同一个 w=', () {
      final src = _code('lib/work_card_prefetch.dart');
      expect(src.contains('workCardDecodeWidth(devicePixelRatio)'), isTrue);
      expect(src.contains('withImageWidth(it.cover, kWorkImageWidth)'), isTrue);
      expect(src.contains('prefetchThumbItems('), isTrue);
      expect(src.contains('grid.prefetchCount('), isTrue);
    });

    test('张数按网格规格算：600×400 下与 delegate 的列数一致', () {
      // 600 宽、180 列上限、间距 2：ceil(600/182) → 4 列（列宽 ≈ 148.5）。
      final n = kWorkGrid.prefetchCount(
        const Size(600, 400),
        padding: EdgeInsets.zero,
      );
      expect(n, greaterThan(4), reason: '至少一行都不止');
      // 同一组参数换更窄的视口，张数必须跟着减少（不是写死的上限）。
      final narrow = kWorkGrid.prefetchCount(
        const Size(200, 400),
        padding: EdgeInsets.zero,
      );
      expect(narrow, lessThan(n));
    });

    test('预热入口对空封面返回 0，不会拼出服务器根地址', () {
      // `withImageWidth('')` 仍是空串，`prefetchThumbItems` 上游排掉。
      expect(
        prefetchWorkCovers(
          viewport: const Size(600, 400),
          grid: kWorkGrid,
          padding: EdgeInsets.zero,
          devicePixelRatio: 2,
          items: [(cover: '', headers: const {'A': '1'})],
        ),
        0,
      );
    });
  });

  group('作品卡与库卡片圆角不互相顶替', () {
    test('两个常量都在、且不同', () {
      expect(kWorkCardRadius == kCardRadius, isFalse);
      // WorkCard 转发的是作品卡那个（不是库卡片的 12）。
      final wc = _code('lib/work_card.dart');
      expect(wc.contains('static const double radius = kWorkCardRadius'), isTrue);
    });
  });
}
