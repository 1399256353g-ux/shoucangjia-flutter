// 库卡片右上角「快速刷新」按钮（owner 2026-11-22）。
//
// 一个入口只有两种外观：静止时是 `Icons.refresh`；刷新中变成转圈并
// 禁用重复点击。防抖与业务动作都在 [runLibRefresh] 里，本控件只负责
// 呈现与「同一时刻只有一次进行中」的状态，不新增任何定时器。
library;

import 'package:flutter/material.dart';

import 'error_text.dart';

/// 与封面按钮同风格、同尺寸（30×30 触达区，18dp 图标）。
class LibQuickRefreshButton extends StatefulWidget {
  /// 卡片所属库（基础库 id）；单元库卡片传它子树里的第一个基础库。
  final String libId;

  /// 真正执行刷新；返回 null 表示跳过（例如库 id 为空）。
  final Future<String?> Function()? onRefresh;

  /// 刷新完成后回传的一句话提示（由控件自己弹 SnackBar，卡片不重复处理）。
  /// 传 null 时控件不弹提示。
  final BuildContext? feedbackOf;

  const LibQuickRefreshButton({
    super.key,
    required this.libId,
    this.onRefresh,
    this.feedbackOf,
  });

  @override
  State<LibQuickRefreshButton> createState() => _LibQuickRefreshButtonState();
}

class _LibQuickRefreshButtonState extends State<LibQuickRefreshButton> {
  bool _busy = false;

  Future<void> _run() async {
    final fn = widget.onRefresh;
    if (fn == null || _busy) return;
    setState(() => _busy = true);
    String? msg;
    try {
      msg = await fn();
    } catch (e) {
      msg = '刷新失败：${errorText(e)}';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final host = widget.feedbackOf ?? context;
    if (msg != null && msg.isNotEmpty && host.mounted) {
      ScaffoldMessenger.maybeOf(host)
          ?.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: ValueKey('lib-refresh-${widget.libId}'),
      tooltip: _busy ? '正在刷新' : '快速刷新（重建索引 + 重拉封面）',
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      onPressed: (widget.onRefresh == null || _busy) ? null : _run,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
    );
  }
}
