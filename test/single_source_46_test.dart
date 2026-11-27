/// 第六十六批契约（0.9.289）：**同一件事在页面里没有名字**。
///
/// 第六十三到六十五批收的是「同段代码抄多份」「同一记录两个模型」「同一个
/// 数字两种说法」。这一批抓的是另一类：**页面自己办了一件本该有名字的事**，
/// 于是没有第二个副本可对比，只有一个“看起来合理”的默认值在悄悄替代真实几何。
///
/// 1. 作者头像首屏预热在 `main.dart` 里有两份（排行榜 `avatar` 键 / 作者网格
///    `av` 键），空路径排法、`w=` 宽度、解码宽度公式三处判定各写一遍。
/// 2. `firstScreenRowCount` 的 `rowExtent` 默认 72，而排行榜实测行步进是
///    68（`AuthorRankTile` 67 + 1dp 分隔线）——预热多算约 7%，最后一行在
///    屏幕外。调用方不写参数也能编过，这就是第二份几何。
/// 3. `_PlayerTopNotice` 的 `top: pad.top + 58`：58 是 8 + 48 + 2 算出来的
///    第三个数字，与顶部工具栏 48 / 任务栏 48 毫无关系，却看起来像同一套。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_grid.dart' show avatarDecodeWidth;
import 'package:shoucangjia/avatar_prefetch.dart';
import 'package:shoucangjia/card_metrics.dart';
import 'package:shoucangjia/player_controls.dart';
import 'package:shoucangjia/thumb_prefetch.dart';

