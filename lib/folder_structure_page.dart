import 'dart:convert';
import 'json_num.dart';
import 'count_label.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'http_json.dart';
import 'http_error_text.dart';

import 'home_action.dart';
import 'rel_path.dart';
import 'top_node.dart';
import 'error_text.dart';
import 'load_error_view.dart';

/// 文件结构列表：把库里所有文件夹平铺成可折叠的树，
/// 供 owner 指定「节点文件夹」（单元库）。
/// 术语：本页（结构设置）是唯一使用「顶级单元库」的地方，它指一个媒体库的根节点，
/// 名称取该库根目录名；界面其它位置一律称「媒体库」。
///
/// 数据：`GET /api/folders` → { root, top:{name,rel}, folders:[{rel,name,depth,authors,isNode,dirs}] }
/// 保存：`POST /api/nodes` body {nodes:[rel,...]}
///
/// 页面按**服务器**工作：节点文件夹是每台服务器自己的 `nodes.json`。
/// 0.9.327 之前本页只接受一份 `urlOf/headersOf`，两个调用点都写死「首条
/// 连接」/「当前库的连接」——多连接时 owner 只能给其中一台勾节点文件夹，
/// 第二台的节点永远设不了（首页却照常把它那台的卡片画出来）。
/// 现在传入 [sources] 全部连接，页内按连接切换，保存写回**当前那台**。
class FolderSource {
  final String id;
  final String label;
  final String base;
  final Map<String, String> Function() headersOf;

  const FolderSource({
    required this.id,
    required this.label,
    required this.base,
    required this.headersOf,
  });

  Uri urlOf(String path) => Uri.parse('$base$path');

  /// 切换菜单里的名称：没填名称就用地址（这里**要**地址，否则无法区分两台）。
  String get title => label.trim().isEmpty ? base : label.trim();
}

class FolderStructurePage extends StatefulWidget {
  /// 可切换的服务器；第一项是打开页面时的那一台。
  final List<FolderSource> sources;

  /// 保存成功后的回调（参数是刚写进服务器的那份节点列表）。
  final Future<void> Function(List<String> nodes)? onSaved;

  /// 可注入的 HTTP 客户端（测试用）。不传时页面自己建一个并在销毁时关闭
  /// ——与周边五个项目页同一口径，不再每次请求新建。
  final http.Client? client;

  const FolderStructurePage({
    super.key,
    required this.sources,
    this.onSaved,
    this.client,
  }) : assert(sources.length > 0, '至少要有一条连接');

  @override
  State<FolderStructurePage> createState() => _FolderStructurePageState();
}

class _FolderRow {
  final String rel;
  final String name;
  final int depth;
  final int authors;
  final List<_FolderRow> children;

  /// 基础库目录：永远不允许勾选为「节点文件夹」（单元库）。
  final bool isBasic;

  /// 服务端注册表（`/api/libraries.json` 的 `basicLibraries`）或接口显式字段
  /// 明确认定为基础库。只有它为 true 时才「硬锁」；
  /// 仅凭「@作者」目录推断的（改造后残留子目录）可自动解锁。
  final bool listed;

  _FolderRow({
    required this.rel,
    required this.name,
    required this.depth,
    required this.authors,
    required this.children,
    this.isBasic = false,
    this.listed = false,
  });
}

/// 是否锁死「不能设为节点文件夹」。
///
/// - `listed`：服务端注册表/接口显式标记为基础库 → 锁（除非手动解锁）；
/// - 仅靠「@作者」子目录推断、且注册表已能正常读到（[basicsKnown]）却不含它
///   → 认为该目录已被改成单元库、只是残留作者目录，自动解锁；
/// - 注册表读不到（[basicsKnown] 为 false）时保持保守：仍然锁。
bool basicLocked({
  required bool isBasic,
  required bool listed,
  required bool basicsKnown,
  required int authors,
  required bool unlocked,
}) {
  if (!isBasic) return false;
  if (unlocked) return false;
  // 已经没有作者＝不再具备基础库特征，直接解锁。
  if (authors <= 0) return false;
  if (listed) return true;
  return !basicsKnown;
}

