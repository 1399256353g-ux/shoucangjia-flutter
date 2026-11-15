import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'home_action.dart';
import 'unit_crawler.dart';
import 'unit_library.dart';

/// L5-D：单个单元库的爬虫配置页。
///
/// 配置与脚本都留在该单元库目录下（`crawler/`），运行互不影响；
/// 顶级单元库（SECRET）不提供本页。
class UnitCrawlerPage extends StatefulWidget {
  final UnitLibrary unit;
  final String base;
  final Map<String, String> headers;
  final http.Client? client;

  const UnitCrawlerPage({
    super.key,
    required this.unit,
    required this.base,
    required this.headers,
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
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      if (!mounted) return;
      setState(() {
        path = '${j['path'] ?? ''}';
        config = UnitCrawlerConfig.fromJson(j['crawler'] as Map?);
        scripts = UnitCrawlerScript.listFrom(j['scripts']);
        running = (j['running'] as Map?)?['running'] == true;
      });
    } catch (e) {
      if (mounted) setState(() => err = '$e');
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
      final j = jsonDecode(r.body) as Map<String, dynamic>;
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
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已启动 ${j['script'] ?? config.script} pid=${j['pid']}')));
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
                          ? '仅保存配置；实际调度由 NAS cron / 维护接口触发'
                          : '无爬虫脚本，同步设置不可用'),
                      value: hasScript && config.enabled,
                      onChanged: hasScript
                          ? (v) => setState(
                              () => config = config.copyWith(enabled: v))
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const ValueKey('unit-crawler-schedule'),
                      initialValue: config.schedule,
                      enabled: hasScript,
                      decoration: const InputDecoration(
                          labelText: '每日执行时间（HH:MM）', hintText: '04:10'),
                      onChanged: (v) => config = config.copyWith(
                          schedule: normalizeSchedule(v)),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      const Expanded(child: Text('间隔（分钟，0 = 仅按时间）')),
                      Text('${config.intervalMin}'),
                    ]),
                    Slider(
                      value: config.intervalMin.toDouble().clamp(0, 1440),
                      min: 0,
                      max: 1440,
                      divisions: 48,
                      onChanged: hasScript
                          ? (v) => setState(() => config = config.copyWith(
                              intervalMin: normalizeInterval(v.round())))
                          : null,
                    ),
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

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('加载失败：$err', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: load, child: const Text('重试')),
          ]),
        ),
      );

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
    final current = list.any((s) => s.name == config.script)
        ? config.script
        : null;
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
