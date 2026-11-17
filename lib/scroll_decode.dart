/// 滚动 → 缩略图预取预算联动（不改视觉、不改交互）。
///
/// 把子树的滚动状态上报给 [ThumbPrefetch.instance]：滚动/惯性开始收紧预取
/// 并发（默认 4 → 2），滚动结束立刻恢复。首屏预热在滚动开始前发起，不受
/// 影响；用户只要不动，预取就按常规并发跑完。
library;

import 'package:flutter/widgets.dart';

import 'thumb_prefetch.dart';

class ScrollDecodeScope extends StatelessWidget {
  /// 被观察的滚动区域。
  final Widget child;

  /// 上报目标；默认全局预热器（单测可注入）。
  final ThumbPrefetch? prefetch;

  const ScrollDecodeScope({super.key, required this.child, this.prefetch});

  @override
  Widget build(BuildContext context) {
    final target = prefetch ?? ThumbPrefetch.instance;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // 只认最外层滚动，内层（筛选条这类横向列表）不改变预算。
        if (n.depth != 0) return false;
        if (n is ScrollStartNotification) {
          target.setScrolling(true);
        } else if (n is ScrollEndNotification) {
          target.setScrolling(false);
        }
        return false;
      },
      child: child,
    );
  }
}