class _FolderStructurePageState extends State<FolderStructurePage> {
  /// 当前正在编辑的那台服务器（见 [FolderSource]）。
  late int _active = 0;

  FolderSource get _src => widget.sources[_active];

  http.Client? _ownClient;

  http.Client get _client => widget.client ?? (_ownClient ??= http.Client());

  Uri _urlOf(String path) => _src.urlOf(path);

  Map<String, String> _headers() => _src.headersOf();

  String topName = '';
  String topRel = '';
  List<_FolderRow> rows = [];
  final Set<String> expanded = <String>{};
  final Set<String> nodes = <String>{};
  final Set<String> saved = <String>{};

  /// 基础库 rel 集合（来自 `/api/libraries.json` 的 `basicLibraries`）。
  Set<String> basicRels = <String>{};

  /// 上一步的注册表是否真的读到了（失败时不能据此解锁）。
  bool basicsKnown = false;

  /// 手动强制解锁的基础库目录（持久化）：允许把它们设为节点文件夹。
  final Set<String> unlocked = <String>{};
  static const String _unlockedKey = 'folder_unlocked_v1';
  bool loading = true;
  bool saving = false;
  String? err;

  /// 接口可能直接给出的「是否基础库」字段名。
  static const List<String> _basicFlagKeys = <String>[
    'basic',
    'isBasic',
    'is_basic',
    'isBasicLib',
    'is_basic_lib',
    'basicLib',
  ];

  /// 统一 rel：去掉首尾 `/`，压缩重复 `/`。
  ///
  /// 转调 [normalizeRelPath]（`rel_path.dart` 唯一实现）：这里原先自己写了一遍
  /// `replaceAll('\\','/').split('/')` 链，与 `unit_library.splitRel` /
  /// `category_tree.splitCatRel` / `diskNameOf` 是**第四份**同样规则的拷贝。
  static String normalizeRel(String rel) => normalizeRelPath(rel);

  /// 父链中是否有「@作者」这一级目录（接口未标记基础库时的兜底判断）。
  static bool hasAuthorMarkerInParents(String rel) {
    final parts = normalizeRel(rel).split('/');
    if (parts.length < 2) return false;
    for (var i = 0; i < parts.length - 1; i++) {
      final s = parts[i].trim();
      if (s.startsWith('@') && s.contains('作者')) return true;
    }
    return false;
  }

  static bool? _explicitBasicFlag(Map raw) {
    for (final k in _basicFlagKeys) {
      final v = boolOrNull(raw[k]);
      if (v != null) return v;
    }
    return null;
  }

  static bool _isBasicFolder(
    Map raw,
    String rel,
    int authors,
    Set<String> basics,
  ) {
    final explicit = _explicitBasicFlag(raw);
    if (explicit != null) return explicit;
    if (basics.contains(normalizeRel(rel))) return true;
    // 兜底：有作者且父链下存在「@作者」目录 → 视为基础库。
    if (authors > 0 && hasAuthorMarkerInParents(rel)) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadUnlocked();
    _load();
  }

  @override
  void dispose() {
    _ownClient?.close();
    super.dispose();
  }

  /// 切到另一台服务器：节点列表属于各自服务器的 `nodes.json`，所以三份
  /// 状态（节点勾选 / 已保存副本 / 展开状态）都先清掉再重新读。
  /// 有未保存改动时先确认——否则切换会静默丢掉刚勾的那几项。
  Future<void> _switchServer(int index) async {
    if (index == _active || loading || saving) return;
    if (!await _confirmDiscard('切换服务器')) return;
    if (!mounted) return;
    setState(() {
      _active = index;
      nodes.clear();
      saved.clear();
      expanded.clear();
      basicRels = <String>{};
      basicsKnown = false;
      rows = const [];
      topName = '';
      topRel = '';
    });
    await _load();
  }

