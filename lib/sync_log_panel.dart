/// 同步日志面板：嵌在单元库「爬虫配置」页里。
///
/// - `GET /api/sync/logs?lib=&limit=`：按轮次展示时间/库/成功/失败/删除/耗时；
/// - `POST /api/sync/retry {runId, ids}`：失败项逐条重试或整轮重试。
///
/// 数据只来自服务端账本（保留 7 天），本页不读任何媒体文件。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'http_error_text.dart';
import 'http_json.dart';

import 'sync_ledger.dart';
import 'error_text.dart';

class SyncLogPanel extends StatefulWidget {
  final String base;
  final Map<String, String> headers;

  /// 当前注册库 id；空串时不带 lib 参数。
  final String libId;
  final http.Client? client;

  /// 一次拉取的轮次数。
  final int limit;

  const SyncLogPanel({
    super.key,
    required this.base,
    required this.headers,
    this.libId = '',
    this.client,
    this.limit = 20,
  });

  @override
  State<SyncLogPanel> createState() => SyncLogPanelState();
}

class SyncLogPanelState extends State<SyncLogPanel> {
  SyncLog log = SyncLog.empty;
  bool loading = true;
  String? err;
  bool retrying = false;

  /// owner 2026-11-25：「日志在设置页上限显示 10 条，剩下的点展开按键才显示」。
  /// 默认只铺 10 条，其余收起来——日志是排查用的，不该占满整页。
  bool expanded = false;
  static const int kCollapsedRuns = 10;

  /// 正在提交保留天数（避免连点）。
  bool busy = false;

