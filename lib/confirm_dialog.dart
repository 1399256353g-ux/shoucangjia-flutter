/// 「确认 / 取消」对话框的唯一实现（第一百一十九批 · 0.9.366）。
///
/// 为什么要有这个文件：这一种对话框在 15 个地方各写了一遍。每处单独看都
/// 正常，所以不报错；但它是**同一个交互的第二十几份拷贝**——「取消在左、
/// 确认在右」「确认按钮用 FilledButton」「危险操作用红底」这三条约定全靠
/// 每处手抄。想统一成「回车＝确认 / Esc＝取消」「危险操作标题变红」时，
/// 要改 15 处，漏掉的那一处不会报错，只会跟其它地方长得不一样。
///
/// 只收**纯文本确认**这一种形态：
///  - 标题 + 一段说明 + 取消/确认两键，返回 bool；
///  - 带 `TextField` / `StatefulBuilder` / 自定义内容（多选列表、备注框）的
///    对话框**不收**——它们的正文不是一句话，强行套模板会把布局塞进参数里。
///  - `取消（Esc）` 那种是按键捕获弹窗的单键样式，语义不同，**不能合并**。
///
/// 返回值刻意是 `bool` 而不是 `bool?`：调用点在 `null`（点外部关闭）与
/// `false`（点取消）上的处理**必须相同**，返回可空类型只会让每处再写一遍
/// `ok != true`。
library;

import 'package:flutter/material.dart';

/// 弹一个确认框；用户点确认返回 true，点取消或点外部返回 false。
///
/// [destructive] 为真时确认键用红底——这是「不可撤销」的唯一视觉标记，
/// 此前只有一个调用点自己写 `FilledButton.styleFrom(backgroundColor:
/// Colors.red)`，其余删除类操作都是普通按钮颜色。是否算「不可撤销」由
/// 调用方按文案决定（删注册表项可恢复，删同步源索引不可恢复），本函数
/// 不猜。
///
/// [confirmKey] 给需要被测试/自动化定位确认键的少数调用点用（例如
/// 单元库挂载页的 `uag-delete-ok`）。不传就是普通按钮。
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool destructive = false,
  Key? confirmKey,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          key: confirmKey,
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Colors.red)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}