  Future<void> _loadUnlocked() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(_unlockedKey) ?? const <String>[];
      if (!mounted) return;
      setState(() => unlocked
        ..clear()
        ..addAll(list.map(normalizeRel).where((e) => e.isNotEmpty)));
    } catch (_) {}
  }

  Future<void> _saveUnlocked() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_unlockedKey, unlocked.toList());
    } catch (_) {}
  }

  /// 有效「基础库锁定」：目录仍具基础库特征（有作者）且未被手动解锁。
  /// 已经没有作者、或注册表里已不再登记它（改成单元库后只剩 @作者 残留）
  /// 的目录自动解锁。
  bool _lockedBasic(_FolderRow r) => basicLocked(
        isBasic: r.isBasic,
        listed: r.listed,
        basicsKnown: basicsKnown,
        authors: r.authors,
        unlocked: unlocked.contains(normalizeRel(r.rel)),
      );

  void _forceUnlock(_FolderRow r) {
    final n = normalizeRel(r.rel);
    setState(() => unlocked.add(n));
    _saveUnlocked();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已解锁「${r.name}」，可设为节点文件夹')));
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      final rs = await Future.wait<Object?>([
        _client
            .get(_urlOf('/api/folders'), headers: _headers())
            .timeout(const Duration(seconds: 20)),
        _fetchBasicRels().then<Object?>((v) => v),
      ]);
      final r = rs[0] as http.Response;
      final basics = rs[1] as Set<String>?;
      final known = basics ?? const <String>{};
      if (r.statusCode != 200) throw httpErrorText(r.statusCode);
      final j = jsonOf(r);
      final top = j['top'];
      // owner 2026-11-22：名称来自服务端（库根目录名），不写死 SECRET。
      // 服务端没给 top 时才用刚刚落盘的库根名，仍为空才回落到常量。
      final served = '${top is Map ? (top['name'] ?? '') : ''}'.trim();
      if (served.isNotEmpty) {
        TopNodeName.set(served);
      } else {
        TopNodeName.setFromRoot('${j['root'] ?? ''}');
      }
      topName = TopNodeName.current;
      topRel = '${top is Map ? (top['rel'] ?? '') : ''}';
      final serverNodes =
          [for (final e in listOf(j['nodes'])) '$e'];
      nodes
        ..clear()
        ..addAll(serverNodes);
      saved
        ..clear()
        ..addAll(serverNodes);
      basicRels = known.toSet();
      basicsKnown = basics != null;
      rows = _parse(listOf(j['folders']), known);
      // 基础库永远不能是节点：按「实时基础库特征」清掉历史误选（保留 saved 原值）。
      nodes.removeWhere((e) => _isBasicRel(e));
      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        err = errorText(e);
      });
    }
  }

  /// 读取 `/api/libraries.json` 的基础库 rel 集合；失败不影响主流程。
  /// 失败返回 `null`（与「读到了但一个都没有」区分）：只有真读到注册表时，
  /// 才能据此判断某个目录「已经不是基础库了」。
  Future<Set<String>?> _fetchBasicRels() async {
    try {
      final r = await _client
          .get(_urlOf('/api/libraries.json'), headers: _headers())
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      final j = jsonOf(r);
      if (j is! Map) return null;
      final raw = j['basicLibraries'];
      if (raw is! List) return null;
      final out = <String>{};
      for (final e in raw) {
        if (e is! Map) continue;
        final rel = normalizeRel('${e['rel'] ?? ''}');
        if (rel.isNotEmpty) out.add(rel);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  List<_FolderRow> _parse(List list, Set<String> basics) {
    final out = <_FolderRow>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final rel = '${raw['rel'] ?? ''}'.trim();
      if (rel.isEmpty) continue;
      final authors =
          intOf(raw['authors']);
      out.add(_FolderRow(
        rel: rel,
        name: '${raw['name'] ?? rel}'.trim(),
        depth: raw['depth'] == null ? 1 : intOf(raw['depth'], 1),
        authors: authors,
        children: _parse(listOf(raw['dirs']), basics),
        isBasic: _isBasicFolder(raw, rel, authors, basics),
        listed: _explicitBasicFlag(raw) == true ||
            basics.contains(normalizeRel(rel)),
      ));
    }
    return out;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      // 双保险：基础库目录永远不进 nodes。
      nodes.removeWhere((e) => _isBasicRel(e));
      final r = await _client
          .post(
            _urlOf('/api/nodes'),
            headers: {
              ..._headers(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'nodes': nodes.toList()}),
          )
          .timeout(const Duration(seconds: 20));
      final j = r.statusCode == 200 ? jsonOf(r) : null;
      final bad = apiFailureText(r.statusCode, j);
      if (bad != null) throw bad;
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
          .showSnackBar(SnackBar(content: Text(failureLine('保存', errorText(e)))));
    }
  }

  bool get dirty =>
      nodes.length != saved.length || !nodes.every(saved.contains);

  /// 有未保存改动时，离开页面或刷新会丢掉这些改动：先向 owner 确认。
  Future<bool> _confirmDiscard(String action) async {
    if (!dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('还有未保存的改动'),
        content: Text('$action会丢弃当前未保存的节点设置，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃改动'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 刷新前先确认：避免把未保存的勾选一并刷掉。
  Future<void> _refresh() async {
    if (loading || saving) return;
    if (!await _confirmDiscard('刷新')) return;
    if (!mounted) return;
    await _load();
  }

  void _toggleExpand(String rel) {
    setState(() {
      if (!expanded.remove(rel)) expanded.add(rel);
    });
  }

  void _toggleNode(String rel) {
    if (_isBasicRel(rel)) return;
    setState(() {
      if (!nodes.remove(rel)) nodes.add(rel);
    });
  }

  bool _isBasicRel(String rel) {
    final n = normalizeRel(rel);
    // 行存在（本树里）就以「实时基础库特征」为准：作者>0 且未解锁才算基础库。
    // 用户已把目录改成符合单元库（无 @作者/无作者）后，即使 libraries.json
    // 里还残留它的 rel，也不再锁定，避免「永远无法设为节点」。
    final row = _findRow(rows, rel);
    if (row != null) return _lockedBasic(row);
    // 行不存在（例如被截断/嵌套过深）才回落到注册表 rel 集合。
    return basicRels.contains(n) && !unlocked.contains(n);
  }

  _FolderRow? _findRow(List<_FolderRow> list, String rel) {
    for (final r in list) {
      if (r.rel == rel) return r;
      final hit = _findRow(r.children, rel);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 当前树里所有可设为节点的目录：非叶子（有下级）且不是基础库。
  List<String> get _nodeCandidates {
    final out = <String>[];
    void walk(List<_FolderRow> list) {
      for (final r in list) {
        if (!_lockedBasic(r) && r.children.isNotEmpty) out.add(r.rel);
        walk(r.children);
      }
    }

    walk(rows);
    return out;
  }

  /// 一键把所有非基础库文件夹设为节点，并剔除基础库。
  void _setAllNonBasicAsNodes() {
    final candidates = _nodeCandidates;
    final basicsInNodes = nodes.where((e) => _isBasicRel(e)).toList();
    if (candidates.isEmpty && basicsInNodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可设为节点的文件夹')),
      );
      return;
    }
    final before = nodes.length;
    setState(() {
      nodes.removeWhere((e) => _isBasicRel(e));
      nodes.addAll(candidates);
    });
    final added = nodes.length - (before - basicsInNodes.length);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已选入 ${candidates.length} 个非基础库文件夹'
          '（新增 ${added > 0 ? added : 0}，共 ${nodes.length} 个节点），点「保存」生效'),
    ));
  }

  Future<void> _confirmUnlock(_FolderRow r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('解锁「${r.name}」？'),
        content: const Text('该目录当前被识别为基础库，锁定为不可设为节点。\n'
            '强制解锁后可以把它设为节点文件夹（单元库）；'
            '如果它确实还是基础库，建议不要这样做。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('解锁')),
        ],
      ),
    );
    if (ok == true && mounted) _forceUnlock(r);
  }

  Widget _buildRow(_FolderRow r) {
    final open = expanded.contains(r.rel);
    final isNode = nodes.contains(r.rel);
    final hasKids = r.children.isNotEmpty;
    final isBasic = _lockedBasic(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('folder-${r.rel}'),
          onTap: isBasic ? null : () => _toggleNode(r.rel),
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
                isBasic
                    ? Icons.inventory_2_outlined
                    : (isNode ? Icons.hub_outlined : Icons.folder_outlined),
                size: 17,
                color: isNode && !isBasic
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
                            fontWeight: isNode && !isBasic
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isBasic ? Colors.grey : null)),
                    if (r.authors > 0)
                      Text('${formatCount(r.authors)} 位作者',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              if (isBasic)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('基础库',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey)),
                )
              else if (isNode)
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
                      style:
                          TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              if (isBasic)
                IconButton(
                  key: ValueKey('node-unlock-${r.rel}'),
                  tooltip: '强制解锁（允许设为节点）',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.lock_open, size: 17),
                  onPressed: () => _confirmUnlock(r),
                ),
              Switch(
                key: ValueKey('node-switch-${r.rel}'),
                value: isNode && !isBasic,
                onChanged: isBasic ? null : (_) => _toggleNode(r.rel),
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
    return PopScope(
      canPop: !dirty || saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!await _confirmDiscard('返回')) return;
        if (!mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: widget.sources.length <= 1
              ? const Text('文件结构')
              : _ServerPicker(
                  sources: widget.sources,
                  active: _active,
                  onPick: _switchServer,
                ),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
            const HomeAction(),
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
                ? LoadErrorView.loadFailed(err!)
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
                            child: Text('顶级单元库：$topName',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          Text('已选 ${nodes.length} 个节点',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ]),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                            '点目录行或右侧开关，把目录设为「节点文件夹」（单元库）。'
                            '顶级单元库＝该媒体库的根节点（每个库各有一个），名称取它的根目录名；'
                            '接入多个媒体库时，每个库各有自己的顶级单元库。'
                            '「基础库」目录固定排除，不能设为节点。',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Row(children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              key: const ValueKey('bulk-set-nodes'),
                              onPressed: (loading || saving || rows.isEmpty)
                                  ? null
                                  : _setAllNonBasicAsNodes,
                              icon: const Icon(Icons.account_tree_outlined,
                                  size: 16),
                              label: const Text('一键把所有非基础库文件夹设为节点',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          if (basicRels.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text('基础库 ${basicRels.length} 个',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ]),
                      ),
                      for (final r in rows) _buildRow(r),
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('该库下没有子文件夹',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                    ],
                  ),
      ),
    );
  }
}

/// 标题位置的服务器切换器：多连接时点开列出全部连接。
///
/// 单连接时调用方直接显示「文件结构」（见 `build`），避免给只有一个库的人
/// 多一个没有第二项的菜单。
class _ServerPicker extends StatelessWidget {
  final List<FolderSource> sources;
  final int active;
  final Future<void> Function(int index) onPick;

  const _ServerPicker({
    required this.sources,
    required this.active,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cur = sources[active];
    return PopupMenuButton<int>(
      key: const ValueKey('folder-server-picker'),
      tooltip: '选择要设置节点文件夹的服务器',
      onSelected: (i) => onPick(i),
      itemBuilder: (_) => [
        for (var i = 0; i < sources.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(children: [
              Icon(i == active ? Icons.check : Icons.dns_outlined,
                  size: 16,
                  color: i == active
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey),
              const SizedBox(width: 8),
              Flexible(
                child: Text(sources[i].title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text('文件结构 · ${cur.title}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const Icon(Icons.arrow_drop_down),
      ]),
    );
  }
}
