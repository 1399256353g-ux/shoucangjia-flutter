/// A1：单元库「作者文件夹挂载」面板（客户端入口，长期缺失）。
///
/// owner 原话（2026-11-24）：「这么好的作者文件夹挂载机制你是一点没改啊」。
/// 服务端早就有 `/api/unit-author-groups.json`（GET/POST：merge / split /
/// setFiles / delete）与 `/api/unit/authors.json`（合并后的作者卡），
/// 客户端此前**一个入口都没有**，所以这套能力等于不存在。
///
/// 本页只做服务端已有能力的接线，不新增规则：请求体、前置校验、
/// 作者目录命名全部走 `unit_author_groups.dart`（那层有单测）。
///
/// 三个刻意的设计：
///  1. **派生组与手动组分开呈现**。派生组（`auto:true`）是服务端按同名作者
///     现算的，不落盘；把它和手动组混在一个列表里，用户会以为「删除」能删掉它。
///  2. **拆分要选走哪几项**。服务端 `split` 的语义是「把 keep 列表搬到一个新组，
///     原组保留其余」，所以必须让用户勾选，不能一键拆成单选。
///  3. **每个写操作都先本地校验**再发请求，错误显示在对话框里，而不是
///     发完等 400 再弹一个看不懂的 HTTP 码。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'error_text.dart';
import 'http_json.dart';
import 'load_error_view.dart';
import 'unit_author_groups.dart';
import 'unit_library.dart';

/// 作者文件夹挂载面板。
class UnitAuthorMountPage extends StatefulWidget {
  final UnitLibrary unit;
  final String base;
  final Map<String, String> headers;
  final http.Client? client;

  const UnitAuthorMountPage({
    super.key,
    required this.unit,
    required this.base,
    required this.headers,
    this.client,
  });

  @override
  State<UnitAuthorMountPage> createState() => _UnitAuthorMountPageState();
}

class _UnitAuthorMountPageState extends State<UnitAuthorMountPage> {
  UnitAuthorGroupsState state = const UnitAuthorGroupsState();
  UnitAuthorCards cards = const UnitAuthorCards();
  bool loading = true;
  bool busy = false;
  String? err;

  http.Client get _client => widget.client ?? http.Client();

