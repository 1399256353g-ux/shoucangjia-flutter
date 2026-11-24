import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'http_json.dart';
import 'http_error_text.dart';

import 'api_url.dart';
import 'collection_sync.dart';
import 'error_text.dart';

/// 单元库爬虫设置里的「同步源」区块（owner 2026-11-21 要求）。
///
/// 旧设置页有一个全局「同步源选择」入口，和具体单元库脱节；现在把
/// 与当前单元库同名的同步源直接放进该单元库的爬虫设置里：
/// - 目录名 `(2) 丝` ↔ 同步源 `丝`；
/// - 顶级单元库（如 `(2) douyin`）显示全部同步源；
/// - 勾选状态仍写回 `/api/settings`，因此主页/库选择页的可见性语义不变。
class CollectionSyncPanel extends StatefulWidget {
  final String base;
  final Map<String, String> headers;

  /// 当前注册库 id（用于 `/api/settings?lib=`）。
  final String libId;
  final String unitName;
  final String unitRel;
  final http.Client? client;
  final VoidCallback? onChanged;

  const CollectionSyncPanel({
    super.key,
    required this.base,
    required this.headers,
    required this.unitName,
    required this.unitRel,
    this.libId = '',
    this.client,
    this.onChanged,
  });

  @override
  State<CollectionSyncPanel> createState() => _CollectionSyncPanelState();
}

class _CollectionSyncPanelState extends State<CollectionSyncPanel> {
  List<CollectionSyncInfo> all = const <CollectionSyncInfo>[];
  int? defaultIdx;
  int accountCount = 0;
  bool loading = true;
  bool saving = false;
  String? err;

  http.Client get _client => widget.client ?? http.Client();

  Uri get _settingsUri {
    final base = baseForJoin(widget.base);
    final q = widget.libId.isEmpty
        ? ''
        : '?lib=${Uri.encodeQueryComponent(widget.libId)}';
    return Uri.parse('$base/api/settings$q');
  }

  List<CollectionSyncInfo> get visible => syncCollectionsForUnit(
        all,
        unitName: widget.unitName,
        unitRel: widget.unitRel,
      );

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
    if (widget.base.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        loading = false;
        err = '未配置服务器地址';
      });
      return;
    }
    try {
      final r = await _client
          .get(_settingsUri, headers: widget.headers)
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      final j = jsonMapOf(r);
      final list = parseCollectionSettings(j);
      if (!mounted) return;
      setState(() {
        all = list;
        defaultIdx = (j['default'] as num?)?.toInt();
        accountCount =
            (j['accountCount'] as num?)?.toInt() ?? list.where((e) => e.account).length;
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

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final r = await _client.post(_settingsUri,
          headers: {...widget.headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'default': defaultIdx,
            'collections': [
              for (final c in all)
                {'idx': c.idx, 'name': c.name, 'sync': c.sync}
            ],
          }));
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      final j = jsonMapOf(r);
      final list = parseCollectionSettings(j);
      if (!mounted) return;
      setState(() {
        all = list;
        defaultIdx = (j['default'] as num?)?.toInt();
        saving = false;
      });
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('同步源保存失败：${errorText(e)}')));
    }
  }

  void _toggle(CollectionSyncInfo c, bool value) {
    setState(() {
      final i = all.indexWhere((e) => e.idx == c.idx);
      if (i < 0) return;
      all[i] = CollectionSyncInfo(
        idx: c.idx,
        name: c.name,
        count: c.count,
        sync: value,
        inIndex: c.inIndex,
        account: c.account,
        customName: c.customName,
      );
      if (!value && defaultIdx == c.idx) {
        int? next;
        for (final e in all) {
          if (e.sync) {
            next = e.idx;
            break;
          }
        }
        defaultIdx = next;
      }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = visible;
    final enabled = rows.where((e) => e.sync).length;
    return Column(
      key: const ValueKey('unit-sync-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.sync_alt, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('同步源',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          if (loading || saving)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 4),
        Text(
          loading
              ? '正在读取账号同步源…'
              : err != null
                  ? '读取失败：$err'
                  : rows.isEmpty
                      ? '未找到与「${widget.unitName}」同名的同步源'
                      : '该单元库对应 ${rows.length} 个同步源 · $enabled 个参与同步',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        if (err != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: load, child: const Text('重试读取同步源')),
          ),
        for (final c in rows)
          SwitchListTile(
            key: ValueKey('unit-sync-${c.idx}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              c.subtitleWith(isDefault: defaultIdx == c.idx),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            value: c.sync,
            onChanged: loading || saving ? null : (v) => _toggle(c, v),
          ),
        if (!loading && err == null && rows.isNotEmpty)
          Text(
            '未勾选的同步源不参与同步，也不会出现在主页/库选择页。',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
      ],
    );
  }
}
