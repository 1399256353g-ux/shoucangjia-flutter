import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'http_json.dart';

import 'home_action.dart';
import 'interval_label.dart';
import 'collection_sync_panel.dart';
import 'sync_log_panel.dart';
import 'time_labels.dart';
import 'unit_crawler.dart';
import 'unit_library.dart';
import 'error_text.dart';
import 'load_error_view.dart';

/// L5-D：单个单元库的爬虫配置页。
///
/// 配置与脚本都留在该单元库目录下（`crawler/`），运行互不影响；
/// 顶级单元库（SECRET）不提供本页。
class UnitCrawlerPage extends StatefulWidget {
  final UnitLibrary unit;
  final String base;
  final Map<String, String> headers;

  /// 当前注册库 id；同步源读写走 `/api/settings?lib=`。
  final String libId;
  final http.Client? client;

  const UnitCrawlerPage({
    super.key,
    required this.unit,
    required this.base,
    required this.headers,
    this.libId = '',
    this.client,
  });

  @override
  State<UnitCrawlerPage> createState() => _UnitCrawlerPageState();
}

class _UnitCrawlerPageState extends State<UnitCrawlerPage> {
  bool loading = true;
  bool saving = false;
  bool running = false;
  String? err;
  String path = '';
  UnitCrawlerConfig config = const UnitCrawlerConfig();
  List<UnitCrawlerScript> scripts = const [];

  /// M7：服务端下发的运行记录（上次/下次/最近结果）。
  Map<String, dynamic> schedule = const {};

  http.Client get _client => widget.client ?? http.Client();

  String get _configUrl => unitCrawlerUrl(widget.base, '/api/unit/crawler',
      unitId: widget.unit.id, rel: widget.unit.rel);

  String get _runUrl => unitCrawlerUrl(widget.base, '/api/unit/run-crawler',
      unitId: widget.unit.id, rel: widget.unit.rel);

  bool get hasScript =>
      scripts.any((s) => s.name == config.script && s.looksRunnable);

