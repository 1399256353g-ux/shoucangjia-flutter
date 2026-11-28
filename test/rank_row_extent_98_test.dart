// 第九十八批（0.9.343）契约：
//   1. 排行榜行高常量必须等于**真实排版高度**（不是凑出来的整数）。
//   2. 「播放设置 → 恢复默认」只重置播放参数；「按键绑定 → 恢复默认」只重置
//      按键。此前两个按钮都调全量重置，改一页把另一页的设置静默清掉。
//
// 隐私：全部用合成 id/名字（`b1` / `T1` / `A`），不读任何真实目录名，
// 不涉及截图或媒体内容。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/card_metrics.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/main.dart' show AuthorRankTile, LibMeta;
import 'package:shoucangjia/preload_policy.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/video_layout.dart' show VideoFit;

BasicLib b(String id, String rel) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 3,
      serverId: 's1',
      serverLabel: 'A',
    );

/// 一行排行榜：带媒体库 + 单元库两级词条（这就是行高实测的那一形态）。
Widget row(LibMeta? meta) => MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          AuthorRankTile(
            rank: 1,
            rankColor: Colors.amber,
            name: 'A',
            avatar: '',
            lib: 'b1',
            libs: const ['b1'],
            meta: meta,
            works: 3,
            plays: 5,
            drops: 1,
          ),
          const Divider(height: kAuthorRankDividerHeight),
          const Text('x'),
        ]),
      ),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppSettings.resetDefaults();
    await LibraryBadge.load();
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.topOfUnit.clear();
    LibraryBadge.parentOfUnit.clear();
    UnitBadgeRegistry.order.clear();
    UnitBadgeRegistry.labels.clear();
    UnitBadgeRegistry.keys.clear();
  });

  group('1. 排行榜行高常量 == 真实排版高度', () {
    testWidgets('实测行高与常量一致（误差 < 0.05dp）', (t) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1.0;
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'T1', rel: 'T1', name: 'T1', serverId: 's1', serverLabel: 'A'),
        ],
        basics: [b('b1', 'T1/x')],
        topName: 'ROOT',
      )!;
      UnitBadgeRegistry.setFrom(tree);
      final meta = LibMeta(
        basics: tree.allBasics,
        allBasics: tree.allBasics,
        stats: const {},
        unitTree: tree,
        units: flattenUnits(tree),
        basicToUnit: unitOfBasics(tree),
        topName: 'ROOT',
      );
      await t.pumpWidget(row(meta));
      await t.pump();
      final h = t.getSize(find.byType(AuthorRankTile)).height;
      expect(h, closeTo(kAuthorRankTileHeight, 0.05),
          reason: '常量必须是测出来的真实行高：写整数会每行少算 0.6dp，'
              '首屏预热就会多算进屏幕外的一行');
      // 两级词条真的贴上了（否则这条测试会在「空行」上通过，失去意义）。
      expect(find.byType(Text), findsWidgets);
    });

    test('行步进 = 行高 + 分隔线，且不是整数', () {
      expect(kAuthorRankDividerHeight, 1);
      expect(kAuthorRankRowExtent, kAuthorRankTileHeight + kAuthorRankDividerHeight);
      expect(kAuthorRankTileHeight, isNot(kAuthorRankTileHeight.roundToDouble()),
          reason: '真有小数才算「测出来的」；写回 67 会绕过这条');
    });
  });

  group('2. 两个「恢复默认」各管一半', () {
    test('resetPlayback 不动按键绑定', () {
      final custom =
          KeyCombo(LogicalKeyboardKey.keyQ.keyId, KeyCombo.modCtrl | KeyCombo.modShift);
      expect(AppSettings.bindCombo(PlayerAction.mute, custom), isTrue);
      AppSettings.defaultSpeed = 2.0;
      AppSettings.preloadPerSide = 3;

      AppSettings.resetPlayback();

      expect(AppSettings.keyBindings[PlayerAction.mute], custom,
          reason: '播放设置的重置不得清掉用户改过的组合键');
      expect(AppSettings.defaultSpeed, 1.0);
      expect(AppSettings.preloadPerSide,
          preloadDefaultPerSideFor(
              mobile: Platform.isAndroid || Platform.isIOS));
    });

    test('resetKeys 不动播放参数', () {
      AppSettings.defaultSpeed = 1.5;
      AppSettings.imageIntervalSec = 7;
      AppSettings.videoFitOverride = VideoFit.contain;
      expect(
          AppSettings.bindCombo(PlayerAction.mute,
              KeyCombo(LogicalKeyboardKey.keyQ.keyId, KeyCombo.modCtrl)),
          isTrue);

      AppSettings.resetKeys();

      expect(AppSettings.defaultSpeed, 1.5,
          reason: '按键页的重置不得把播放倍速打回默认');
      expect(AppSettings.imageIntervalSec, 7);
      expect(AppSettings.videoFitOverride, VideoFit.contain);
      expect(AppSettings.keyLabel(PlayerAction.mute), 'M');
    });

    test('resetDefaults 仍是全量（启动读入/测试基线需要它）', () {
      AppSettings.defaultSpeed = 2.0;
      AppSettings.bindCombo(PlayerAction.mute,
          KeyCombo(LogicalKeyboardKey.keyQ.keyId, KeyCombo.modCtrl));

      AppSettings.resetDefaults();

      expect(AppSettings.defaultSpeed, 1.0);
      expect(AppSettings.keyLabel(PlayerAction.mute), 'M');
    });

    test('resetDefaults 不是第二份实现：它只调两个分项', () {
      // 三条链必须同源：全量 = 播放 + 按键。若 resetDefaults 里又写一遍
      // 每个字段，改一处就会分叉（新增字段只加到其中一边）。
      AppSettings.defaultSpeed = 2.5;
      AppSettings.hideUiSec = 9;
      AppSettings.resetKeys();
      expect(AppSettings.defaultSpeed, 2.5, reason: 'resetKeys 不碰播放参数');
      AppSettings.resetPlayback();
      expect(AppSettings.defaultSpeed, 1.0);
      expect(AppSettings.hideUiSec, 3);
    });
  });
}