/// 去掉整行注释后再做「有没有第二个实现」的扫描。
String _code(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('作者头像首屏预热只有一个实现（0.9.289）', () {
    test('页面不再自己拼 w= / 自己调 prefetchThumbItems', () {
      final src = _code('lib/main.dart');
      expect(src.contains('prefetchThumbItems('), isFalse,
          reason: '头像预热已收口到 avatar_prefetch');
      expect(src.contains('ThumbPrefetch.instance.run('), isFalse);
      expect(src.contains('ThumbPrefetch.instance.runWith('), isFalse);
      // 两个预热入口都必须转发。
      expect(src.contains('prefetchAvatarItems('), isTrue);
      expect(src.contains('void _prefetchRankAvatars'), isTrue);
      expect(src.contains('void _prefetchAvatars'), isTrue);
    });

    test('唯一实现收在 avatar_prefetch，且走同一个缩图宽度', () {
      final src = _code('lib/avatar_prefetch.dart');
      expect(src.contains('List<ThumbPrefetchItem> avatarPrefetchRequests('),
          isTrue);
      expect(src.contains('int prefetchAvatarItems('), isTrue);
      expect(src.contains('withImageWidth('), isTrue);
      expect(src.contains('kAvatarImageWidth'), isTrue);
      expect(src.contains('avatarDecodeWidth('), isTrue);
      expect(src.contains('prefetchThumbItems('), isTrue);
    });

    test('空路径/纯空白不占额度，非空路径带上 w= 与鉴权头', () {
      final asked = <String>[];
      final reqs = avatarPrefetchRequests(
        [
          (path: '', lib: 'L1'),
          (path: '   ', lib: 'L1'),
          (path: 'a.jpg', lib: 'L1'),
          (path: 'b.png', lib: 'L2'),
          (path: 'c.jpg', lib: 'L2'),
        ],
        limit: 2,
        urlOf: (path, lib) {
          asked.add('$lib:$path');
          return '/media/$lib/$path';
        },
        headersOf: (lib) => {'Authorization': 'Basic $lib'},
      );
      expect(reqs.length, 2, reason: 'limit 指非空头像的张数');
      expect(asked, ['L1:a.jpg', 'L2:b.png'],
          reason: '空路径必须在 urlOf 之前排掉（cfg.mediaUrl(\'\') 是服务器根地址）');
      // 地址必须带上头像缩图宽度，鉴权头随图走。
      expect(reqs.first.url, '/media/L1/a.jpg?w=200');
      expect(reqs.first.headers['Authorization'], 'Basic L1');
      expect(reqs.last.headers['Authorization'], 'Basic L2');
    });

    test('解码宽度按头像显示尺寸算，不是按列表行高', () {
      // 42dp × 2 = 84；若误用行高 67.6 会得到 135.2。
      expect(avatarDecodeWidth(displaySize: 42, devicePixelRatio: 2), 84);
      expect(avatarDecodeWidth(displaySize: 58, devicePixelRatio: 2), 116);
      expect(avatarDecodeWidth(displaySize: 42, devicePixelRatio: 2),
          isNot(avatarDecodeWidth(displaySize: kAuthorRankTileHeight, devicePixelRatio: 2)));
    });
  });

  group('排行榜行步进只有一处（0.9.289）', () {
    test('行高与分隔线合成行步进 68.6', () {
      // 0.9.343：行高是测出来的 67.6，不是整数 67（词条块 14.6dp 后
      // `ListTile` 算出的真实高度带小数）。
      expect(kAuthorRankTileHeight, closeTo(67.6, 1e-9));
      expect(kAuthorRankDividerHeight, 1);
      expect(kAuthorRankRowExtent, closeTo(68.6, 1e-9));
    });

    test('firstScreenRowCount 不再有默认行高（调用方必须给几何）', () {
      final src = _code('lib/thumb_prefetch.dart');
      expect(RegExp(r'double rowExtent = ').hasMatch(src), isFalse,
          reason: '一个“看起来合理”的默认值就是第二份几何');
      expect(RegExp(r'required double rowExtent').hasMatch(src), isTrue);
      // 排行榜传的必须是尺寸表那一份。
      final main = _code('lib/main.dart');
      expect(main.contains('rowExtent: kAuthorRankRowExtent'), isTrue);
      // 页面里不准再出现不带 rowExtent 的调用。
      final calls = RegExp(r'firstScreenRowCount\(').allMatches(main).length;
      final withExtent =
          RegExp(r'firstScreenRowCount\([\s\S]{0,160}?rowExtent:').allMatches(main).length;
      expect(calls, withExtent, reason: '每个调用点都必须显式给出 rowExtent');
    });

    test('68 与旧的 72 算出不同行数（差异真实存在，不是等价改写）', () {
      final now = firstScreenRowCount(
          viewportHeight: 800, rowExtent: kAuthorRankRowExtent);
      final old = firstScreenRowCount(viewportHeight: 800, rowExtent: 72);
      expect(now, greaterThanOrEqualTo(old),
          reason: '行距更小 → 同样高度能放更多行');
    });
  });

  group('播放页提示条下移量只有一个出处（0.9.289）', () {
    test('58 不再是字面量，而是三个数字的合成', () {
      expect(kPlayerNoticeTop, 58);
      expect(kPlayerNoticeTop,
          kStageToolbarTopOffset + kStageToolbarRowHeight + kStageToolbarRowGap);
      expect(kStageToolbarTopOffset, 8);
      expect(kStageToolbarRowHeight, 48);
      expect(kStageToolbarRowGap, 2);
    });

    test('播放页不再写 pad.top + 58', () {
      final main = _code('lib/main.dart');
      expect(main.contains('pad.top + 58'), isFalse);
      expect(main.contains('kPlayerNoticeTop'), isTrue);
      // 顶部图标行的上边距也读同一个常量。
      expect(main.contains('pad.top + kStageToolbarTopOffset'), isTrue);
    });

    test('非全屏图标按钮的边长只来自 kStageButtonExtent', () {
      final src = _code('lib/player_controls.dart');
      expect(kStageButtonExtent, 40);
      expect(RegExp(r'width: 40,').hasMatch(src), isFalse,
          reason: '边长只在常量里出现一次');
      expect(RegExp(r'height: 40,').hasMatch(src), isFalse);
      expect(src.contains('kStageButtonExtent'), isTrue);
    });
  });
}
