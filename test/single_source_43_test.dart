/// 第六十三批契约：**同一个几何数字、同一个键字符串各写多份**。
///
/// 前几批抓的是「同一段代码抄多份」与「同一条记录两个模型」。这一批抓的是
/// **数字与分隔符**这一类更不起眼的重复：
///
/// 1. `unit_library_view` 的 `_prefetchCovers` 有三份（主页/星标页/单元库页），
///    三份的「张数上限 / 去重方式 / 纵向内边距」各不相同，而它们各自都
///    「算得出一个数」——只有对比两个页面的预热张数才会发现。
/// 2. 同一组网格参数（260/10/1.02、220/10/0.92）在 `gridDelegate` 与
///    `firstScreenThumbCount` 两处各写一遍。改一处、漏一处，预热的就是
///    另一批格子：多算一列＝白拉一列看不见的封面，少算＝首屏仍然逐张请求。
/// 3. 节点键 `'<连接>␁<rel>'` 在 `unit_library._nodeKeyOf` /
///    `multi_server.unitCoverKey` / `unit_cover_store._keyOf` 三处各拼一遍，
///    `main.dart` 还反向手拆一次；分隔符常量另有一份字面量。
///    三处必须是同一个字符串，否则封面键与树节点键对不上——
///    表现是「设了封面、返回界面又没了」，而两处各自都自洽。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/decode_plan.dart';
import 'package:shoucangjia/grid_spec.dart';
import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/node_key.dart';
import 'package:shoucangjia/thumb_prefetch.dart';

