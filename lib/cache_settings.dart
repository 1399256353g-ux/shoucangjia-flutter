// T4：设置 → 缓存。
//
// 显示当前缓存目录/占用，允许调整上限（128–2048 MB）、自动清理开关与
// 保留天数，并提供「立即清空」（二次确认，清完提示释放字节数）。
import 'package:flutter/material.dart';

import 'cover_cache.dart';
import 'home_action.dart';
import 'toast.dart';

class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({super.key});

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage> {
  CacheUsage usage = CacheUsage.empty;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final u = await DiziCache.measure();
    if (!mounted) return;
    setState(() {
      usage = u;
      loading = false;
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('立即清空缓存'),
        content: Text('将删除 ${usage.human} 的全部封面缓存，'
            '下次浏览会重新下载。确定继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    final freed = await DiziCache.clearAll();
    await _refresh();
    if (!mounted) return;
    showToast(this, '已释放 ${formatBytes(freed)}');
  }

  @override
  Widget build(BuildContext context) {
    final dir = DiziCache.rootDir.isEmpty ? '（未初始化）' : DiziCache.rootDir;
    return Scaffold(
      appBar: AppBar(title: const Text('缓存'), actions: const [HomeAction()]),
      body: ListView(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
              '封面与缩略图缓存只写入本 App 的缓存目录；Windows 固定落 E 盘，'
              '不会写 C 盘。超出上限按「最久未使用」淘汰。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('缓存目录'),
          subtitle: SelectableText(dir,
              style: const TextStyle(fontSize: 12)),
        ),
        ListTile(
          leading: const Icon(Icons.data_usage),
          title: const Text('当前占用'),
          subtitle: Text(loading
              ? '统计中…'
              : '${usage.human} · ${usage.files} 个文件 · 上限 ${DiziCache.maxMb} MB'),
          trailing: IconButton(
            tooltip: '重新统计',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.speed),
          title: const Text('缓存上限'),
          subtitle: const Text('超出后按最久未使用淘汰'),
          trailing: DropdownButton<int>(
            value: DiziCache.maxMb,
            items: [
              for (final mb in DiziCache.maxMbOptions)
                DropdownMenuItem(value: mb, child: Text('$mb MB')),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await DiziCache.setMaxMb(v);
              await _refresh();
              if (mounted) setState(() {});
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.auto_delete_outlined),
          title: const Text('自动清理'),
          subtitle: const Text('启动、运行中与退出前自动清理过期/超限条目'),
          value: DiziCache.autoClean,
          onChanged: (v) async {
            await DiziCache.setAutoClean(v);
            if (mounted) setState(() {});
          },
        ),
        ListTile(
          leading: const Icon(Icons.event_available),
          title: const Text('保留天数'),
          subtitle: const Text('超过该天数未访问的缓存会被清理'),
          trailing: DropdownButton<int>(
            value: DiziCache.keepDays,
            items: [
              for (final d in DiziCache.keepDayOptions)
                DropdownMenuItem(value: d, child: Text('$d 天')),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await DiziCache.setKeepDays(v);
              if (mounted) setState(() {});
            },
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
          title: const Text('立即清空'),
          subtitle: const Text('删除全部封面缓存，显示释放的空间'),
          onTap: loading ? null : _clear,
        ),
      ]),
    );
  }
}
