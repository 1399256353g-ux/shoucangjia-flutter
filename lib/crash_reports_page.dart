// 设置 → 诊断信息：看最近错误（0.9.23）。
//
// 展示内存里的错误记录（`CrashLog`）+ 本机落盘日志尾部（只读、不发送），
// 「复制全部」方便 owner 直接把问题贴回来。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'crash_guard.dart';
import 'byte_size.dart';
import 'count_label.dart';
import 'resize_cache_api.dart';
import 'thumb_prefetch.dart';

class CrashReportsPage extends StatelessWidget {
  /// 顶部一行环境信息（如服务器地址），可为空。
  final String detail;

  /// 服务端缩图缓存统计 / 清理地址（无连接时为空）。
  final Uri? cacheStatsUri;
  final Uri? cachePruneUri;
  final Map<String, String> cacheHeaders;

  /// 作为「诊断」合并页的一个 tab 嵌入时置 true：
  /// 不套 Scaffold/AppBar，操作按钮移到内容顶部，避免双层标题栏。
  final bool embedded;

  const CrashReportsPage({
    super.key,
    this.detail = '',
    this.cacheStatsUri,
    this.cachePruneUri,
    this.cacheHeaders = const {},
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      AnimatedBuilder(
        animation: CrashLog.instance,
        builder: (context, _) {
          if (CrashLog.instance.count == 0) return const SizedBox.shrink();
          return IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(
                  ClipboardData(text: CrashLog.instance.dump()));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已复制错误记录')));
            },
          );
        },
      ),
      AnimatedBuilder(
        animation: CrashLog.instance,
        builder: (context, _) {
          if (CrashLog.instance.count == 0) return const SizedBox.shrink();
          return IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: CrashLog.instance.clear,
          );
        },
      ),
    ];
    if (embedded) {
      return Column(children: [
        Align(alignment: Alignment.centerRight, child: Row(
            mainAxisSize: MainAxisSize.min, children: actions)),
        Expanded(child: _body(context)),
      ]);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断信息'),
        actions: actions,
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) => AnimatedBuilder(
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
              const _CrashLogFileTile(),
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
      );

  /// 首屏缩略图预热 + 图片缓存现状（0.9.26）。
  ///
  /// 字节与张数一律走 [formatBytes] / [formatCount]：这里原先自己算了
  /// `(bytes / 1048576).toStringAsFixed(1)` 拼成 `3.5 MB`，而同一页下面的
  /// 「缩图缓存」行用的是 [formatBytes]（`31.5 MB` / `1.50 GB`）。
  /// 两个读数并排显示时，一个到 GB 就换单位、一个永远停在 MB：
  /// 上限 2 GB 的图片缓存写成 `2048 MB`，而旁边一行写着 `2.00 GB`——
  /// 同一个 App、同一屏、同一个量纲两种写法。
  Widget _prefetchTile() {
    final p = ThumbPrefetch.instance;
    final cache = PaintingBinding.instance.imageCache;
    final used = formatBytes(cache.currentSizeBytes);
    final cap = formatBytes(cache.maximumSizeBytes);
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
            '图片缓存 ${formatCount(cache.currentSize)} 张 / $used'
            '（上限 $cap）',
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

/// 本机落盘日志：路径 + 最近写入时间 + 尾部内容（0.9.37）。
///
/// 闪退（尤其 Windows 上的封面闪退）后 owner 无法取到终端输出，
/// 这里把 `crash.log` 的尾部直接读出来，可一键复制。只读本机文件，
/// 不发网络请求、不写回。
class _CrashLogFileTile extends StatefulWidget {
  const _CrashLogFileTile();

  @override
  State<_CrashLogFileTile> createState() => _CrashLogFileTileState();
}

class _CrashLogFileTileState extends State<_CrashLogFileTile> {
  bool _loading = true;
  String _info = '';
  String _tail = '';
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final info = await crashLogFileInfo();
    final tail = await readCrashLogTail();
    if (!mounted) return;
    setState(() {
      _info = info ?? '';
      _tail = tail;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _info.isNotEmpty;
    final path = CrashLog.logPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          leading: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(hasFile
                  ? Icons.description_outlined
                  : Icons.note_alt_outlined),
          title: Text(hasFile ? '崩溃日志文件：$_info' : '崩溃日志文件：暂无'),
          subtitle: Text(
            '$path\n'
            '${hasFile ? '只读本机文件，不上传；点开可看最近内容' : '闪退后重开应用再看，日志写在应用所在机器的本地磁盘'}',
            style: const TextStyle(fontSize: 11, height: 1.35),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _loading ? null : _load,
              ),
              IconButton(
                tooltip: '复制日志',
                icon: const Icon(Icons.copy_all_outlined, size: 20),
                onPressed: _tail.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: _tail));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制日志内容')));
                      },
              ),
            ],
          ),
          onTap: _tail.isEmpty
              ? null
              : () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded && _tail.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0x0F000000),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              child: SelectableText(
                _tail,
                style:
                    const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
              ),
            ),
          ),
      ],
    );
  }
}
