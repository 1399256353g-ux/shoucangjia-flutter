/// 第七十批契约（0.9.292）：**量出来的数字 vs 猜出来的数字**。
///
/// 前几批抓的是「同一件事两处各写一份」「同一记录两个模型」。这一批抓的是
/// 更不容易被看见的一类：**尺寸是量的，用来解码的数字却是猜的**。
///
/// 1. 「按屏幕宽度解码」在播放页有两份实现：
///    `_posterDecodeWidth` 是 `roundDim(w*dpr, fallback:360).clamp(360,2160)`，
///    图文原图 `picView` 是 `roundDim(w*dpr, fallback:1080)` **没有上限**。
///    宽屏/NaN 时同一张图在两个页面就是两个缓存键。
/// 2. 删除记录缩略图：尺寸 56 写三遍、解码宽度内联 `160`——既不是 56×2(112)
///    也不是 56×3(168)，是一个「看起来差不多」的中间数。
/// 3. 作者「选一张作头像」弹窗：格子实际 136dp（420 宽 / 3 列 / 6 间距），
///    解码宽度却按 96dp 算 —— 小图放大 1.4 倍显示。
/// 4. 邻页预载的 `precacheImage` 用 `CachedNetworkImageProvider(maxWidth:)`，
///    而邻页渲染是 `CachedNetworkImage(memCacheWidth:)`（= `ResizeImage` 包一层）。
///    两者缓存键不同 → 预载拉回来的图滑入时仍「没命中」，再下一次。
/// 5. 作者总览页的网格 `padding` 与预热 `padding` 各写一份
///    `fromLTRB(12, 4, 12, 16)`；基础库页作者 tab 同理（两个数字各拼一遍）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_index.dart'
    show
        authorGridPadRight,
        basicAuthorGridPadding,
        kAuthorGridPadLeft,
        kAuthorGridPadRight,
        kAuthorGridPagePadding,
        kAuthorIndexBarGap,
        kAuthorIndexBarWidth;
import 'package:shoucangjia/card_metrics.dart';
import 'package:shoucangjia/decode_plan.dart';

