// 设置 → 诊断信息：看最近错误（0.9.23）。
//
// 只展示内存里的错误记录（`CrashLog`），不读文件、不上传；
// 「复制全部」方便 owner 直接把问题贴回来。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'crash_guard.dart';

class CrashReportsPage extends StatelessWidget {
  /// 顶部一行环境信息（如服务器地址），可为空。
  final String detail;

  const CrashReportsPage({super.key, this.detail = ''});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断信息'),
        actions: [
          AnimatedBuilder(
            animation: CrashLog.instance,
            builder: (context, _) {
              final n = CrashLog.instance.count;
              if (n == 0) return const SizedBox.shrink();
              return IconButton(
                tooltip: '复制全部',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: CrashLog.instance.dump()));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制错误记录')));
                },
              );
            },
          ),
          AnimatedBuilder(
            animation: CrashLog.instance,
            builder: (context, _) {
              final n = CrashLog.instance.count;
              if (n == 0) return const SizedBox.shrink();
              return IconButton(
                tooltip: '清空',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: CrashLog.instance.clear,
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: CrashLog.instance,
        builder: (context, _) {
          final entries = CrashLog.instance.entries;
          return ListView(
            children: [
              if (detail.trim().isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('当前连接'),
                  subtitle: Text(detail, maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(entries.isEmpty
                    ? '最近没有错误'
                    : '最近 ${entries.length} 条错误'),
                subtitle: const Text('只在内存里保留最近 50 条，重启后清空'),
              ),
              const Divider(height: 1),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('运行正常，没有记录到错误。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey)),
                ),
              for (final e in entries)
                ExpansionTile(
                  leading: Icon(
                    e.kind == 'widget'
                        ? Icons.widgets_outlined
                        : Icons.bolt_outlined,
                    size: 20,
                  ),
                  title: Text(
                    e.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    '${e.timeText} · ${e.kindLabel}'
                    '${e.hits > 1 ? ' · ×${e.hits}' : ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (e.stack.trim().isEmpty)
                      const Text('（无调用栈）',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey))
                    else
                      SelectableText(
                        e.stack,
                        style: const TextStyle(
                            fontSize: 10.5, fontFamily: 'monospace'),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
