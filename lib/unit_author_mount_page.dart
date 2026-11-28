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
import 'author_file_picker.dart';
import 'http_json.dart';
import 'label_fallback.dart';
import 'load_error_view.dart';
import 'ui_copy.dart';
import 'unit_author_groups.dart';
import 'unit_library.dart';
import 'toast.dart';
import 'confirm_dialog.dart';
import 'basic_lib.dart' show BasicLib;
import 'loading_view.dart';
import 'api_timeout.dart';
import 'text_styles.dart';

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

  /// 单元库下**全部**作者目录（来自 `/api/unit/authors` 的 `items`）。
  ///
  /// 候选池只能是它：`cards` 只含「已形成组」的目录，没成组的独立目录不在里面，
  /// 用户就选不到「名字不同的另一个文件夹」——那正是挂载要解决的问题。
  List<AuthorGroupFile> allFiles = const <AuthorGroupFile>[];

  bool loading = true;
  bool busy = false;
  String? err;

  /// 挂载页「按基础库挂载」里勾选的基础库 id。
  ///
  /// owner 2026-11-28：不再按目录树勾，而是先选基础库、再建作者目录。
  final Set<String> _pickedBasics = <String>{};

  /// 注入的客户端优先；否则本页自建一个并在 dispose 关闭。
  http.Client? _ownClient;
  http.Client get _client => widget.client ?? (_ownClient ??= http.Client());

  /// 单元库标识：一律用 rel（服务端 `resolveUnit` 只认 rel 或 id 反查，
  /// rel 是最直接的一手标识；id 形式在两种 id 语义下可能对不上目录）。
  String get _unitRel => widget.unit.rel;

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
    setState(() {
      loading = true;
      err = null;
    });
    if (_unitRel.trim().isEmpty) {
      setState(() {
        loading = false;
        err = '媒体库没有可挂载的作者文件夹';
      });
      return;
    }
    try {
      final results = await Future.wait([
        _client
            .get(Uri.parse(unitAuthorGroupsUrl(widget.base, _unitRel)),
                headers: widget.headers)
            .timeout(kTimeoutRead),
        _client
            .get(Uri.parse(unitAuthorsUrl(widget.base, _unitRel)),
                headers: widget.headers)
            .timeout(kTimeoutRead),
        // 候选池：该单元库下**全部**作者目录（含没成组的）。
        // 失败不影响主流程：退回作者卡里的成员（旧行为）。
        _client
            .get(Uri.parse(unitAuthorsAllUrl(widget.base, _unitRel)),
                headers: widget.headers)
            .timeout(kTimeoutRead),
      ]);
      final g = jsonMapOf(results[0]);
      // 读接口收尾统一走 throwIfApiFailed：以前这里手拼
      // `'${g['error'] ?? 'HTTP n'}'`，error 是非字符串时会把 `{code: 500}`
      // 贴到界面上，g 不是 Map 时直接 NoSuchMethodError。
      // requireOk: false = 老契约（200 且无显式 ok:false 即成功），与本页
      // 第二个请求（作者卡）的判定一致。
      throwIfApiFailed(results[0].statusCode, g);
      // 作者卡失败不算整体失败：分组列表仍然可用（只是没有成员候选）。
      UnitAuthorCards c = const UnitAuthorCards();
      if (results[1].statusCode == 200) {
        final cj = jsonOf(results[1]);
        if (cj is Map && !serviceSaidFail(cj)) c = UnitAuthorCards.fromJson(cj);
      }
      // 候选池：优先用「全部目录」接口；拿不到时退回作者卡成员。
      var pool = const <AuthorGroupFile>[];
      if (results[2].statusCode == 200) {
        pool = authorGroupFilesFromItems(jsonOf(results[2]));
      }
      if (!mounted) return;
      setState(() {
        state = UnitAuthorGroupsState.fromJson(g);
        cards = c;
        allFiles = pool.isNotEmpty ? pool : _filesFromCards(c);
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

  /// 作者卡里的成员（旧候选池；只在「全部目录」接口不可用时兜底）。
  static List<AuthorGroupFile> _filesFromCards(UnitAuthorCards c) {
    final seen = <String>{};
    final out = <AuthorGroupFile>[];
    for (final card in c.cards) {
      for (final f in card.files) {
        if (seen.add(f.key)) out.add(f);
      }
    }
    return out;
  }

  /// 所有「还没被任何手动组占用」的成员。
  List<AuthorGroupFile> get _available {
    final claimed = state.claimedKeys;
    final out = <AuthorGroupFile>[];
    for (final f in allFiles) {
      if (claimed.contains(f.key)) continue;
      out.add(f);
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

  /// 基础库 id → 显示名（分支标题）。
  ///
  /// 只在本单元库的基础库表里找；找不到就回落 id——分支标题是导航信息，
  /// 宁可显示 id 也不要显示空标题。
  ///
  /// 0.9.352：回落判定收进 `libLabelOf`，与作者页那份面板、`displayLib` 同一条；
  /// 此前这里只查 `unit.allBasics` 且自写 `trim().isEmpty`，而 `LibNode` 树上的
  /// 同名库在另一页走的是 `items[].libName`，两页对「这个库叫什么」各答一次。
  String _libLabelOf(String lib) {
    for (final b in widget.unit.allBasics) {
      if (b.id == lib) return libLabelOf(b.id, b.name);
    }
    return lib;
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
      // requireOk:false = 老契约（200 且无显式 ok:false 即成功）。
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

  /// 按勾选的基础库建作者目录（已存在的直接用）。
  ///
  /// owner 2026-11-28：「选择后在对应基础库下创建作者文件夹，若已经存在则直接使用」。
  /// 只调 `POST /api/unit/authors/create`（幂等：已存在返回 409）；不删不改任何已有文件。
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
      final bodies = createAuthorBodies(authorDir: dir, libs: _pickedBasics);
      for (final body in bodies) {
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
        authorCreateSummary(
            made: made, existed: existed, failed: failed.length),
        bad: failed.isNotEmpty);
    if (made > 0 || existed > 0) await load();
  }

  void _toast(String msg, {bool bad = false}) =>
      showToast(this, msg, bad: bad);

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
      floatingActionButton: loading || err != null
          ? null
          : Column(mainAxisSize: MainAxisSize.min, children: [
              FloatingActionButton.extended(
                key: const ValueKey('uag-create-dirs'),
                heroTag: 'uag-create',
                onPressed: (busy || _pickedBasics.isEmpty)
                    ? null
                    : _createAuthorDirs,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: Text(
                    '建作者目录 ${_pickedBasics.isEmpty ? '' : '(${_pickedBasics.length})'}'),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.extended(
                heroTag: 'uag-merge',
                onPressed: busy ? null : _openMerge,
                icon: const Icon(Icons.merge_type),
                label: const Text('合并作者'),
              ),
            ]),
      body: _body(),
    );
  }

  Widget _body() {
    if (loading) return const LoadingView();
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
        // owner 2026-11-28：挂载不再按目录树，而按**基础库**选。
        // 先列出直属上级单元库下的全部基础库，让用户选「哪些基础库有他的作品」。
        _sectionTitle('按基础库挂载 ${_scopeBasics.length}'),
        if (_scopeBasics.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text('这个单元库下没有可选的基础库。',
                style: kHintTextStyle),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
                '勾选哪些基础库有该作者的目录；勾完点右下角「建作者目录」，'
                '已存在的目录会直接使用。同名目录默认为同一作者，可手动拆分。',
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
        ],
        _sectionTitle('已挂载的手动组 ${manual.length}'),
        if (manual.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text('还没有手动合并的作者组。点右下角「合并作者」把同名作者并到一组。',
                style: kHintTextStyle),
          ),
        for (final g in manual) _groupTile(g),
        const Divider(height: 24),
        _sectionTitle('可自动合并 ${auto.length}'),
        if (auto.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text('当前单元库内没有同名作者。',
                style: kHintTextStyle),
          ),
        for (final g in auto) _autoTile(g),
      ],
    );
  }

  /// 直属上级单元库下的全部基础库（作品不得跨出这个范围）。
  List<BasicLib> get _scopeBasics => basicsOfUnitScope(widget.unit.allBasics);

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _groupTile(UnitAuthorGroup g) {
    final files = g.files;
    return ListTile(
      key: ValueKey('uag-group-${g.id}'),
      title: Text(g.name.isEmpty ? '未命名组' : g.name,
          overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 副标题走 authorMergeSummary（唯一出口）：且此前「已拆」是
          // 标题行上的一个小标签、摘要函数里却写在副标题——同一条事实两套文案。
          Text(g.summary, style: const TextStyle(fontSize: 11)),
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
      subtitle: Text(g.summary, style: const TextStyle(fontSize: 11)),
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
                    style: kHintTextStyle),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  // owner 2026-11-27：候选按基础库分叉展开（树枝），
                  // 不再把几十个库几百个目录平铺成一列。
                  child: AuthorFilePicker(
                    leafKeyPrefix: 'uag-pick',
                    files: available,
                    picked: picked,
                    labelOf: _libLabelOf,
                    subtitleOf: (f) => _labelOf(f) == f.authorDir ? '' : _labelOf(f),
                    onToggle: (f, on) => setD(() {
                      if (on) {
                        picked.add(f.key);
                      } else {
                        picked.remove(f.key);
                      }
                    }),
                    onToggleBranch: (branch, on) => setD(() {
                      for (final f in branch) {
                        if (on) {
                          picked.add(f.key);
                        } else {
                          picked.remove(f.key);
                        }
                      }
                    }),
                  ),
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
                    style: kHintTextStyle),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: AuthorFilePicker(
                    leafKeyPrefix: 'uag-split',
                    files: g.files,
                    picked: picked,
                    labelOf: _libLabelOf,
                    onToggle: (f, on) => setD(() {
                      if (on) {
                        picked.add(f.key);
                      } else {
                        picked.remove(f.key);
                      }
                    }),
                    onToggleBranch: (branch, on) => setD(() {
                      for (final f in branch) {
                        if (on) {
                          picked.add(f.key);
                        } else {
                          picked.remove(f.key);
                        }
                      }
                    }),
                  ),
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
      groupFiles: g.files,
    );
    // 前置校验只有 req.error 一个入口（原组成员已挂在请求上，
    // 不再绕过它直接调底层函数——那正是「同一条规则两个入口」的来源）。
    final bad = req.error;
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
                    style: kHintTextStyle),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: AuthorFilePicker(
                    leafKeyPrefix: 'uag-setfiles',
                    files: pool,
                    picked: picked,
                    labelOf: _libLabelOf,
                    onToggle: (f, on) => setD(() {
                      if (on) {
                        picked.add(f.key);
                      } else {
                        picked.remove(f.key);
                      }
                    }),
                    onToggleBranch: (branch, on) => setD(() {
                      for (final f in branch) {
                        if (on) {
                          picked.add(f.key);
                        } else {
                          picked.remove(f.key);
                        }
                      }
                    }),
                  ),
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
    final ok = await confirmAction(
      context,
      title: '删除作者组',
      message: '删除「${g.name.isEmpty ? '未命名组' : g.name}」？'
          '只删分组记录，不动任何作者目录与作品文件。',
      confirmLabel: '删除',
      // 这个确认键的 key 已被外部测试/自动化引用，通过参数保留。
      confirmKey: const ValueKey('uag-delete-ok'),
    );
    if (!ok) return;
    await _send(UnitAuthorRequest(
      unit: _unitRel,
      action: UnitAuthorAction.delete,
      groupId: g.id,
    ));
  }

}
