// 第九十七批（0.9.342）契约：
//   1. 边框粗细不得改变词条占位面积（底纹在 decoration、边框在
//      foregroundDecoration；内边距固定）。
//   2. 词条文字在词条区域居中。
//   3. 媒体库词条真正贴到作者卡/基础库卡（owner 2026-11-27 第四次提出）。
//   4. 媒体库名只认本份元数据，不读进程级 `TopNodeName`（两台服务器会串名）。
//
// 隐私：全部用合成 id/名字（`t1` / `lib-x` / `@a`），不读任何真实目录名，
// 不涉及截图或媒体内容。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/author_badge_row.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/card_metrics.dart';
import 'package:shoucangjia/grid_spec.dart';
import 'package:shoucangjia/main.dart'
    show AuthorAvatar, AuthorBadges, AuthorGridCard, LibMeta, UnitBadges;
import 'package:shoucangjia/top_node.dart';
import 'package:shoucangjia/unit_library.dart';

BasicLib b(String id, String rel) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 3,
    );

/// 两台服务器各自的媒体库根：`T1` 属于 s1，`T2` 属于 s2。
UnitLibrary twoServers() => buildUnitTree(
      nodes: const [
        LibNode(id: 'T1', rel: 'T1', name: 'T1', serverId: 's1', serverLabel: 'A'),
        LibNode(id: 'T2', rel: 'T2', name: 'T2', serverId: 's2', serverLabel: 'B'),
      ],
      basics: [
        BasicLib(
            id: 'b1', name: 'b1', rel: 'T1/x', bigId: '', authors: 1, works: 3,
            serverId: 's1', serverLabel: 'A'),
        BasicLib(
            id: 'b2', name: 'b2', rel: 'T2/y', bigId: '', authors: 1, works: 3,
            serverId: 's2', serverLabel: 'B'),
      ],
      topName: 'ROOT',
    )!;

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LibraryBadge.load();
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.topOfUnit.clear();
    LibraryBadge.parentOfUnit.clear();
    UnitBadgeRegistry.order.clear();
    UnitBadgeRegistry.labels.clear();
    UnitBadgeRegistry.keys.clear();
    TopNodeName.reset();
  });

  group('1. 调粗边框不得改变占位面积', () {
    test('边框只在 foregroundDecoration 里，decoration 不带 border', () {
      for (final k in LibEntryKind.values) {
        final fill = LibraryBadge.fillDecorationFor(k, 0xFF336699);
        expect(fill.border, isNull, reason: '底纹层不得带边框（会撑大内容）');
        final border = LibraryBadge.borderDecorationFor(k);
        expect(border.border, isNotNull);
        expect(border.color, isNull, reason: '边框层不得再画底纹');
      }
    });

    test('同一层级把边框从 0.5 调到 3.0，圆角/底纹完全不变', () {
      LibraryBadge.entryStyle[LibEntryKind.basic] = LibraryBadge
          .styleFor(LibEntryKind.basic)
          .copyWith(borderWidth: 0.5);
      final thin = LibraryBadge.fillDecorationFor(LibEntryKind.basic, 0xFF112233);
      LibraryBadge.entryStyle[LibEntryKind.basic] = LibraryBadge
          .styleFor(LibEntryKind.basic)
          .copyWith(borderWidth: 3.0);
      final thick = LibraryBadge.fillDecorationFor(LibEntryKind.basic, 0xFF112233);
      expect((thick.color as Color).toARGB32(), (thin.color as Color).toARGB32());
      expect((thick.borderRadius as BorderRadius).topLeft.x,
          (thin.borderRadius as BorderRadius).topLeft.x);
      expect((LibraryBadge.borderDecorationFor(LibEntryKind.basic).border
              as Border)
          .top
          .width, closeTo(3.0, 1e-9));
    });

    testWidgets('词条实测尺寸不随边框粗细变化（渲染级）', (t) async {
      Future<Size> measure(double width) async {
        LibraryBadge.entryStyle[LibEntryKind.unit] = LibraryBadge
            .styleFor(LibEntryKind.unit)
            .copyWith(borderWidth: width);
        await t.pumpWidget(host(Center(
          child: LibBadgeChip(label: 'lib-x', color: 0xFF336699),
        )));
        await t.pump();
        return t.getSize(find.byType(LibBadgeChip));
      }

      final thin = await measure(0.0);
      final thick = await measure(3.0);
      expect(thick.width, closeTo(thin.width, 0.01),
          reason: '边框画在前景层，不能挤内容也不能改变占位');
      expect(thick.height, closeTo(thin.height, 0.01));
    });
  });

  group('2. 词条文字居中', () {
    testWidgets('文本在词条区域内水平垂直居中', (t) async {
      await t.pumpWidget(host(Center(
        child: LibBadgeChip(label: 'lib-x', color: 0xFF336699),
      )));
      final chip = t.getRect(find.byType(LibBadgeChip));
      final txt = t.getRect(find.text('lib-x'));
      expect(txt.center.dx, closeTo(chip.center.dx, 0.6));
      expect(txt.center.dy, closeTo(chip.center.dy, 0.6));
    });
  });

  group('3. 媒体库词条贴到作者卡/基础库卡', () {
    testWidgets('作者词条：媒体库 → 单元库 双级都在', (t) async {
      final tree = twoServers();
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
      await t.pumpWidget(host(UnitBadges(
        meta: meta,
        mediaPath: '',
        basicId: 'b1',
      )));
      // 媒体库词条（来自媒体库根）与单元库词条两级都在，且媒体库在最前。
      // 末尾还有一个折叠基础库的 `▾N`（它的数字不是词条）。
      final texts = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .where((s) => !RegExp(r'^\d+$').hasMatch(s))
          .toList();
      expect(texts.length, 2, reason: '媒体库 + 单元库两级词条');
      expect(texts.any((s) => s.contains('media:')), isFalse,
          reason: '内部键不得出现在词条文字里');
      expect(t.getRect(find.text(texts[0])).left,
          lessThanOrEqualTo(t.getRect(find.text(texts[1])).left));
    });

    testWidgets('媒体库词条带名字，不是内部 id', (t) async {
      final tree = twoServers();
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
      final media = mediaRootForBasic(tree, 'b1');
      expect(media, isNotNull);
      expect(meta.mediaIdFor(meta.basicToUnit['b1'] ?? ''), media!.id);
      final label = meta.topNameOf(media.id);
      expect(label.isNotEmpty, isTrue);
      expect(label.contains('media:'), isFalse,
          reason: '内部键绝不能出现在词条文字里');
    });

    testWidgets('基础库页作者卡带媒体库词条（调用方注入）', (t) async {
      await t.pumpWidget(host(AuthorBadgeRow(
        unitLabel: 'x',
        unitId: 'T1/x',
        extraChips: const <BadgeChipSpec>[
          BadgeChipSpec(
              label: 'MEDIA', color: 0xFF1D4ED8, unitId: 'media:s1',
              kind: LibEntryKind.top),
        ],
      )));
      expect(find.text('x'), findsOneWidget);
      expect(find.text('MEDIA'), findsOneWidget);
      // 媒体库词条必须排在最前（层级从高到低）。
      final mediaRect = t.getRect(find.text('MEDIA'));
      final unitRect = t.getRect(find.text('x'));
      expect(mediaRect.left, lessThanOrEqualTo(unitRect.left));
    });
  });

  group('3b. 单连接旧形态不贴媒体库词条（不编造一级）', () {
    test('树里没有媒体库层时 mediaIdFor 返回空串', () {
      // 单连接：root 的直接子节点就是单元库自己，没有 media: 这一层。
      final tree = buildUnitTree(
        nodes: const [LibNode(id: 'U1', rel: 'U1', name: 'U1')],
        basics: [b('bx', 'U1/x')],
        topName: 'ROOT',
      )!;
      expect(tree.children.any((c) => c.isMediaRoot), isFalse);
      final meta = LibMeta(
        basics: tree.allBasics,
        allBasics: tree.allBasics,
        stats: const {},
        unitTree: tree,
        units: flattenUnits(tree),
        basicToUnit: unitOfBasics(tree),
        topName: 'ROOT',
      );
      expect(meta.mediaIdFor('U1'), '');
    });

    testWidgets('只有一个单元库词条时不出现重复的一级', (t) async {
      final tree = buildUnitTree(
        nodes: const [LibNode(id: 'U1', rel: 'U1', name: 'U1')],
        basics: [b('bx', 'U1/x')],
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
      await t.pumpWidget(host(UnitBadges(meta: meta, mediaPath: '', basicId: 'bx')));
      final texts = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .where((s) => !RegExp(r'^\d+$').hasMatch(s))
          .toList();
      expect(texts, <String>['U1']);
    });
  });

  group('3c. 固定尺寸作者卡：两级词条不换行、不压头像', () {
    testWidgets('150dp 作者卡里媒体库+单元库词条仍是一行', (t) async {
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'T1', rel: 'T1', name: '媒体库根名字很长很长很长', serverId: 's1', serverLabel: 'A'),
          LibNode(id: 'T1/u', rel: 'T1/u', name: '单元库名字很长很长很长', serverId: 's1'),
        ],
        basics: [b('b1', 'T1/u/x')],
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
      await t.pumpWidget(host(Center(
        child: SizedBox(
          width: 150,
          height: kAuthorCardExtent,
          child: AuthorGridCard(
            name: '某作者',
            avatar: '',
            lib: 'b1',
            meta: meta,
            stats: const {},
            works: 12,
            subtitle: '12 作品',
          ),
        ),
      )));
      await t.pump();
      expect(t.takeException(), isNull);
      final badges = t.getRect(find.byType(AuthorBadges));
      final avatar = t.getRect(find.byType(AuthorAvatar));
      // 词条块底边必须在头像顶边之上（否则两行词条压住头像）。
      expect(badges.bottom, lessThanOrEqualTo(avatar.top),
          reason: '词条行高必须收在一行里，不能压到头像');
    });

    test('卡片词条上限小于信息区上限（否则两级各占一行）', () {
      expect(kAuthorCardChipMaxWidth, lessThan(kBadgeChipMaxWidth));
    });
  });

  group('4. 媒体库名只认本份元数据', () {
    test('两台服务器各自取自己的根名，不读进程级全局值', () {
      // 全局值被「最后加载那台」写成 T2；s1 的 meta 仍要报它自己的名字。
      TopNodeName.set('T2');
      final tree = twoServers();
      LibMeta metaFor(String own) => LibMeta(
            basics: tree.allBasics,
            allBasics: tree.allBasics,
            stats: const {},
            unitTree: tree,
            units: flattenUnits(tree),
            basicToUnit: unitOfBasics(tree),
            topName: own,
          );
      // 两张卡片各自的名字来自自己那条连接，不同台不同名。
      expect(metaFor('T1').topNameOf('media:s1'),
          isNot(metaFor('T2').topNameOf('media:s2')));
      expect(TopNodeName.current, 'T2');
    });

    test('拿不到名字时回落 id，不回落进程级全局名', () {
      TopNodeName.set('别人家的库根');
      const meta = LibMeta(basics: <BasicLib>[], stats: <String, dynamic>{});
      expect(meta.topNameOf('media:zz'), 'media:zz');
    });
  });
}