  /// 注入的客户端优先；否则本页自建一个并在 dispose 关闭（与
  /// `collection_sync_panel` 同一理由：每个请求各建一个客户端且从不关闭，
  /// 反复进出的页面会各留一套连接池）。
  http.Client? _ownClient;
  http.Client get _client => widget.client ?? (_ownClient ??= http.Client());

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _ownClient?.close();
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final r = await _client
          .get(syncLogsUri(widget.base, lib: widget.libId, limit: widget.limit),
              headers: widget.headers)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      dynamic raw;
      try {
        raw = decodeSyncJson(r.bodyBytes);
      } catch (_) {
        throw Exception('返回不是 JSON');
      }
      if (!mounted) return;
      setState(() {
        log = parseSyncLog(raw);
        err = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        err = errorText(e);
        loading = false;
      });
    }
  }

  Future<void> _retry(SyncRun run, List<String> ids) async {
    if (retrying) return;
    final body = syncRetryBody(runId: run.id, ids: ids);
    if (stringsOf(body['ids']).isEmpty) return;
    setState(() => retrying = true);
    try {
      final r = await _client
          .post(syncRetryUri(widget.base),
              headers: {...widget.headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      dynamic parsed;
      try {
        parsed = decodeSyncJson(r.bodyBytes);
      } catch (_) {
        parsed = null;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(syncRetryResultLabel(r.statusCode, parsed))));
      if (r.statusCode == 200) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted) await load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureLine('重试', errorText(e)))));
    } finally {
      if (mounted) setState(() => retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('sync-log-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.receipt_long, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('同步日志',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            key: const ValueKey('sync-log-refresh'),
            tooltip: '刷新同步日志',
            visualDensity: VisualDensity.compact,
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 22, bottom: 4),
          child: Row(children: [
            Expanded(
              child: Text(
                '保留 ${log.keptDays} 天 · 最近 ${log.runs.length} 次同步'
                '${log.total > log.runs.length ? '（共 ${log.total}）' : ''}',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ),
            // owner 2026-11-25：保留天数可自己设置；过期的同步日志自动清除。
            // 只改同步日志，删除检测记录（_deleted.log）不受影响。
            TextButton(
              key: const ValueKey('sync-log-keepdays'),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28)),
              onPressed: busy ? null : _editKeepDays,
              child: const Text('设置保留天数', style: TextStyle(fontSize: 10.5)),
            ),
          ]),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (err != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                  child: Text(failureLine('同步日志读取', err!),
                      style: const TextStyle(fontSize: 11))),
              TextButton(onPressed: load, child: const Text('重试')),
            ]),
          )
        else if (log.runs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('暂无同步记录（服务端每次跑完爬虫会写一条）',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          )
        else
          for (final r in (expanded
              ? log.runs
              : log.runs.take(kCollapsedRuns).toList()))
            _runTile(r),
          if (log.runs.length > kCollapsedRuns)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
              child: TextButton.icon(
                key: const ValueKey('sync-log-expand'),
                onPressed: () => setState(() => expanded = !expanded),
                icon: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18),
                label: Text(
                  expanded
                      ? '收起（只看最近 $kCollapsedRuns 条）'
                      : '展开全部 ${log.runs.length} 条'
                          '${log.total > log.runs.length ? '（服务端共 ${log.total}）' : ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// owner 2026-11-25：「可自己设置保留日志的天数，过期的日志自动清除，
  /// 但小心别把删除检测日志删了」。
  ///
  /// 这里只改**同步日志**的保留天数（1..90）。删除检测记录在
  /// `_deleted.log`，由另一个服务端脚本维护，接口完全不碰它。
  Future<void> _editKeepDays() async {
    if (busy) return;
    var days = log.keptDays > 0 ? log.keptDays : 7;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('同步日志保留天数'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('超期记录会自动清除（范围 1–90 天）。\n'
                  '只清理同步日志，删除监测记录不受影响。',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              Row(children: [
                const Text('天数'),
                Expanded(
                  child: Slider(
                    key: const ValueKey('sync-log-keepdays-slider'),
                    value: days.toDouble(),
                    min: 1,
                    max: 90,
                    divisions: 89,
                    label: '$days',
                    onChanged: (v) => setLocal(() => days = v.round()),
                  ),
                ),
                SizedBox(
                    width: 32,
                    child: Text('$days', textAlign: TextAlign.end)),
              ]),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(days),
                  child: const Text('保存')),
            ],
          );
        });
      },
    );
    if (picked == null || !mounted) return;
    setState(() => busy = true);
    try {
      final r = await _client
          .post(
            syncLogSettingsUri(widget.base),
            headers: {...widget.headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'keepDays': picked}),
          )
          .timeout(const Duration(seconds: 12));
      dynamic parsed;
      try {
        parsed = decodeSyncJson(r.bodyBytes);
      } catch (_) {
        parsed = null;
      }
      if (r.statusCode != 200) {
        throw Exception(httpErrorText(r.statusCode));
      }
      final saved = parseKeepDays(parsed, fallback: picked);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已设为保留 $saved 天')));
      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureLine('设置', errorText(e)))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _runTile(SyncRun r) {
    final cs = Theme.of(context).colorScheme;
    final failColor = Colors.orange.shade800;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Theme(
        // 去掉 ExpansionTile 展开时的分隔线，保持卡片干净
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('sync-run-${r.id}'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.only(left: 6, right: 6, bottom: 6),
          leading: r.running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(
                  switch (r.mode) {
                    'quick' => Icons.bolt,
                    'full' => Icons.sync,
                    'retry' => Icons.replay,
                    _ => Icons.play_arrow,
                  },
                  size: 18,
                  color: cs.primary,
                ),
          title: Text(r.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${r.unitLabel}'
              '${r.script.isEmpty ? '' : ' · ${r.script}'}'
              '${r.retryOf.isEmpty ? '' : ' · 重试 ${r.retryOf}'}'
              '${r.error.isEmpty ? '' : ' · ${r.error}'}'
              // 退出码的说法只有 `sync_ledger.syncExitLabel` 一处
              // （爬虫配置页的「上次运行」读同一条）。
              '${r.exit == null ? '' : ' · ${syncExitLabel(r.exit)}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          ),
          children: [
            if (r.items.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
                  child: Text(
                    r.hasFail ? '本轮失败 $r.fail 条（无逐条明细）' : '本轮无逐条明细',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else ...[
              for (final it in r.items)
                ListTile(
                  key: ValueKey('sync-item-${r.id}-${it.id}'),
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  title: Text(it.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  subtitle: Text(
                    '${it.stateLabel}'
                    '${it.id.isEmpty ? '' : ' · ${it.id}'}'
                    '${it.why.isEmpty ? '' : ' · ${it.why}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        color: it.failed ? failColor : cs.onSurfaceVariant),
                  ),
                  trailing: it.failed
                      ? IconButton(
                          key: ValueKey('sync-item-retry-${r.id}-${it.id}'),
                          tooltip: '重试该条',
                          visualDensity: VisualDensity.compact,
                          onPressed: (retrying || it.id.isEmpty)
                              ? null
                              : () => _retry(r, [it.id]),
                          icon: const Icon(Icons.replay, size: 16),
                        )
                      : null,
                ),
              if (r.itemsTotal > r.items.length)
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 2),
                  child: Text('仅显示前 ${r.items.length} 条（共 ${r.itemsTotal}）',
                      style:
                          TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                ),
              if (r.hasFail)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton.icon(
                      key: ValueKey('sync-retry-all-${r.id}'),
                      onPressed: (retrying || r.failedIds.isEmpty)
                          ? null
                          : () => _retry(r, r.failedIds),
                      icon: const Icon(Icons.replay, size: 16),
                      label: Text('全部重试（${r.failedIds.length}）',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
