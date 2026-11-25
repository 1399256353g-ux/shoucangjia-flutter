/// 作者主页的「作者文件夹挂载」面板（owner 2026-11-25）。
///
/// owner：「这套机制怎么想挂载入口也应该在作者主页吧，单元库点进去再选哪个
/// 作者吗？搞笑」。
///
/// 挂载是**作者维度**的事：打开某个人，才该看到这个人存在于哪些基础库、
/// 哪些文件夹，以及是否已经合并。原来的入口在单元库页，要先进库再在几百个
/// 作者里找一个，方向就是错的。
///
/// 本面板只做三件事：
///  1. 列出这个作者在哪些「基础库 / 文件夹」里（只读，来自 `/api/author/mounts`）；
///  2. 同一单元库内 ≥2 处时，可一键合并成一张作者卡；
///  3. 已合并的组可拆回去（拆出来的那份永远不再自动合并）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'error_text.dart';
import 'http_error_text.dart';
import 'http_json.dart';
import 'json_num.dart';
import 'count_label.dart';
import 'rel_path.dart';
import 'unit_author_groups.dart';

/// 打开作者挂载面板。
Future<bool?> showAuthorMountSheet({
  required BuildContext context,
  required String authorName,
  required String base,
  required Map<String, String> headers,
  http.Client? client,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AuthorMountSheet(
      authorName: authorName,
      base: base,
      headers: headers,
      client: client,
    ),
  );
}

class _AuthorMountSheet extends StatefulWidget {
  const _AuthorMountSheet({
    required this.authorName,
    required this.base,
    required this.headers,
    this.client,
  });

  final String authorName;
  final String base;
  final Map<String, String> headers;
  final http.Client? client;

  @override
  State<_AuthorMountSheet> createState() => _AuthorMountSheetState();
}

class _AuthorMountSheetState extends State<_AuthorMountSheet> {
  AuthorMounts mounts = AuthorMounts.empty;
  bool loading = true;
  bool busy = false;
  String? err;

