// 设置 → 诊断信息：看最近错误（0.9.23）。
//
// 只展示内存里的错误记录（`CrashLog`），不读文件、不上传；
// 「复制全部」方便 owner 直接把问题贴回来。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'crash_guard.dart';
import 'resize_cache_api.dart';
import 'thumb_prefetch.dart';

class CrashReportsPage extends StatelessWidget {
  /// 顶部一行环境信息（如服务器地址），可为空。
  final String detail;

  /// 服务端缩图缓存统计 / 清理地址（无连接时为空）。
  final Uri? cacheStatsUri;
  final Uri? cachePruneUri;
  final Map<String, String> cacheHeaders;

  const CrashReportsPage({
    super.key,
    this.detail = '',
    this.cacheStatsUri,
    this.cachePruneUri,
    this.cacheHeaders = const {},
  });

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
              _prefetchTile(),
              if (cacheStatsUri != null)
                _ResizeCacheTile(
                  statsUri: cacheStatsUri!,
                  pruneUri: cachePruneUri,
                  headers: cacheHeaders,
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

  /// 首屏缩略图预热 + 图片缓存现状（0.9.26）。
  Widget _prefetchTile() {
    final p = ThumbPrefetch.instance;
    final cache = PaintingBinding.instance.imageCache;
    final mb = (cache.currentSizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final pending = p.stats.pending;
    return AnimatedBuilder(
      animation: p,
      builder: (context, _) {
        final s = p.stats;
        return ListTile(
          dense: true,
          leading: p.busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.bolt_outlined),
          title: Text(s.requested == 0
              ? '首屏缩略图：尚未预热'
              : '首屏缩略图：${s.loaded}/${s.requested} 张就绪'),
          subtitle: Text(
            '失败 ${s.failed} · 跳过 ${s.skipped}'
            '${pending > 0 ? ' · 进行中 $pending' : ''}'
            ' · 最近 ${s.lastRunText}\n'
            '图片缓存 ${cache.currentSize} 张 / $mb MB'
            '（上限 ${(cache.maximumSizeBytes / (1024 * 1024)).round()} MB）',
            style: const TextStyle(fontSize: 11, height: 1.35),
          ),
        );
      },
    );
  }
}

/// 服务端缩图缓存（`?w=`）现状 + 手动清理（0.9.28）。
///
/// 只读 `/api/cache/stats`；清理走 `/api/cache/prune`，服务端只删
/// `~/.cache/gallery-resize` 自己的文件，不会碰作品原图。
class _ResizeCacheTile extends StatefulWidget {
  final Uri statsUri;
  final Uri? pruneUri;
  final Map<String, String> headers;

  const _ResizeCacheTile({
    required this.statsUri,
    required this.pruneUri,
    required this.headers,
  });

  @override
  State<_ResizeCacheTile> createState() => _ResizeCacheTileState();
}

class _ResizeCacheTileState extends State<_ResizeCacheTile> {
  ResizeCacheStats? stats;
  bool loading = true;
  bool pruning = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => loading = true);
    final s = await fetchResizeCacheStats(widget.statsUri, widget.headers);
    if (!mounted) return;
    setState(() {
      stats = s;
      loading = false;
    });
  }

  Future<void> _prune() async {
    final uri = widget.pruneUri;
    if (uri == null || pruning) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缩图缓存'),
        content: const Text('只会删除服务端生成的缩图缓存（卡片、头像、海报的小图），'
            '不会删除或改动任何作品原图。下次浏览会按需重新生成。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('清理')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => pruning = true);
    final msg = await pruneResizeCache(uri, widget.headers);
    if (!mounted) return;
    setState(() => pruning = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg ?? '清理失败，检查服务器连接')));
    if (msg != null) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final percent = s?.usedPercent;
    final String title;
    if (loading && s == null) {
      title = '缩图缓存：读取中…';
    } else if (s == null) {
      title = '缩图缓存：读取失败';
    } else {
      title = '缩图缓存 ${s.usageText}'
          '${s.files > 0 ? '（${s.files} 张）' : ''}';
    }
    final subtitle = s == null
        ? '服务端按显示宽度生成的缩图，只读原图、不覆盖媒体'
        : '${s.countersText}\n'
            '命中率 ${s.hitRateText}'
            '${percent != null ? ' · 占用上限的 $percent%' : ''}'
            '${s.pruneDeleted > 0 ? ' · 已自动清理 ${s.pruneDeleted} 个' : ''}';
    return ListTile(
      dense: true,
      leading: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.photo_size_select_small_outlined),
      title: Text(title),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 11, height: 1.35)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: loading ? null : _refresh,
          ),
          if (widget.pruneUri != null)
            IconButton(
              tooltip: '清理缩图缓存',
              icon: pruning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cleaning_services_outlined, size: 20),
              onPressed: pruning ? null : _prune,
            ),
        ],
      ),
    );
  }
}