/// 去掉整行注释后再做「有没有第二个实现」的扫描。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('按屏幕宽度解码只有一个公式（0.9.292）', () {
    test('公式本身：向上取整、夹在 min..max 之间', () {
      // 390dp × 3 = 1170
      expect(
          screenDecodeWidth(viewportWidth: 390, devicePixelRatio: 3), 1170);
      // 小窗按 360 兜底（不会是 0 或负数）
      expect(screenDecodeWidth(viewportWidth: 100, devicePixelRatio: 1), 360);
      // 大屏夹在 2160：1600dp × 3 = 4800 → 2160
      expect(
          screenDecodeWidth(viewportWidth: 1600, devicePixelRatio: 3), 2160);
      // 非有限视口/像素比不抛
      expect(screenDecodeWidth(viewportWidth: double.nan, devicePixelRatio: 3),
          360);
      // dpr 非有限时按 1.0 处理（不是「无上限放大」）。
      expect(
          screenDecodeWidth(
              viewportWidth: 390, devicePixelRatio: double.infinity),
          390);
      // 小数按 `roundDim` 四舍五入（沿用 0.9.25 定的口径，不另立一套）
      expect(
          screenDecodeWidth(viewportWidth: 100.2, devicePixelRatio: 1), 360);
      expect(screenDecodeWidth(viewportWidth: 400.2, devicePixelRatio: 1), 400);
      expect(screenDecodeWidth(viewportWidth: 400.6, devicePixelRatio: 1), 401);
    });

    test('播放页海报与图文原图取同一个值（此前是两份公式）', () {
      final main = _code('lib/main.dart');
      // 两个入口都必须转发。
      expect(main.contains('screenDecodeWidth('), isTrue);
      // 旧的两份实现（各自的兜底值与 clamp）在 lib/ 里不得复活。
      expect(main.contains('clamp(360, 2160)'), isFalse,
          reason: '海报的上下限应在 decode_plan.screenDecodeWidth 里');
      expect(main.contains('fallback: 1080'), isFalse,
          reason: '图文原图的 1080 兜底与海报的 360 是两个说法');
      // 全 lib 只有 decode_plan 定义这个公式。
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        // Windows CI 上的分隔符是 `\`，不能只按 `/` 拆。
        final name = f.path.split(RegExp(r'[\\/]')).last;
        if (name == 'decode_plan.dart') continue;
        expect(_code(f.path).contains('int screenDecodeWidth('), isFalse,
            reason: '$name 又写了一份「按屏幕宽度解码」');
      }
    });
  });

  group('小方图缩略图的尺寸与解码宽度同源（0.9.292）', () {
    test('删除记录缩略图：56 与解码宽度来自同一对出口', () {
      expect(kDeletedThumbSize, 56);
      // 3x：56 × 3 = 168（旧的 160 既不是 2x 也不是 3x）
      expect(squareThumbDecodeWidth(56, 3), 168);
      expect(squareThumbDecodeWidth(56, 2), 112);
      expect(squareThumbDecodeWidth(56, 1), 56);
      // 上限 3 倍（4x 屏不无限放大）
      expect(squareThumbDecodeWidth(56, 4), 168);
      // 非有限值不抛
      expect(squareThumbDecodeWidth(56, double.nan), 56);

      final main = _code('lib/main.dart');
      expect(main.contains('memCacheWidth: 160'), isFalse,
          reason: '160 是猜出来的数，应与 56 的显示尺寸同源');
      expect(main.contains('squareThumbDecodeWidth('), isTrue);
      expect(main.contains('kDeletedThumbSize'), isTrue);
    });

    test('头像候选格边长是量的（136），不是 96', () {
      // 420 宽 / 3 列 / 间距 6 → (420 - 12) / 3 = 136
      expect(kAvatarCandidateSize, 136);
      final main = _code('lib/main.dart');
      expect(main.contains('displaySize: 96'), isFalse,
          reason: '96 是猜的，格子实际 136');
      expect(main.contains('displaySize: kAvatarCandidateSize'), isTrue);
      // 格子宽度本身在弹窗里仍是 420/3 列/6 间距（尺寸常量与布局同步）。
      expect(main.contains('width: 420'), isTrue);
      expect(main.contains('crossAxisCount: 3'), isTrue);
      expect(main.contains('mainAxisSpacing: 6'), isTrue);
      expect(main.contains('crossAxisSpacing: 6'), isTrue);
    });
  });

  group('邻页预载与邻页渲染用同一个缓存键（0.9.292）', () {
    test('预载与探比例都走 thumbImageProvider，不再自己建 provider+maxWidth', () {
      final main = _code('lib/main.dart');
      // `_resolveAspect` 与 `_prefetchNeighborCovers` 里的 `maxWidth:` 用法归零。
      expect(main.contains('maxWidth: widget.memCacheWidth'), isFalse,
          reason: '探比例必须与渲染同键（thumbImageProvider）');
      expect(main.contains('maxWidth: memW'), isFalse,
          reason: '预载必须与渲染同键（thumbImageProvider）');
      // 残留的 CachedNetworkImageProvider 只剩「图文原图」那一处（原图不走缩图）。
      final direct = RegExp(r'CachedNetworkImageProvider\(')
          .allMatches(main)
          .length;
      expect(direct, 1, reason: '除图文原图外不得再自己建 provider');
    });

    test('0.9.293：邻页渲染与探比例都读同一个 PlayerImage', () {
      final main = _code('lib/main.dart');
      final i = main.indexOf('class _NeighborPageState');
      final body = main.substring(i, i + 3000);
      expect(body.contains('widget.image.provider('), isTrue,
          reason: '探比例必须向 PlayerImage 要 provider');
      expect(body.contains('memCacheWidth: widget.image.decodeWidth'), isTrue);
      expect(body.contains('widget.imageUrl'), isFalse,
          reason: '邻页不再自己持有地址/头/宽度三个字段');
      expect(body.contains('widget.memCacheWidth'), isFalse);
    });
  });

  group('作者网格内边距只有一个定义（0.9.292）', () {
    test('作者总览页：网格 padding 与预热 padding 是同一常量', () {
      expect(kAuthorGridPagePadding.left, kAuthorGridPadLeft);
      expect(kAuthorGridPagePadding.right, kAuthorGridPadRight);
      expect(kAuthorGridPagePadding.top, 4);
      expect(kAuthorGridPagePadding.bottom, 16);

      final main = _code('lib/main.dart');
      // 作者页那两处（网格 + 预热）都不许再写字面量。它处无关的列表
      // （删除记录/排行/播放记录）不在本契约范围，所以只扫作者页这一段。
      final page = main.substring(
          main.indexOf('class _AuthorGridPageState'),
          main.indexOf('class _AuthorPageState'));
      expect(page.contains('EdgeInsets.fromLTRB(12, 4, 12, 16)'), isFalse,
          reason: '网格与预热各写一份就会分叉');
      expect(main.contains('padding: kAuthorGridPagePadding'), isTrue);
      final prep = main.indexOf('void _prefetchAvatars()');
      expect(
          main.substring(prep, prep + 900)
              .contains('padding: kAuthorGridPagePadding'),
          isTrue,
          reason: '预热必须读同一份内边距');
    });

    test('基础库页作者 tab：左右让位由 authorGridPadRight 决定', () {
      expect(basicAuthorGridPadding(hasIndexBar: true).right,
          kAuthorIndexBarWidth + kAuthorIndexBarGap);
      expect(basicAuthorGridPadding(hasIndexBar: false).right,
          kAuthorGridPadRight);
      expect(basicAuthorGridPadding(hasIndexBar: true).left, kAuthorGridPadLeft);
      expect(basicAuthorGridPadding(hasIndexBar: true).top, 12);
      expect(basicAuthorGridPadding(hasIndexBar: true).bottom, 12);
      // 有索引条时右边必须更宽（让位），否则预热列数会多算。
      expect(basicAuthorGridPadding(hasIndexBar: true).right,
          greaterThan(basicAuthorGridPadding(hasIndexBar: false).right));
      expect(authorGridPadRight(hasIndexBar: true),
          kAuthorIndexBarWidth + kAuthorIndexBarGap);

      final basic = _code('lib/basic_lib_page.dart');
      // 本页两处（网格 + 预热）都只调这一个函数。
      expect(
          RegExp(r'basicAuthorGridPadding\(hasIndexBar:')
              .allMatches(basic)
              .length,
          2,
          reason: '网格与预热各调一次，不得自己拼 fromLTRB');
      expect(basic.contains('EdgeInsets.fromLTRB(\n              kAuthorGridPadLeft'),
          isFalse);
      expect(basic.contains('EdgeInsets kAuthorGridPagePadding'), isFalse);
    });
  });

  group('播放页图文原图与视频海报同键（0.9.292）', () {
    test('picView 的解码宽度来自 screenDecodeWidth，宽度与海报同值', () {
      final main = _code('lib/main.dart');
      final i = main.indexOf('Widget picView(String path');
      expect(i, greaterThan(0));
      final body = main.substring(i, i + 1200);
      expect(body.contains('screenDecodeWidth('), isTrue);
      expect(body.contains('fallback'), isFalse,
          reason: '兜底值不属于调用点');
      expect(body.contains('roundDim('), isFalse);
    });
  });
}