  List<UnitCrawlerScript> get runnableScripts =>
      scripts.where((s) => s.looksRunnable).toList(growable: false);

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      final r = await _client
          .get(Uri.parse(_configUrl), headers: widget.headers)
          .timeout(const Duration(seconds: 10));
      final j = jsonOf(r) as Map<String, dynamic>;
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      if (!mounted) return;
      setState(() {
        path = '${j['path'] ?? ''}';
        config = UnitCrawlerConfig.fromJson(j['crawler'] as Map?);
        scripts = UnitCrawlerScript.listFrom(j['scripts']);
        running = (j['running'] as Map?)?['running'] == true;
        schedule = (j['schedule'] is Map)
            ? Map<String, dynamic>.from(j['schedule'] as Map)
            : const {};
      });
    } catch (e) {
      if (mounted) setState(() => err = errorText(e));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> save() async {
    if (!hasScript) return;
    setState(() => saving = true);
    try {
      final r = await _client
          .post(Uri.parse(_configUrl),
              headers: {
                ...widget.headers,
                'Content-Type': 'application/json',
              },
              body: jsonEncode(config.toJson()))
          .timeout(const Duration(seconds: 10));
      final j = jsonOf(r) as Map<String, dynamic>;
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      if (!mounted) return;
      setState(() {
        config = UnitCrawlerConfig.fromJson(j['crawler'] as Map?);
        scripts = UnitCrawlerScript.listFrom(j['scripts']);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('单元库爬虫配置已保存')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> run() async {
    if (!hasScript || running) return;
    setState(() => running = true);
    try {
      final r = await _client
          .post(Uri.parse(_runUrl), headers: widget.headers)
          .timeout(const Duration(seconds: 10));
      final j = jsonOf(r) as Map<String, dynamic>;
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('已启动 ${j['script'] ?? config.script} pid=${j['pid']}')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await load();
    } catch (e) {
      if (!mounted) return;
      setState(() => running = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('启动失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('爬虫配置 · ${widget.unit.name}'),
        actions: [
          const HomeAction(),
          TextButton(
            onPressed: (!hasScript || saving) ? null : save,
            child: Text(saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: err != null
          ? _errorView()
          : loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('单元库：${widget.unit.rel}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                    if (path.isNotEmpty)
                      Text(path,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 12),
                    _capabilityBanner(),
                    if (!hasScript) ...[
                      const SizedBox(height: 8),
                      Text('脚本目录：${_scriptDir()}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                    const Divider(height: 28),
                    SwitchListTile(
                      key: const ValueKey('unit-crawler-enabled'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用同步调度'),
                      subtitle: Text(hasScript
                          ? '保存后由 NAS 调度读取；无脚本时不可用'
                          : '无爬虫脚本，同步设置不可用'),
                      value: hasScript && config.enabled,
                      onChanged: hasScript
                          ? (v) => setState(
                              () => config = config.copyWith(enabled: v))
                          : null,
                    ),
                    const SizedBox(height: 8),
                    // 同步频率：快检只扫新增/删除，全量才完整抓取。
                    _ScheduleSummary(schedule: schedule),
                    // S3：同步日志（时间/库/成功/失败/耗时；失败项可展开单条重试）
                    const SizedBox(height: 6),
                    SyncLogPanel(
                      base: widget.base,
                      headers: widget.headers,
                      libId: widget.libId,
                      client: widget.client,
                    ),
                    const Divider(height: 28),
                    // owner 2026-11-21：同步源选择并入每个单元库的爬虫设置，
                    // 不再保留设置页里的全局「同步源选择」入口。
                    CollectionSyncPanel(
                      base: widget.base,
                      headers: widget.headers,
                      libId: widget.libId,
                      unitName: widget.unit.name,
                      unitRel: widget.unit.rel,
                      client: widget.client,
                    ),
                    const Divider(height: 28),
                    SwitchListTile(
                      key: const ValueKey('unit-crawler-quick'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用快检'),
                      subtitle: const Text('只扫新增/删除，开销小；发现新作品再排全量'),
                      value: hasScript && config.quickCheck,
                      onChanged: hasScript
                          ? (v) => setState(
                              () => config = config.copyWith(quickCheck: v))
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text('快检间隔',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final m in kQuickMinOptions)
                        ChoiceChip(
                          label: Text(everyMinutesLabel(m)),
                          selected: config.quickMin == m,
                          onSelected: hasScript
                              ? (_) => setState(
                                  () => config = config.copyWith(quickMin: m))
                              : null,
                        ),
                    ]),
                    const SizedBox(height: 10),
                    Text('全量同步间隔',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final m in kFullMinOptions)
                        ChoiceChip(
                          label: Text(everyMinutesLabel(m)),
                          selected: config.fullMin == m,
                          onSelected: hasScript
                              ? (_) => setState(
                                  () => config = config.copyWith(fullMin: m))
                              : null,
                        ),
                    ]),
                    const SizedBox(height: 10),
                    Text('快检冷却',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final m in kCooldownOptions)
                        ChoiceChip(
                          label: Text('$m 分钟'),
                          selected: config.cooldownMin == m,
                          onSelected: hasScript
                              ? (_) => setState(() =>
                                  config = config.copyWith(cooldownMin: m))
                              : null,
                        ),
                    ]),
                    const SizedBox(height: 8),
                    Text('当前：${config.intervalLabel}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                    TextFormField(
                      initialValue: config.note,
                      enabled: hasScript,
                      decoration: const InputDecoration(labelText: '备注'),
                      maxLines: 2,
                      onChanged: (v) =>
                          config = config.copyWith(note: clipNote(v)),
                    ),
                    const Divider(height: 28),
                    _scriptPicker(),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const ValueKey('unit-crawler-run'),
                      onPressed: (hasScript && !running) ? run : null,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(unitCrawlerRunLabel(running)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '脚本写入该单元库的 crawler/ 目录；每个单元库独立运行，互不影响。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
    );
  }

  Widget _errorView() =>
      LoadErrorView(message: '加载失败：$err', onRetry: load);

  Widget _capabilityBanner() {
    final ok = hasScript;
    return Container(
      key: const ValueKey('unit-crawler-capability'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (ok ? Colors.green : Colors.orange).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.warning_amber,
            size: 18, color: ok ? Colors.green : Colors.orange),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ok ? '已配置脚本：${config.script}' : '无爬虫脚本（J17：同步设置已停用）',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ]),
    );
  }

  String _scriptDir() {
    final p = path.isNotEmpty ? path : widget.unit.rel;
    return p.endsWith('/') ? '${p}crawler' : '$p/crawler';
  }

  Widget _scriptPicker() {
    final list = runnableScripts;
    final current =
        list.any((s) => s.name == config.script) ? config.script : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('爬虫脚本', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (list.isEmpty)
          const Text('未发现脚本（支持 .sh / .py / .js）',
              style: TextStyle(fontSize: 12, color: Colors.grey))
        else
          DropdownButtonFormField<String>(
            key: const ValueKey('unit-crawler-script'),
            initialValue: current,
            decoration: const InputDecoration(labelText: '选择要运行的脚本'),
            items: [
              for (final s in list)
                DropdownMenuItem(
                  value: s.name,
                  child: Text('${s.name} · ${s.size} B'),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => config = config.copyWith(script: v));
            },
          ),
        if (list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('目录：${_scriptDir()}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
      ],
    );
  }
}

/// M7：同步配置页顶部的运行记录摘要（上次/下次 + 最近结果）。
class _ScheduleSummary extends StatelessWidget {
  final Map<String, dynamic> schedule;
  const _ScheduleSummary({required this.schedule});

  static String _t(dynamic v) {
    final ms = (v is num) ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    return monthDayTimeOfMs(ms);
  }

  @override
  Widget build(BuildContext context) {
    if (schedule.isEmpty) return const SizedBox.shrink();
    final mode = '${schedule['lastMode'] ?? ''}';
    final exit = schedule['lastExit'];
    final qh = schedule['quickRunsHour'] is num
        ? (schedule['quickRunsHour'] as num).toInt()
        : 0;
    final style = TextStyle(
        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '上次运行 ${_t(schedule['lastRun'])}'
          '${mode.isEmpty ? '' : ' · ${mode == 'quick' ? '快检' : '全量'}'}'
          '${exit == null ? '' : ' · exit $exit'}',
          style: style,
        ),
        const SizedBox(height: 2),
        Text(
          '下次快检 ${_t(schedule['nextQuick'])} · 下次全量 ${_t(schedule['nextFull'])}'
          ' · 本小时快检 $qh/3',
          style: style,
        ),
      ]),
    );
  }
}
