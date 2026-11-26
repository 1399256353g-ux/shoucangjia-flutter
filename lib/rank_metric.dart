// 排行榜「数值类型 + 数值」的唯一排版出口。
//
// owner 2026-11-27：「各个地方固定下数字和数值类型的位置啊，数值类型统一在
// 数字前面」。此前两个榜各写一份，且**切换排行方式时数字会换位置**：
//
// | 位置 | 播放量榜 | 小水滴榜 |
// |---|---|---|
// | 作者榜 trailing | `2000`（无类型） | `💧 4`（emoji 当类型） |
// | 各库榜副标题 | `2000 播放 · 4 水滴` | `播放 2000 · 4 水滴` |
//
// 第二行是最刺眼的一处：同一个 2000，切一次指标就从行首跑到「播放」后面。
// 类型在前、数字固定宽度，两页共用，切换指标只换类型文字，数字不挪。
library;

import 'package:flutter/material.dart';

/// 排行榜数值格子的固定宽度（作者榜/各库榜共用）。
///
/// 固定宽度是这条规则的核心：分数位数在 3–7 位之间变化（`999` / `1234567`），
/// 若按内容撑开，右侧对齐的数字仍会左右平移。
const double kRankScoreWidth = 84;

/// 分数格子：类型文字在上、数字在下，两者都固定在这块宽度内。
///
/// 类型永远在数字**前面**（此处是上方，明细行里是左侧），不用 emoji 代替：
/// `💧 4` 与 `4` 的宽度差导致整列数字对不齐。
class RankScoreCell extends StatelessWidget {
  /// 数值类型：`播放量` / `小水滴`。
  final String label;
  final int value;
  final Color color;

  const RankScoreCell({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kRankScoreWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text('$value',
              maxLines: 1,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

/// 明细行：数值类型在前，切换指标时任何一个数字都不换位置。
///
/// `works` 为空时不输出作品数（各库榜没有这一项）。
String rankDetailLine({
  required int plays,
  required int drops,
  int? works,
}) {
  final parts = <String>['播放 $plays', '水滴 $drops'];
  if (works != null) parts.add('$works 作品');
  return parts.join(' · ');
}
