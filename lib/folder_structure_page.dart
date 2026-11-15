import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 文件结构列表：把库里所有文件夹平铺成可折叠的树，
/// 供 owner 指定「节点文件夹」（单元库）。默认只有 SECRET 顶级节点。
///
/// 数据：`GET /api/folders` → { root, top:{name,rel}, folders:[{rel,name,depth,authors,isNode,dirs}] }
/// 保存：`POST /api/nodes` body {nodes:[rel,...]}
class FolderStructurePage extends StatefulWidget {
  final Uri Function(String path) urlOf;
  final Map<String, String> Function() headersOf;
  final Future<void> Function(List<String> nodes)? onSaved;

  const FolderStructurePage({
    super.key,
    required this.urlOf,
    required this.headersOf,
    this.onSaved,
  });

  @override
  State<FolderStructurePage> createState() => _FolderStructurePageState();
}

class _FolderRow {
  final String rel;
  final String name;
  final int depth;
  final int authors;
  final List<_FolderRow> children;

  _FolderRow({
    required this.rel,
    required this.name,
    required this.depth,
    required this.authors,
    required this.children,
  });
}

class _FolderStructurePageState extends State<FolderStructurePage> {
  String topName = 'SECRET';
  String topRel = '';
  List<_FolderRow> rows = [];
  final Set<String> expanded = <String>{};
  final Set<String> nodes = <String>{};
  final Set<String> saved = <String>{};
  bool loading = true;
  bool saving = false;
  String? err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      final r = await http
          .get(widget.urlOf('/api/folders'), headers: widget.headersOf())
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final top = j['top'];
      topName = '${top is Map ? (top['name'] ?? 'SECRET') : 'SECRET'}';
      topRel = '${top is Map ? (top['rel'] ?? '') : ''}';
      nodes
        ..clear()
        ..addAll(((j['nodes'] as List?) ?? const []).map((e) => '$e'));
      saved
        ..clear()
        ..addAll(nodes);
      rows = _parse(((j['folders'] as List?) ?? const []));
      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        err = '$e';
      });
    }
  }

  List<_FolderRow> _parse(List list) {
    final out = <_FolderRow>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final rel = '${raw['rel'] ?? ''}'.trim();
      if (rel.isEmpty) continue;
      out.add(_FolderRow(
        rel: rel,
        name: '${raw['name'] ?? rel}'.trim(),
        depth: (raw['depth'] is num) ? (raw['depth'] as num).toInt() : 1,
        authors: (raw['authors'] is num) ? (raw['authors'] as num).toInt() : 0,
        children: _parse((raw['dirs'] as List?) ?? const []),
      ));
    }
    return out;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final r = await http
          .post(
            widget.urlOf('/api/nodes'),
            headers: {
              ...widget.headersOf(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'nodes': nodes.toList()}),
          )
          .timeout(const Duration(seconds: 20));
      final j = r.statusCode == 200
          ? jsonDecode(utf8.decode(r.bodyBytes))
          : null;
      if (r.statusCode != 200 || j is! Map || j['ok'] != true) {
        throw (j is Map && j['error'] != null)
            ? '${j['error']}'
            : 'HTTP ${r.statusCode}';
      }
      saved
        ..clear()
        ..addAll(nodes);
      await widget.onSaved?.call(nodes.toList());
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('节点设置已保存')));
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  bool get dirty =>
      nodes.length != saved.length || !nodes.every(saved.contains);

  void _toggleExpand(String rel) {
    setState(() {
      if (!expanded.remove(rel)) expanded.add(rel);
    });
  }

  void _toggleNode(String rel) {
    setState(() {
      if (!nodes.remove(rel)) nodes.add(rel);
    });
  }

  Widget _buildRow(_FolderRow r) {
    final open = expanded.contains(r.rel);
    final isNode = nodes.contains(r.rel);
    final hasKids = r.children.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('folder-${r.rel}'),
          onTap: () => _toggleNode(r.rel),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10.0 + (r.depth - 1) * 18, 6, 8, 6),
            child: Row(children: [
              SizedBox(
                width: 26,
                child: hasKids
                    ? InkResponse(
                        key: ValueKey('folder-expand-${r.rel}'),
                        onTap: () => _toggleExpand(r.rel),
                        child: AnimatedRotation(
                          turns: open ? 0.25 : 0,
                          duration: const Duration(milliseconds: 120),
                          child: const Icon(Icons.chevron_right, size: 18),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Icon(
                isNode ? Icons.hub_outlined : Icons.folder_outlined,
                size: 17,
                color: isNode
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                isNode ? FontWeight.w700 : FontWeight.w500)),
                    if (r.authors > 0)
                      Text('${r.authors} 位作者',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              if (isNode)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('节点',
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              Switch(
                key: ValueKey('node-switch-${r.rel}'),
                value: isNode,
                onChanged: (_) => _toggleNode(r.rel),
              ),
            ]),
          ),
        ),
        if (open)
          for (final c in r.children) _buildRow(c),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件结构'),
        actions: [
          TextButton(
            onPressed: (dirty && !saving) ? _save : null,
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('加载失败：$err',
                        style: const TextStyle(fontSize: 12)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        const Icon(Icons.layers_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('顶级节点：$topName',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text('已选 ${nodes.length} 个节点',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ]),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text('点目录行或右侧开关，把目录设为「节点文件夹」（单元库）；默认只有顶级 SECRET。',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                    for (final r in rows) _buildRow(r),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('该库下没有子文件夹',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ),
                  ],
                ),
    );
  }
}
