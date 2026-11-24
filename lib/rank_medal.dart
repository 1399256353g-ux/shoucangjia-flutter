// 名次配色（金/银/铜）的唯一实现。
//
// `main.dart` 里原本有两个**逐字相同**的私有 `_rankColor`：
// 作者排行榜 `_RankPageState` 与各库排行榜 `_LibraryRankPageState` 各写一份
// （金 `0xFFFFC107` / 银 `0xFFB0BEC5` / 铜 `0xFFBF8970` / 其余按主题）。
// 两处同值不是巧合而是复制：只要有人调了其中一处，两个榜单的名次颜色就会分叉，
// 而这种「两个页面颜色不一样」的差异几乎不会被当成 bug 报上来。
//
// 这里只保留「前三是奖牌色，其余跟随主题」这一条规则。

import 'package:flutter/material.dart';

/// 名次奖牌色：0 = 金，1 = 银，2 = 铜。[index] 越界时返回 null（调用方用主题色）。
Color? rankMedalColor(int index) {
  switch (index) {
    case 0:
      return const Color(0xFFFFC107);
    case 1:
      return const Color(0xFFB0BEC5);
    case 2:
      return const Color(0xFFBF8970);
    default:
      return null;
  }
}

/// 榜单行名次颜色：前三用奖牌色，其余用主题的次要前景色。
Color rankColorFor(BuildContext context, int index) =>
    rankMedalColor(index) ?? Theme.of(context).colorScheme.onSurfaceVariant;
