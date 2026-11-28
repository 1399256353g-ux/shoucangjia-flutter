/// 单元库「作者挂载」页：**只按基础库**，没有目录树。
///
/// owner 2026-11-28：
/// > 「挂载还是不行，原来的那些设置逻辑特别混乱啊根本没法用，删掉啊还留着干嘛」
///
/// 旧实现并存三套逻辑（目录树勾选合并 / 拆出成员 / 编辑成员），三套都要求
/// 用户理解「文件夹」这一层；而服务端真正能做的事只有一件：**同一单元库内
/// 同名作者默认就是同一个人**（`autoGroupsFor`）。用户要回答的只是
/// 「这个人在哪些基础库有作品」。
///
/// 所以整页只剩两件事：
///  1. 勾基础库 → 在对应库里建 `@作者` 目录（已存在直接用）；
///  2. 已合并的组：可把其中某几个基础库**拆出去**，或整个解散。
///
/// 拆出仍然走服务端既有协议（`split`），但候选从「文件夹」换成「基础库」——
/// 一个作者在一个基础库里只有一个目录，所以按基础库勾选与按目录勾选等价，
/// 而前者是用户脑子里的概念。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_timeout.dart';
import 'basic_lib.dart' show BasicLib;
import 'confirm_dialog.dart';
import 'error_text.dart';
import 'http_json.dart';
import 'label_fallback.dart';
import 'load_error_view.dart';
import 'loading_view.dart';
import 'text_styles.dart';
import 'toast.dart';
import 'ui_copy.dart';
import 'split_libs_dialog.dart';
import 'unit_author_groups.dart';
import 'unit_library.dart';

