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
/// 0.9.363：0.9.362 只把五个入口转发过来，其余 **62 处**仍在页面里直接
/// `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(...)))`。
/// 那 62 处形态一致（所以没坏），但它们是同一件事的第二份实现：
/// 想改一下提示的形态（去掉重复提示、加底部安全区、限制队列长度）就得
/// 一个个找。现在全部转发到这里，`lib/` 里除本文件外**没有任何
/// `showSnackBar`**。
///
/// 这里只保留一条规则：**mount 检查 + 空文本跳过 + 失败态红底**。
/// 页面不再各自决定「要不要检查、要不要上色」；`_toast(...)` 这类私有
/// 转发保留（有些页面需要 `hideCurrentSnackBar` 的替换语义），但它们
/// 内部也只有一行。
library;

import 'package:flutter/material.dart';

import 'error_text.dart';

/// 失败提示的底色。只在这里出现一次：此前四个页面各写 `Colors.red.shade700`。
final Color kToastErrorBackground = Colors.red.shade700;

/// 弹一条提示。[state] 用来判断页面是否还活着。
///
/// 空文本直接跳过：`SnackBar` 只带背景没有文字时，用户看到的是
/// 一条什么都没有的横条，比不弹更糟。
void showToast(State state, String msg,
    {bool bad = false, bool replace = false, Duration? duration}) {
  if (!state.mounted || msg.isEmpty) return;
  showToastIn(state.context, msg,
      bad: bad, replace: replace, duration: duration);
}

/// 已知上下文仍有效时的入口（弹窗回调里已经判过 `context.mounted`）。
///
/// 走 `maybeOf`：拿不到 `ScaffoldMessenger` 时静默返回，不再抛
/// 「No ScaffoldMessenger widget found」——提示是尽力而为，不该让一次
/// 提示失败变成一次崩溃。
///
/// [replace] 对应原 `..hideCurrentSnackBar()..showSnackBar(...)` 的写法：
/// 连续操作（连点星标、连改设置）只留最后一条，不在队列里堆十条。
/// [duration] 只给确实需要更短停留的提示用（例如星标切换 900ms）；
/// 默认值仍是 Flutter 的 4 秒。
void showToastIn(BuildContext context, String msg,
    {bool bad = false, bool replace = false, Duration? duration}) {
  if (msg.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  if (replace) messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: bad ? kToastErrorBackground : null,
    duration: duration ?? const Duration(milliseconds: 4000),
  ));
}

/// 失败提示的唯一入口：`failureLine` 拼文案 + 红底。
///
/// 第一百二十批（0.9.371）：`bad: true` 这个参数此前只有挂载面板两处在用，
/// 而 `lib/` 里 **24 处**「确定失败了」的提示（`showToast(this,
/// failureLine('保存', …))`）全都走默认底色。形态一致所以一直没人发现：
/// 上传封面失败、保存同步源失败、批量删除失败——用户看到的都是一条和
/// 「已保存」长得一模一样的灰条。
///
/// 收口方式不是让 `showToast` 去猜文案里有没有「失败：」（那是靠字符串形状
/// 反推语义，任何一处换成「未能保存」就失效），而是把「这是一次失败」这件
/// 事写进**函数名**：调用点直接给出动作与原因，文案与红底一起由这里决定，
/// 两处不可能再分叉。
///
/// 句子中间夹着「失败：」（如「已删除 3 个，失败：原因」）不算，仍用
/// [failureLine] 拼——那种提示的主体是「删了几个」，不是一次失败。
void failureToast(State state, String action, String reason,
    {bool replace = false, Duration? duration}) {
  showToast(state, failureLine(action, reason),
      bad: true, replace: replace, duration: duration);
}

/// [failureToast] 的 context 版本（已判过 `context.mounted` 的回调里用）。
void failureToastIn(BuildContext context, String action, String reason,
    {bool replace = false, Duration? duration}) {
  showToastIn(context, failureLine(action, reason),
      bad: true, replace: replace, duration: duration);
}
