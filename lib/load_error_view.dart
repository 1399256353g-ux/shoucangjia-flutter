import 'package:flutter/material.dart';

import 'error_text.dart';

/// 「加载失败」的唯一样式。
///
/// 此前这个块在 `main.dart` 里被手写了 **11 次**，分三种形态：
///
/// | 形态 | 处数 | 差异 |
/// |---|---|---|
/// | 带内边距 + 字号 12 + 重试 | 5 | 左右留白 24，长错误换行居中 |
/// | 纯 Text + 重试 | 2 | **没有内边距、字号是默认 14** |
/// | 纯 Text、无重试 | 4 | 页面级整页错误，靠顶部/菜单重新加载 |
///
/// 同一句「加载失败：xxx」在不同页面大小不一，长错误在无内边距的那两处会
/// 顶到屏幕边缘。所以收成一个控件：**只有「有没有重试」这一个维度**，
/// 视觉全部一致。
///
/// 文案由调用方传已翻译好的文本（见 `error_text.dart` 的 `errorText`），
/// 本控件不碰异常对象——展示层与异常翻译是两件事。
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.message, this.onRetry});

  /// 已经翻译成人话的错误文案（不要传 `'$e'`）。
  final String message;

  /// 加载失败页的入口：**唯一**的「加载失败：<原因>」拼法。
  ///
  /// 0.9.362：调用点原来各自写 `LoadErrorView(message: '加载失败：$err')`，
  /// 14 处各拼一遍同一句话。页面上这句话的措辞（`加载失败`）与分隔符
  /// 应该只在一处——否则改成「加载出错」时只改到几处，同一 App 里两种说法。
  factory LoadErrorView.loadFailed(
    String err, {
    Key? key,
    VoidCallback? onRetry,
  }) =>
      LoadErrorView(key: key, message: failureLine('加载', err), onRetry: onRetry);

  /// 为空时不显示重试按钮（页面级错误，靠外层重新加载）。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}