/// 作者挂载面板（单元库入口）。
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
  bool loading = true;
  bool busy = false;
  String? err;

  /// 基础库里要建目录的那些（勾选）。
  final Set<String> _pickedBasics = <String>{};

  http.Client? _ownClient;
  http.Client get _client => widget.client ?? (_ownClient ??= http.Client());

  /// 单元库标识：一律用 rel（服务端 `resolveUnit` 只认 rel 或 id 反查）。
  String get _unitRel => widget.unit.rel;

  /// 直属上级单元库下的全部基础库——作品不得跨出这个范围。
  List<BasicLib> get _scopeBasics => basicsOfUnitScope(widget.unit.allBasics);

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

  /// 只读一份数据：分组表（`groups` + `auto`）。
  ///
  /// 旧实现还多取两份（作者卡、全部目录）喂目录树控件；树删了，
  /// 那两个请求也一起删了——少两次往返，页面开屏更快。
  Future<void> load() async {
    setState(() {
      loading = true;
      err = null;
    });
    if (_unitRel.trim().isEmpty) {
      setState(() {
        loading = false;
        err = '媒体库没有可挂载的作者目录';
      });
      return;
    }
    try {
      final r = await _client
          .get(Uri.parse(unitAuthorGroupsUrl(widget.base, _unitRel)),
              headers: widget.headers)
          .timeout(kTimeoutRead);
      final g = jsonMapOf(r);
      throwIfApiFailed(r.statusCode, g);
      if (!mounted) return;
      setState(() {
        state = UnitAuthorGroupsState.fromJson(g);
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

  Future<void> _send(UnitAuthorRequest req) async {
    setState(() => busy = true);
    try {
      final r = await _client
          .post(
            Uri.parse(unitAuthorGroupsUrl(widget.base, _unitRel)),
            headers: {...widget.headers, 'Content-Type': 'application/json'},
            body: jsonEncode(req.toBody()),
          )
          .timeout(kTimeoutWrite);
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

  void _toast(String msg, {bool bad = false}) =>
      showToast(this, msg, bad: bad);

  /// 基础库 id → 显示名（拿不到回落 id，不留空标题）。
  String _libLabelOf(String lib) {
    for (final b in _scopeBasics) {
      if (b.id == lib) return libLabelOf(b.id, b.name);
    }
    return lib;
  }

  /// 在一个组里出现的基础库（去重、保持出现顺序）。
  List<String> _libsOf(UnitAuthorGroup g) {
    final seen = <String>{};
    final out = <String>[];
    for (final f in g.files) {
      if (seen.add(f.lib)) out.add(f.lib);
    }
    return out;
  }

  Future<void> _createAuthorDirs() async {
    if (_pickedBasics.isEmpty) return;
    final nameCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('建作者目录'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('将在选中的 ${_pickedBasics.length} 个基础库下建 @作者 目录',
                  style: kHintTextStyle),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('uag-create-dir-name'),
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: kAuthorNameFieldLabel,
                  isDense: true,
                ),
                onChanged: (_) => setD(() {}),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            FilledButton(
              key: const ValueKey('uag-create-dir-ok'),
              onPressed: nameCtl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(c, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final dir = authorDirForName(nameCtl.text);
    final bad = authorDirError(dir);
    if (bad != null) {
      _toast(bad, bad: true);
      return;
    }
    setState(() => busy = true);
    var made = 0;
    var existed = 0;
    final failed = <String>[];
    try {
      for (final body in createAuthorBodies(authorDir: dir, libs: _pickedBasics)) {
        try {
          final r = await _client
              .post(
                Uri.parse(unitAuthorCreateUrl(widget.base)),
                headers: {...widget.headers, 'Content-Type': 'application/json'},
                body: jsonEncode(body),
              )
              .timeout(kTimeoutWrite);
          if (r.statusCode == 409) {
            existed++;
          } else if (r.statusCode == 200) {
            made++;
          } else {
            failed.add('${body['lib']}');
          }
        } catch (_) {
          failed.add('${body['lib']}');
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted) return;
    _toast(
        authorCreateSummary(made: made, existed: existed, failed: failed.length),
        bad: failed.isNotEmpty);
    if (made > 0 || existed > 0) await load();
  }

  /// 把自动合并的组固定成手动组——之后才能按基础库拆。
  ///
  /// 服务端 `split` 只认落盘的手动组（`rec.groups`），自动组是现算的、
  /// 没有组记录可拆，所以先 `merge` 成组，再由用户决定拆哪几个库出去。
  Future<void> _pinAsManual(UnitAuthorGroup g) async {
    final req = UnitAuthorRequest(
      unit: _unitRel,
      action: UnitAuthorAction.merge,
      name: g.name,
      files: g.files,
    );
    final bad = req.error;
    if (bad != null) {
      _toast(bad, bad: true);
      return;
    }
    await _send(req);
  }

  /// 拆出：勾选要把哪些**基础库**从这个组里分出去。
  ///
  /// 一个作者在一个基础库里只有一个目录，所以「按基础库勾」与「按目录勾」
  /// 等价——而基础库是用户真正认识的那一层。
  Future<void> _openSplit(UnitAuthorGroup g) async {
    final libs = _libsOf(g);
    if (libs.length < 2) {
      _toast('这个组只有一个基础库，无需拆分', bad: true);
      return;
    }
    final picked = await pickLibsToSplit(
      context,
      libs: libs,
      labelOf: _libLabelOf,
      keyPrefix: 'uag',
    );
    if (picked == null) return;
    final files = <AuthorGroupFile>[
      for (final f in g.files)
        if (picked.contains(f.lib)) f,
    ];
    final req = UnitAuthorRequest(
      unit: _unitRel,
      action: UnitAuthorAction.split,
      groupId: g.id,
      files: files,
      groupFiles: g.files,
    );
    final bad = req.error;
    if (bad != null) {
      _toast(bad, bad: true);
      return;
    }
    await _send(req);
  }

  Future<void> _dissolve(UnitAuthorGroup g) async {
    final ok = await confirmAction(
      context,
      title: '解散合并',
      message: '把「${g.name.isEmpty ? '该组' : g.name}」解散？'
          '这是作者在多个基础库的同名目录，解散后按默认规则重新归类。'
          '只删分组记录，不动任何作者目录与作品文件。',
      confirmLabel: '解散',
      confirmKey: const ValueKey('uag-delete-ok'),
    );
    if (!ok) return;
    await _send(UnitAuthorRequest(
      unit: _unitRel,
      action: UnitAuthorAction.delete,
      groupId: g.id,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kAuthorMountTitle),
        actions: [
          IconButton(
            tooltip: kRefreshTooltip,
            onPressed: loading || busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: (loading || err != null || _pickedBasics.isEmpty)
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('uag-create-dirs'),
              onPressed: busy ? null : _createAuthorDirs,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text('建作者目录（${_pickedBasics.length}）'),
            ),
      body: _body(),
    );
  }

  Widget _body() {
    if (loading) return const LoadingView();
    if (err != null) return LoadErrorView(message: err!, onRetry: load);

    // 手动组里只有一个基础库的没有展示价值；多基础库的才值得看/拆。
    final multiLib = [
      for (final g in state.groups)
        if (_libsOf(g).length >= 2) g,
    ];
    // 自动合并组：服务端已按同名合并，列出来只是让用户知道「这些是同一个人」。
    final auto = [
      for (final g in state.auto)
        if (state.groups
                .where((x) => g.files.any((f) => x.files.contains(f)))
                .isEmpty)
          g,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
      children: [
        _sectionTitle('选基础库'),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
              '勾选这个作者有作品的基础库，点右下角按钮在这些库里建 @作者 目录。'
              '已存在的目录直接使用，不会被覆盖。',
              style: kHintTextStyle),
        ),
        for (final b in _scopeBasics)
          CheckboxListTile(
            key: ValueKey('uag-scope-${b.id}'),
            dense: true,
            value: _pickedBasics.contains(b.id),
            title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: busy
                ? null
                : (v) => setState(() {
                      if (v == true) {
                        _pickedBasics.add(b.id);
                      } else {
                        _pickedBasics.remove(b.id);
                      }
                    }),
          ),
        const Divider(height: 24),
        _sectionTitle('跨基础库合并 ${multiLib.length}'),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
              '同一单元库里同名目录默认就是同一位作者。想拆开某几个基础库，点「拆出」。',
              style: kHintTextStyle),
        ),
        if (multiLib.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text('没有跨基础库的合并。', style: kHintTextStyle),
          ),
        for (final g in multiLib) _groupTile(g),
        const Divider(height: 24),
        _sectionTitle('同名自动合并 ${auto.length}'),
        if (auto.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text('当前单元库内没有跨基础库的同名作者。',
                style: kHintTextStyle),
          ),
        for (final g in auto) _autoTile(g),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _groupTile(UnitAuthorGroup g) {
    final libs = _libsOf(g);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(g.name.isEmpty ? '未命名作者' : g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            if (g.split)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('已拆分',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
              ),
          ]),
          const SizedBox(height: 4),
          // 副标题走 `g.summary`（`authorMergeSummary` 的出口）——
          // 契约：面板不得自己拼「N 个文件夹」。基础库个数用 chip 展示，
          // 那是另一种事实（跨了几个库），不与摘要重复。
          Text(g.summary, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final lib in libs)
              Chip(
                label: Text(_libLabelOf(lib),
                    style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 4, children: [
            TextButton.icon(
              key: ValueKey('uag-split-${g.id}'),
              onPressed: busy ? null : () => _openSplit(g),
              icon: const Icon(Icons.call_split, size: 16),
              label: const Text('拆出'),
            ),
            TextButton.icon(
              key: ValueKey('uag-dissolve-${g.id}'),
              onPressed: busy ? null : () => _dissolve(g),
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('解散'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _autoTile(UnitAuthorGroup g) {
    return ListTile(
      key: ValueKey('uag-auto-${g.id}'),
      dense: true,
      title: Text(g.name.isEmpty ? '未命名' : g.name,
          overflow: TextOverflow.ellipsis),
      subtitle: Text('${_libsOf(g).length} 个基础库 · 同名自动合并',
          style: const TextStyle(fontSize: 11)),
      trailing: TextButton(
        key: ValueKey('uag-pin-${g.id}'),
        onPressed: busy ? null : () => _pinAsManual(g),
        child: const Text('固定为手动组'),
      ),
    );
  }
}
