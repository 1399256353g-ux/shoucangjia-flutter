/// 界面提示（SnackBar）的唯一实现。
///
/// 0.9.362：同一句提示的弹出方式此前在五个文件里各写一遍，而且**行为不同**：
///
/// | 文件 | 是否守 `mounted` | 失败态底色 | 空文本 |
/// |---|---|---|---|
/// | `main.dart` | 是 | 无 | 照弹空白条 |
/// | `category_tree_page.dart` | 是 | 无 | 照弹空白条 |
/// | `author_mount_sheet.dart` | **调用点自己守** | 红底 | 照弹空白条 |
/// | `unit_author_mount_page.dart` | **调用点自己守** | 红底 | 照弹空白条 |
/// | `cover_menu.dart` | 用 `maybeOf` | 无 | 静默跳过 |
///
/// 三处差异都会变成用户能看到的形态：忘了守 `mounted` 的那两个面板在
/// 请求返回前被关掉时，`ScaffoldMessenger.of` 会抛「deactivated widget's
/// ancestor」；没有空文本守卫的会弹出一条只有背景色的空白提示。
///
/// 这里只保留一条规则：**mount 检查 + 空文本跳过 + 失败态红底**。
/// 各页面保留自己的 `_toast(...)` 一行转发，调用点不用改——
/// 提示的形态只有这一个出口，页面不再各自决定「要不要检查、要不要上色」。
library;

import 'package:flutter/material.dart';

/// 失败提示的底色。只在这里出现一次：此前四个页面各写 `Colors.red.shade700`。
final Color kToastErrorBackground = Colors.red.shade700;

/// 弹一条提示。[state] 用来判断页面是否还活着。
///
/// 空文本直接跳过：`SnackBar` 只带背景没有文字时，用户看到的是
/// 一条什么都没有的横条，比不弹更糟。
void showToast(State state, String msg, {bool bad = false}) {
  if (!state.mounted || msg.isEmpty) return;
  showToastIn(state.context, msg, bad: bad);
}

/// 已知上下文仍有效时的入口（弹窗回调里已经判过 `context.mounted`）。
///
/// 走 `maybeOf`：拿不到 `ScaffoldMessenger` 时静默返回，不再抛
/// 「No ScaffoldMessenger widget found」——提示是尽力而为，不该让一次
/// 提示失败变成一次崩溃。
void showToastIn(BuildContext context, String msg, {bool bad = false}) {
  if (msg.isEmpty) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: bad ? kToastErrorBackground : null,
  ));
}