  /// 单元库标识：一律用 rel（服务端 `resolveUnit` 只认 rel 或 id 反查，
  /// rel 是最直接的一手标识；id 形式在两种 id 语义下可能对不上目录）。
  String get _unitRel => widget.unit.rel;

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
    if (_unitRel.trim().isEmpty) {
      setState(() {
        loading = false;
        err = '顶级单元库没有可挂载的作者文件夹';
      });
      return;
    }
    try {
      final results = await Future.wait([
        _client
            .get(Uri.parse(unitAuthorGroupsUrl(widget.base, _unitRel)),
                headers: widget.headers)
            .timeout(const Duration(seconds: 10)),
        _client
            .get(Uri.parse(unitAuthorsUrl(widget.base, _unitRel)),
                headers: widget.headers)
            .timeout(const Duration(seconds: 10)),
      ]);
      final g = jsonMapOf(results[0]);
      if (results[0].statusCode != 200 || g['ok'] == false) {
        throw Exception('${g['error'] ?? 'HTTP ${results[0].statusCode}'}');
      }
      // 作者卡失败不算整体失败：分组列表仍然可用（只是没有成员候选）。
      UnitAuthorCards c = const UnitAuthorCards();
      if (results[1].statusCode == 200) {
        final cj = jsonOf(results[1]);
        if (cj is Map && cj['ok'] != false) c = UnitAuthorCards.fromJson(cj);
      }
      if (!mounted) return;
      setState(() {
        state = UnitAuthorGroupsState.fromJson(g);
        cards = c;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        err = errorText(e);
      });
    }
  }

  /// 所有「还没被任何手动组占用」的成员（来自作者卡）。
  List<AuthorGroupFile> get _available {
    final claimed = state.claimedKeys;
    final out = <AuthorGroupFile>[];
    for (final c in cards.cards) {
      for (final f in c.files) {
        if (claimed.contains(f.key)) continue;
        out.add(f);
      }
    }
    return mergeableFiles(out);
  }

  /// 成员键 → 展示名。名字只用于本页显示，不外传。
  String _labelOf(AuthorGroupFile f) {
    for (final c in cards.cards) {
      for (final x in c.files) {
        if (x == f && c.name.isNotEmpty) return c.name;
      }
    }
    return f.authorDir;
  }

  Future<void> _send(UnitAuthorRequest req) async {
    setState(() => busy = true);
    try {
      final r = await _client
          .post(
            Uri.parse(unitAuthorGroupsUrl(widget.base, _unitRel)),
            headers: {...widget.headers, 'Content-Type': 'application/json'},
            body: jsonEncode(req.toBody()),
          )
          .timeout(const Duration(seconds: 15));
      final j = jsonOf(r);
      final ok = r.statusCode == 200 && j is Map && j['ok'] != false;
      if (!ok) {
        final msg = j is Map
            ? '${j['error'] ?? 'HTTP ${r.statusCode}'}'
            : 'HTTP ${r.statusCode}';
        throw Exception(msg);
      }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('作者文件夹挂载'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: loading || busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: loading || err != null
          ? null
          : FloatingActionButton.extended(
              onPressed: busy ? null : _openMerge,
              icon: const Icon(Icons.merge_type),
              label: const Text('合并作者'),
            ),
      body: _body(),
    );
  }

  Widget _body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (err != null) return LoadErrorView(message: err!, onRetry: load);

    final manual = state.groups;
    final auto = [
      for (final g in state.auto)
        // 派生组里已经被手动组占用的成员要剔掉，否则同一作者两处各出现一次。
        if (g.files.where((f) => !state.claimedKeys.contains(f.key)).length >=
            2)
          g,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
      children: [
        _sectionTitle('已挂载的手动组 ${manual.length}'),
        if (manual.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text('还没有手动合并的作者组。点右下角「合并作者」把同名作者并到一组。',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        for (final g in manual) _groupTile(g),
        const Divider(height: 24),
        _sectionTitle('可自动合并 ${auto.length}'),
        if (auto.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text('当前单元库内没有同名作者。',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        for (final g in auto) _autoTile(g),
        const Divider(height: 24),
        _sectionTitle('新建作者目录'),
        ListTile(
          leading: const Icon(Icons.create_new_folder_outlined),
          title: const Text('按名字建 @作者 目录'),
          subtitle: const Text('服务端已存在的目录会返回 409，不会覆盖'),
          onTap: busy ? null : _openCreate,
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _groupTile(UnitAuthorGroup g) {
    final files = g.files;
    return ListTile(
      key: ValueKey('uag-group-${g.id}'),
      title: Row(children: [
        Expanded(
            child: Text(g.name.isEmpty ? '未命名组' : g.name,
                overflow: TextOverflow.ellipsis)),
        if (g.split)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child:
                Text('已拆', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
      ]),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${files.length} 个文件夹 · ${g.works} 作品',
              style: const TextStyle(fontSize: 11)),
          for (final f in files.take(6))
            Text('· ${_labelOf(f)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis),
          if (files.length > 6)
            Text('… 另 ${files.length - 6} 个',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
      isThreeLine: true,
      // 菜单值用枚举本身，而不是手写字符串——协议名只在 UnitAuthorAction 里
      trailing: PopupMenuButton<UnitAuthorAction>(
        enabled: !busy,
        onSelected: (v) {
          if (v == UnitAuthorAction.split) _openSplit(g);
          if (v == UnitAuthorAction.setFiles) _openSetFiles(g);
          if (v == UnitAuthorAction.delete) _confirmDelete(g);
        },
        itemBuilder: (_) => const <PopupMenuEntry<UnitAuthorAction>>[
          PopupMenuItem(value: UnitAuthorAction.split, child: Text('拆出成员')),
          // setFiles 此前只在协议层存在、页面零入口：想给已有组增/减成员
          // 只能删了重建，重建会丢掉 `split:true`（永不再自动合并）的语义。
          PopupMenuItem(value: UnitAuthorAction.setFiles, child: Text('编辑成员')),
          PopupMenuItem(value: UnitAuthorAction.delete, child: Text('删除该组')),
        ],
      ),
    );
  }

  Widget _autoTile(UnitAuthorGroup g) {
    return ListTile(
      key: ValueKey('uag-auto-${g.id}'),
      title: Text(g.name.isEmpty ? '未命名' : g.name,
          overflow: TextOverflow.ellipsis),
      subtitle: Text('自动合并候选 · ${g.files.length} 个文件夹',
          style: const TextStyle(fontSize: 11)),
      trailing: FilledButton.tonal(
        onPressed: busy ? null : () => _mergeFiles(g.files, name: g.name),
        child: const Text('固定为手动组'),
      ),
    );
  }

  Future<void> _mergeFiles(List<AuthorGroupFile> files,
      {String name = ''}) async {
    final req = UnitAuthorRequest(
      unit: _unitRel,
      action: UnitAuthorAction.merge,
      name: name,
      files: files,
    );
    final bad = req.error;
    if (bad != null) {
      _toast(bad, bad: true);
      return;
    }
    await _send(req);
  }

  Future<void> _openMerge() async {
    final available = _available;
    if (available.isEmpty) {
      _toast('没有可挂载的作者文件夹（可能全部已在组内）', bad: true);
      return;
    }
    final picked = <String>{};
    final nameCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('合并作者文件夹'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('勾选要合并的文件夹（至少 1 个）。服务端会按成员重新聚合作品数与封面。',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final f in available)
                      CheckboxListTile(
                        key: ValueKey('uag-pick-${f.key}'),
                        dense: true,
                        value: picked.contains(f.key),
                        title: Text(_labelOf(f),
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(f.lib,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                        onChanged: (v) => setD(() {
                          if (v == true) {
                            picked.add(f.key);
                          } else {
                            picked.remove(f.key);
                          }
                        }),
                      ),
                  ]),
                ),
              ),
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(
                  labelText: '组名（可留空，默认取第一个成员）',
                  isDense: true,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            FilledButton(
              key: const ValueKey('uag-merge-ok'),
              onPressed: picked.isEmpty ? null : () => Navigator.pop(c, true),
              child: const Text('合并'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _mergeFiles(
      [
        for (final f in available)
          if (picked.contains(f.key)) f
      ],
      name: nameCtl.text.trim(),
    );
  }

  Future<void> _openSplit(UnitAuthorGroup g) async {
    final picked = <String>{};
    final nameCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('拆出成员'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('勾选的成员会搬到新组，原组保留其余成员（不能全拆走，那是删除）。',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final f in g.files)
                      CheckboxListTile(
                        key: ValueKey('uag-split-${f.key}'),
                        dense: true,
                        value: picked.contains(f.key),
                        title: Text(_labelOf(f),
                            style: const TextStyle(fontSize: 13)),
                        onChanged: (v) => setD(() {
                          if (v == true) {
                            picked.add(f.key);
                          } else {
                            picked.remove(f.key);
                          }
                        }),
                      ),
                  ]),
                ),
              ),
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(
                  labelText: '新组名（可留空）',
                  isDense: true,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            FilledButton(
              key: const ValueKey('uag-split-ok'),
              onPressed: picked.isEmpty ? null : () => Navigator.pop(c, true),
              child: const Text('拆出'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final files = [
      for (final f in g.files)
        if (picked.contains(f.key)) f
    ];
    final req = UnitAuthorRequest(
      unit: _unitRel,
      action: UnitAuthorAction.split,
      groupId: g.id,
      name: nameCtl.text.trim(),
      files: files,
    );
    final bad = unitAuthorRequestError(
      action: req.action,
      unit: req.unit,
      groupId: g.id,
      files: files,
      groupFiles: g.files,
    );
    if (bad != null) {
      _toast(bad, bad: true);
      return;
    }
    await _send(req);
  }

  /// setFiles：整组替换成员（增/减都走这一个动作）。
  ///
  /// 与 split 的区别必须说清：split 是「搬走勾选的、原组留其余」，
  /// setFiles 是「保存后的列表就是完整成员表」。所以这里预勾原成员，
  /// 取消勾选即移出，再从可候选里勾新的。
  Future<void> _openSetFiles(UnitAuthorGroup g) async {
    final available = _available;
    final picked = <String>{for (final f in g.files) f.key};
    final pool = <AuthorGroupFile>[...g.files];
    for (final f in available) {
      if (!picked.contains(f.key)) pool.add(f);
    }
    final nameCtl = TextEditingController(text: g.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('编辑组成员'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('保存后的勾选就是完整成员表；取消勾选即移出该组（不会删任何目录）。',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: [
                    for (final f in pool)
                      CheckboxListTile(
                        key: ValueKey('uag-setfiles-${f.key}'),
                        dense: true,
                        value: picked.contains(f.key),
                        title: Text(_labelOf(f),
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(f.lib,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                        onChanged: (v) => setD(() {
                          if (v == true) {
                            picked.add(f.key);
                          } else {
                            picked.remove(f.key);
                          }
                        }),
                      ),
                  ]),
                ),
              ),
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(
                  labelText: '组名（可留空，保留原名）',
                  isDense: true,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            FilledButton(
              key: const ValueKey('uag-setfiles-ok'),
              onPressed: picked.isEmpty ? null : () => Navigator.pop(c, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _send(UnitAuthorRequest(
      unit: _unitRel,
      action: UnitAuthorAction.setFiles,
      groupId: g.id,
      name: nameCtl.text.trim(),
      files: [
        for (final f in pool)
          if (picked.contains(f.key)) f
      ],
    ));
  }

  Future<void> _confirmDelete(UnitAuthorGroup g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除作者组'),
        content: Text('删除「${g.name.isEmpty ? '未命名组' : g.name}」？'
            '只删分组记录，不动任何作者目录与作品文件。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
            key: const ValueKey('uag-delete-ok'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _send(UnitAuthorRequest(
      unit: _unitRel,
      action: UnitAuthorAction.delete,
      groupId: g.id,
    ));
  }

  Future<void> _openCreate() async {
    final basics = widget.unit.allBasics;
    if (basics.isEmpty) {
      _toast('该单元库下没有基础库，无法建作者目录', bad: true);
      return;
    }
    var lib = basics.first.id;
    final nameCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('新建作者目录'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: lib,
                decoration:
                    const InputDecoration(labelText: '基础库', isDense: true),
                items: [
                  for (final b in basics)
                    DropdownMenuItem(
                        value: b.id,
                        child: Text(b.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setD(() => lib = v ?? lib),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('uag-create-name'),
                controller: nameCtl,
                decoration: const InputDecoration(
                  labelText: '作者名（会建成 @作者名 目录）',
                  isDense: true,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            FilledButton(
              key: const ValueKey('uag-create-ok'),
              onPressed: nameCtl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(c, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final dir = authorDirForName(nameCtl.text);
    final bad = authorDirError(dir);
    if (bad != null) {
      _toast(bad, bad: true);
      return;
    }
    setState(() => busy = true);
    try {
      final r = await _client
          .post(
            Uri.parse(unitAuthorCreateUrl(widget.base)),
            headers: {...widget.headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'lib': lib, 'name': nameCtl.text.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      final j = jsonOf(r);
      if (r.statusCode != 200 || (j is Map && j['ok'] == false)) {
        final msg = j is Map
            ? '${j['error'] ?? 'HTTP ${r.statusCode}'}'
            : 'HTTP ${r.statusCode}';
        // 409 是「已存在」，属于用户可理解的结果，不是错误路径。
        throw Exception(r.statusCode == 409 ? '该作者目录已存在' : msg);
      }
      await load();
      if (!mounted) return;
      _toast('已创建作者目录');
    } catch (e) {
      if (!mounted) return;
      _toast(errorText(e), bad: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
