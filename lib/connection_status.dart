// P5 连接语义：主页左上角的连接状态图标。
//
// 规则（owner 2026-11-23）：
//  - 全部连接都在线 → 对钩/云图标；
//  - 有连接被关闭（与服务器断连）→ 图标变叉号，并在 tooltip 里给出条数；
//  - 点击图标进入「网络连接」设置。
//
// 状态来源只有一处：[serversFromPrefs]（与设置页同源，键名由
// `ConnPrefsKeys.servers` 定义）。
// 设置页改动后 bump [connectionRevision]，主页图标立即重读，不加定时器。

import 'package:flutter/material.dart';

import 'multi_server.dart';
import 'status_color.dart';

/// 连接配置版本号：任何「断开 / 重连 / 增删」都要 bump。
final ValueNotifier<int> connectionRevision = ValueNotifier<int>(0);

/// 读取当前已断连的连接数量。
Future<int> loadDisconnectedCount() async {
  try {
    return disconnectedCount(await loadServersFromPrefs());
  } catch (_) {
    return 0;
  }
}

/// 左上角连接状态图标。
class ConnectionStatusIcon extends StatefulWidget {
  /// 点击图标时的动作（打开网络连接设置）。
  final VoidCallback? onTap;

  const ConnectionStatusIcon({super.key, this.onTap});

  @override
  State<ConnectionStatusIcon> createState() => _ConnectionStatusIconState();
}

class _ConnectionStatusIconState extends State<ConnectionStatusIcon> {
  int down = 0;

  @override
  void initState() {
    super.initState();
    _load();
    connectionRevision.addListener(_load);
  }

  @override
  void dispose() {
    connectionRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final n = await loadDisconnectedCount();
    if (mounted && n != down) setState(() => down = n);
  }

  @override
  Widget build(BuildContext context) {
    final off = down > 0;
    return IconButton(
      key: const ValueKey('connection-status'),
      tooltip: off ? '已断连 $down 条连接（点此重连）' : '连接正常（点此管理网络连接）',
      onPressed: widget.onTap,
      icon: Icon(
        off ? Icons.link_off : Icons.cloud_done_outlined,
        color: off ? kStatusBad : kStatusOk,
      ),
    );
  }
}