/// 去掉整行注释后再做「有没有第二个实现」的扫描。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('网格规格只有一张表（0.9.286）', () {
    test('页面 delegate 与预热张数读同一份规格', () {
      // 单元库卡片与基础库卡片各自的三个数字，只允许出现在 grid_spec。
      expect(kUnitLibGrid.maxCrossAxisExtent, 260);
      expect(kUnitLibGrid.spacing, 10);
      expect(kUnitLibGrid.aspectRatio, 1.02);
      expect(kBasicLibGrid.maxCrossAxisExtent, 220);
      expect(kBasicLibGrid.spacing, 10);
      expect(kBasicLibGrid.aspectRatio, 0.92);

      final delegate = kUnitLibGrid.delegate;
      expect(delegate.maxCrossAxisExtent, kUnitLibGrid.maxCrossAxisExtent);
      expect(delegate.mainAxisSpacing, kUnitLibGrid.spacing);
      expect(delegate.crossAxisSpacing, kUnitLibGrid.spacing);
      expect(delegate.childAspectRatio, kUnitLibGrid.aspectRatio);
    });

    test('三个库网格页面都不得再手写字面量 delegate', () {
      final src = _code('lib/unit_library_view.dart');
      // 旧写法：`gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(`
      // 后面跟 260/220 与 1.02/0.92。删除后三处全部走 `kXxxGrid.delegate`。
      expect(src.contains('SliverGridDelegateWithMaxCrossAxisExtent('), isFalse,
          reason: '页面里又有一个手写 delegate，数字会与预热各写一份');
      expect(RegExp(r'kUnitLibGrid\.delegate').allMatches(src).length, 3);
      expect(RegExp(r'kBasicLibGrid\.delegate').allMatches(src).length, 1);
      // 旧常量不得复活：间距已经进规格表。
      expect(RegExp(r'kLibGridSpacing').hasMatch(src), isFalse);
    });

    test('预热张数：规格 + 真实 padding 算出与 delegate 一致的列数', () {
      // 400 宽、左右各 12 → 可用 376；ceil(376/270) = 2 列，
      // 列宽 (376-10)/2 = 183，行高 183/1.02 ≈ 179.4，步长 ≈ 189.4；
      // 800 高 → 5 行 → 10 张（上限放宽到 20 才看得见几何本身）。
      expect(
          kUnitLibGrid.prefetchCount(const Size(400, 800),
              padding: const EdgeInsets.symmetric(horizontal: 12), maxItems: 20),
          10);
      // 900 宽 → 可用 876，ceil(876/270) = 4 列；300 高 → 2 行 → 8 张。
      expect(
          kUnitLibGrid.prefetchCount(const Size(900, 300),
              padding: const EdgeInsets.symmetric(horizontal: 12), maxItems: 30),
          8);
      // 基础库卡片 220 更窄：同宽下仍 4 列（876/230 = 3.8 → 4）。
      expect(
          kBasicLibGrid.prefetchCount(const Size(900, 300),
              padding: const EdgeInsets.symmetric(horizontal: 12), maxItems: 30),
          8);
      // 且与 `firstScreenThumbCount` 同源：同样的参数必须得出同一个数。
      expect(
          kUnitLibGrid.prefetchCount(const Size(900, 300),
              padding: const EdgeInsets.symmetric(horizontal: 12), maxItems: 30),
          firstScreenThumbCount(
            viewportWidth: 900,
            viewportHeight: 300,
            maxCrossAxisExtent: 260,
            paddingX: 12,
            paddingY: 0,
            crossSpacing: 10,
            mainSpacing: 10,
            aspectRatio: 1.02,
            screens: 1,
            maxItems: 30,
          ));
    });

    test('上下内边距各自取一半，不再拿左右值顶替', () {
      // 星标页真实 padding 是 fromLTRB(12,12,12,24)：上下合计 36。
      // 旧写法传 `padding: kLibGridPadding.left`（＝12），把可用高度算大 24：
      // 600×400 下真实是 3 列 × 2 行 = 6 张，旧写法算成 3 列 × 3 行（封顶 8），
      // 多预热的那 2 张在首屏之外。
      const real = EdgeInsets.fromLTRB(12, 12, 12, 24);
      expect(real.vertical, 36);
      expect(
          kUnitLibGrid.prefetchCount(const Size(600, 400), padding: real), 6);
      expect(
          kUnitLibGrid
              .prefetchCount(const Size(600, 400),
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
          8,
          reason: '旧口径把上下也当成 12 → 多算一行');
    });

    test('非有限视口不抛（规格入口同样受取整兜底约束）', () {
      for (final v in <Size>[
        const Size(double.nan, 800),
        const Size(400, double.infinity),
        const Size(-100, -100),
        Size.zero,
      ]) {
        expect(() => kUnitLibGrid.prefetchCount(v, padding: EdgeInsets.zero),
            returnsNormally);
      }
    });
  });

  group('库卡片预热只有一个实现（0.9.286）', () {
    test('页面不再自己拼 URL / 自己去重 / 自己调 ThumbPrefetch', () {
      final src = _code('lib/unit_library_view.dart');
      expect(src.contains('ThumbPrefetch.instance.run('), isFalse,
          reason: '页面又自己预热了一次，几何会与 grid_spec 分叉');
      expect(src.contains('thumbImageProvider('), isFalse,
          reason: 'provider 构造只允许在 lib_card_prefetch 里');
      expect(RegExp(r'firstScreenThumbCount\(').hasMatch(src), isFalse,
          reason: '张数只允许由 LibGridSpec.prefetchCount 算');
      expect(RegExp(r'prefetchLibCovers\(').allMatches(src).length, 4,
          reason: '主页 1 + 星标页 1 + 单元库页 2（下级/基础库）');
      // 星标页的网格与预热用同一个 padding 常量（声明 1 + 网格 1 + 预热 1）。
      expect(RegExp(r'kStarredGridPadding').allMatches(src).length, 3);
    });

    test('预热用的解码宽度与卡片渲染同一个函数', () {
      final src = _code('lib/lib_card_prefetch.dart');
      expect(src.contains('decodeWidth'), isTrue);
      // 卡片侧（_UnitCoverFill）也不得再内联 decodeWidthForDisplay。
      final view = _code('lib/unit_library_view.dart');
      expect(view.contains('decodeWidthForDisplay('), isFalse,
          reason: '卡片内联公式会让缓存键与预热分叉');
      // 0.9.288：显示宽度与公式都收到网格规格——页面里不许再出现
      // 「自己挑一个 220/260 再算解码宽度」的写法。
      expect(RegExp(r'libCardDecodeWidthOf\(').hasMatch(view), isFalse,
          reason: '解码宽度只允许经 LibGridSpec.decodeWidth');
      expect(RegExp(r'\.decodeWidth\(').allMatches(view).length, 5,
          reason: '卡片 1 处 + 三页预热 4 处');
    });

    test('解码宽度：按真实显示宽度算，220 与 260 不同', () {
      expect(libCardDecodeWidthOf(220, 2), 440);
      expect(libCardDecodeWidthOf(260, 2), 520);
      // 上限仍是 3x（`ceilDim(displayWidth * 3)`），4x 屏不无限放大。
      expect(libCardDecodeWidthOf(220, 4), 660);
      expect(libCardDecodeWidthOf(260, 4), 780);
      // 非有限/零宽度按「不缩放」的旧口径返回 0，不抛。
      expect(libCardDecodeWidthOf(220, double.nan), 220);
      expect(libCardDecodeWidthOf(double.nan, 2), 0);
    });
  });

  group('节点键只有一处拼装（0.9.286）', () {
    test('分隔符是控制字符，拼接后不同 (连接, rel) 不会撞键', () {
      expect(kNodeKeySep, '\u0001');
      // `|` 出现在 rel 里也不会与「连接分隔」混淆。
      final a = nodeKey('s1', 'A|B');
      expect(a.contains(kNodeKeySep), isTrue);
      expect(nodeKeyServerId(a), 's1');
      expect(nodeKeyRel(a), 'A|B');
      // 同名 rel、不同连接：两个不同的键。
      expect(nodeKey('s1', '(1) 抖音'), isNot(nodeKey('s2', '(1) 抖音')));
      // 连接两侧空白等价。
      expect(nodeKey(' s1 ', 'A'), nodeKey('s1', 'A'));
    });

    test('反向解析与拼装对称：三处键必须逐字相同', () {
      const sid = 'srv-2';
      const rel = '(1) A/(2) B';
      final tree = nodeKey(sid, rel);
      // 封面表键（multi_server）必须与树节点键一模一样。
      expect(unitCoverKey(sid, rel), tree);
      // 归一化写法（服务端原始 rel 带反斜杠/点段）落到同一个键。
      expect(unitCoverKey(sid, r'(1) A\.\(2) B'), tree);
      expect(nodeKeyNormalized(sid, r'(1) A\.\(2) B'), tree);
      // 归属判定用同一个键。
      expect(nodeKeyHasServer(tree, sid), isTrue);
      expect(nodeKeyHasServer(tree, 'srv-3'), isFalse);
    });

    test('格式不对的键不静默当成「连接为空」', () {
      expect(nodeKeyServerId('A/B'), '');
      expect(nodeKeyRel('A/B'), '');
      expect(nodeKeyHasServer('A/B', ''), isFalse,
          reason: '没有分隔符的旧键不能被认作「空连接的节点」');
    });

    test('契约：分隔符字面量与手拆不得复活', () {
      // 分隔符只允许在 node_key.dart 里出现一次（字面量）。
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final name = f.uri.pathSegments.last;
        if (name == 'node_key.dart') continue;
        if (_code(f.path).contains(r"'\u0001'")) offenders.add(name);
      }
      expect(offenders, isEmpty, reason: '分隔符字面量又出现在: $offenders');

      // 手拆键（startsWith 连接前缀 / indexOf 分隔符）不得复活。
      final mainSrc = _code('lib/main.dart');
      expect(mainSrc.contains(r"k.startsWith('$markedSid"), isFalse);
      expect(mainSrc.contains(r"k.substring(k.indexOf("), isFalse);
      expect(mainSrc.contains('nodeKeyHasServer('), isTrue);
      expect(mainSrc.contains('nodeKeyRel('), isTrue);
    });

    test('树节点键与封面键各只有一处实现', () {
      final lib = _code('lib/unit_library.dart');
      // `_nodeKeyOf` 只剩转发，不再自己拼字符串。
      expect(lib.contains(r"'${serverId.trim()}\u0001$rel'"), isFalse);
      expect(lib.contains('nodeKey(serverId, rel)'), isTrue);

      final ms = _code('lib/multi_server.dart');
      expect(ms.contains(r"'${serverId.trim()}\u0001"), isFalse);
      expect(ms.contains('nodeKey(serverId, normalizeUnitRel(rel))'), isTrue);

      // 封面 store 仍带命名空间前缀，但分隔符必须是同一个常量。
      final store = _code('lib/unit_cover_store.dart');
      expect(store.contains('kNodeKeySep'), isTrue);
      expect(store.contains(r"'$ns:${scope.trim()}$_sep$id'"), isTrue);
    });
  });
}