  http.Client get _client => widget.client ?? http.Client();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final r = await _client
          .get(Uri.parse(authorMountsUrl(widget.base, widget.authorName)),
              headers: widget.headers)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      // 解码走唯一出口 jsonOf（字符集策略只有一处，见 http_json.dart）。
      final raw = jsonOf(r);
      if (!mounted) return;
      setState(() {
        mounts = AuthorMounts.fromJson(raw);
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

  /// 把该单元库内的全部来源合并成一组。
  Future<void> _mergeAll(String unit) async {
    if (busy) return;
    final files = <AuthorGroupFile>[
      for (final i in mounts.items)
        if (i.unitRel == unit) AuthorGroupFile(lib: i.lib, authorDir: i.authorDir),
    ];
    if (files.length < 2) return;
    final req = UnitAuthorRequest(
      unit: unit,
      action: UnitAuthorAction.merge,
      name: widget.authorName,
      files: files,
    );
    final bad = req.error;
    if (bad != null) {
      _toast(bad, bad: true);
      return;
    }
    await _send(req, unit);
  }

  /// 把这个组拆成「只留第一个成员」，其余成员各自独立。
  Future<void> _split(AuthorMountGroup g) async {
    if (busy) return;
    if (g.files.length < 2) {
      _toast('这个组只有一个文件夹，无需拆分', bad: true);
      return;
    }
    final keep = g.files.first;
    final req = UnitAuthorRequest(
      unit: g.unit,
      action: UnitAuthorAction.split,
      groupId: g.groupId,
      files: <AuthorGroupFile>[keep],
      groupFiles: g.files,
    );
    final bad = req.error;
    if (bad != null) {
      _toast(bad, bad: true);
      return;
    }
    await _send(req, g.unit);
  }

  /// 解散一个手动组（成员回到各自独立状态）。
  Future<void> _dissolve(AuthorMountGroup g) async {
    if (busy) return;
    final req = UnitAuthorRequest(
      unit: g.unit,
      action: UnitAuthorAction.delete,
      groupId: g.groupId,
    );
    final bad = req.error;
    if (bad != null) {
      _toast(bad, bad: true);
      return;
    }
    await _send(req, g.unit);
  }

  Future<void> _send(UnitAuthorRequest req, String unit) async {
    setState(() => busy = true);
    try {
      final r = await _client
          .post(
            Uri.parse(unitAuthorGroupsUrl(widget.base, unit)),
            headers: {...widget.headers, 'Content-Type': 'application/json'},
            body: jsonEncode(req.toBody()),
          )
          .timeout(const Duration(seconds: 15));
      final j = jsonOf(r);
      throwIfApiFailed(r.statusCode, j);
      await load();
      if (!mounted) return;
      _toast('已保存');
    } catch (e) {
      if (!mounted) return;
      _toast(errorText(e), bad: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _toast(String msg, {bool bad = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bad ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(children: [
              const Icon(Icons.folder_shared_outlined, size: 18),
              const SizedBox(width: 8),
              const Text('作者文件夹挂载',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (busy)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '同一个作者可能被放在多个基础库或文件夹里。这里列出全部分布，'
              '可把它们合并成一张作者卡（只影响显示与归类，不动任何文件）。',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ),
          const Divider(height: 1),
          Flexible(child: _body(cs)),
        ]),
      ),
    );
  }

  Widget _body(ColorScheme cs) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (err != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('读取失败：$err',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          FilledButton(onPressed: load, child: const Text('重试')),
        ]),
      );
    }
    if (mounts.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('没有找到这个作者的目录',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }

    final units = mounts.units;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        // 概要：几库几处
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            '共 ${mounts.libCount} 个基础库 · ${mounts.dirCount} 个文件夹'
            '${mounts.sameUnitOnly ? ' · 同一单元库内' : ' · 跨 ${units.length} 个单元库'}',
            style: const TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        ),
        for (final u in units) _unitSection(u, cs),
        if (!mounts.sameUnitOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(
              '这些文件夹分属不同单元库，服务端只会在同一单元库内合并——'
              '跨单元库的同名作者各自独立显示。',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _unitSection(String unit, ColorScheme cs) {
    final items = [for (final i in mounts.items) if (i.unitRel == unit) i];
    final gid = mounts.groupIdIn(unit);
    AuthorMountGroup? group;
    for (final g in mounts.groups) {
      if (g.unit == unit) {
        group = g;
        break;
      }
    }
    // 拆分走 `rel_path.dart` 唯一实现（连 `\` 一起认）：旧写法 `split('/').last`
    // 遇到服务端下发的 `A\B` 会把整条路径当名字贴在分组标题上。
    final unitTail = lastRelName(unit);
    final unitLabel = unit.isEmpty
        ? '无归属'
        : (unitTail.isEmpty ? unit : unitTail);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.layers_outlined, size: 15, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(unitLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            if (gid.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(boolOf(group?.split) ? '已拆分' : '已合并',
                    style: TextStyle(fontSize: 10, color: cs.primary)),
              ),
          ]),
          const SizedBox(height: 6),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(Icons.folder_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${i.displayLib} · ${i.authorDir}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                if (i.works > 0)
                  Text('${formatCount(i.works)} 作品',
                      style:
                          const TextStyle(fontSize: 10.5, color: Colors.grey)),
              ]),
            ),
          if (items.length >= 2) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (gid.isEmpty)
                FilledButton.tonalIcon(
                  onPressed: busy ? null : () => _mergeAll(unit),
                  icon: const Icon(Icons.merge_type, size: 16),
                  label: Text('合并这 ${items.length} 处'),
                )
              else ...[
                if (group != null && group.files.length >= 2)
                  TextButton.icon(
                    onPressed: busy ? null : () => _split(group!),
                    icon: const Icon(Icons.call_split, size: 16),
                    label: const Text('拆分'),
                  ),
                TextButton.icon(
                  onPressed: busy ? null : () => _dissolve(group!),
                  icon: const Icon(Icons.link_off, size: 16),
                  label: const Text('解散合并'),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}
