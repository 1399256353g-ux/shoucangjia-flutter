/// 作者页的「作者挂载」面板：**按基础库**，没有目录树。
///
/// owner 2026-11-28（第三次提同一件事）：
/// > 「差分合并点了没用，分开的还是分开，旧逻辑和新的还是一起混在一起」
///
/// 旧实现有三个致命问题，全在本文件里：
///  1. 渲染的数据是 `/api/author/mounts` 的 `items`——**逐个目录**的平铺列表；
///     合并只会写一个 group 记录，`items` 永远不变，所以「点了没用」。
///  2. 合并 / 拆出 / 编辑成员三套对话框并存，都要用户理解「文件夹」这一层。
///  3. 目录树勾选控件在这里也有第四份拷贝（0.9.374 起整套删除，只剩
///     按基础库勾选）。
///
/// 现在只按**基础库**说话：
///  - 已合并 → 一张卡显示「N 个基础库」，可拆出某几个库；
///  - 未合并 → 列出这些库，点「合并成一个作者」。
///
/// 合并结果从 `/api/unit/authors.json?unit=` 读（那是唯一会变的地方）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_timeout.dart';
import 'count_label.dart';
import 'error_text.dart';
import 'http_error_text.dart';
import 'http_json.dart';
import 'json_num.dart';
import 'label_fallback.dart';
import 'loading_view.dart';
import 'rel_path.dart' show lastRelName;
import 'text_styles.dart';
import 'toast.dart';
import 'ui_copy.dart';
import 'confirm_dialog.dart';
import 'split_libs_dialog.dart';
import 'unit_author_groups.dart';

/// 一个单元库里「这位作者」的合并卡。
class _UnitCard {
  final String unit;
  final String groupId;
  final String name;
  final List<AuthorGroupFile> files;
  final bool auto;
  final int works;

  const _UnitCard({
    required this.unit,
    required this.groupId,
    required this.name,
    required this.files,
    this.auto = false,
    this.works = 0,
  });

  /// 卡里出现的不同基础库（保持出现顺序）。
  List<String> get libs {
    final seen = <String>{};
    final out = <String>[];
    for (final f in files) {
      if (seen.add(f.lib)) out.add(f.lib);
    }
    return out;
  }
}

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

  /// 单元库 rel → 该作者在那里的合并卡（没有则为 null：说明目录还没归组）。
  Map<String, _UnitCard?> cards = <String, _UnitCard?>{};

  bool loading = true;
  bool busy = false;
  String? err;

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
          .get(Uri.parse(authorMountsUrl(widget.base, widget.authorName)),
              headers: widget.headers)
          .timeout(kTimeoutRead);
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      final m = AuthorMounts.fromJson(jsonOf(r));
      // 合并结果只体现在 `/api/unit/authors.json`：逐单元取一次。
      final found = <String, _UnitCard?>{};
      for (final unit in m.units) {
        found[unit] = await _cardOf(unit, m);
      }
      if (!mounted) return;
      setState(() {
        mounts = m;
        cards = found;
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

  /// 从单元库的合并卡里找出「这位作者」的那一张。
  ///
  /// 判定用 `lib|authorDir` 集合相交：作者改名后目录名可能和显示名不同，
  /// 名字比对会漏；目录身份才是稳定的。
  Future<_UnitCard?> _cardOf(String unit, AuthorMounts m) async {
    final mine = <String>{
      for (final i in m.items)
        if (i.unitRel == unit) '${i.lib}|${i.authorDir}',
    };
    if (mine.isEmpty) return null;
    try {
      final ur = await _client
          .get(Uri.parse(unitAuthorsUrl(widget.base, unit)),
              headers: widget.headers)
          .timeout(kTimeoutRead);
      if (ur.statusCode != 200) return null;
      final raw = jsonOf(ur);
      if (raw is! Map) return null;
      final list = raw['cards'];
      if (list is! List) return null;
      for (final c in list) {
        if (c is! Map) continue;
        final fs = c['files'];
        if (fs is! List) continue;
        final files = <AuthorGroupFile>[];
        var hit = false;
        for (final f in fs) {
          final g = AuthorGroupFile.fromJson(f);
          if (g == null) continue;
          files.add(g);
          if (mine.contains(g.key)) hit = true;
        }
        if (!hit) continue;
        return _UnitCard(
          unit: unit,
          groupId: '${c['groupId'] ?? ''}'.trim(),
          name: '${c['name'] ?? ''}'.trim(),
          files: files,
          auto: boolOf(c['auto']),
          works: intOf(c['works']),
        );
      }
    } catch (_) {}
    return null;
  }

  String _libLabelOf(String lib) {
    for (final i in mounts.items) {
      if (i.lib == lib) return libLabelOf(i.lib, i.libName);
    }
    return lib;
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

  /// 把该单元库里的这几处合并成一位作者。
  ///
  /// 服务端 `merge` 需要一个**落盘的组**；合并后 `/api/unit/authors.json`
  /// 才会显示成一张卡——所以这里合并完必须重新 load。
  Future<void> _mergeUnit(String unit) async {
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

  /// 拆出：选出要**分出去**的基础库。
  ///
  /// 一个作者在一个基础库里只有一个目录，所以按基础库勾与按目录勾等价。
  /// 自动合并的卡没有落盘组，先 `merge` 固定成组再 `split`。
  Future<void> _splitCard(_UnitCard c) async {
    final libs = c.libs;
    if (libs.length < 2) {
      _toast('这个作者只有一个基础库，无需拆分', bad: true);
      return;
    }
    final picked = await pickLibsToSplit(
      context,
      libs: libs,
      labelOf: _libLabelOf,
      keyPrefix: 'ams',
    );
    if (picked == null || !mounted) return;

    // 服务端 split 的语义：`files` 是要搬进新组的那一份，原组留其余。
    final moveOut = <AuthorGroupFile>[
      for (final f in c.files)
        if (picked.contains(f.lib)) f,
    ];
    final keep = <AuthorGroupFile>[
      for (final f in c.files)
        if (!picked.contains(f.lib)) f,
    ];
    if (moveOut.isEmpty || keep.isEmpty) return;

    // 还没落盘的手动组（自动合并 / 无 groupId）：先 merge 出一个真组。
    if (c.groupId.isEmpty || c.auto) {
      final before = c.groupId;
      await _send(
        UnitAuthorRequest(
          unit: c.unit,
          action: UnitAuthorAction.merge,
          name: c.name.isEmpty ? widget.authorName : c.name,
          files: c.files,
        ),
        c.unit,
      );
      if (!mounted) return;
      // merge 建的是新组：重新读一次拿到它的 id，再拆分。
      final fresh = cards[c.unit];
      final gid = (fresh != null && fresh.groupId.isNotEmpty)
          ? fresh.groupId
          : before;
      if (gid.isEmpty) {
        _toast('合并后没有拿到组标识，请重新打开面板再拆', bad: true);
        return;
      }
      // 用新组成员重新拆：搬走 moveOut，其余留原组。
      await _send(
        UnitAuthorRequest(
          unit: c.unit,
          action: UnitAuthorAction.split,
          groupId: gid,
          name: widget.authorName,
          files: moveOut,
          groupFiles: c.files,
        ),
        c.unit,
      );
      return;
    }

    final req = UnitAuthorRequest(
      unit: c.unit,
      action: UnitAuthorAction.split,
      groupId: c.groupId,
      name: widget.authorName,
      files: moveOut,
      groupFiles: c.files,
    );
    final bad = req.error;
    if (bad != null) {
      _toast(bad, bad: true);
      return;
    }
    await _send(req, c.unit);
  }

  Future<void> _dissolve(_UnitCard c) async {
    if (c.groupId.isEmpty) {
      _toast('这个作者还没合并成分组，无需解散', bad: true);
      return;
    }
    // 纯文本确认框走 `confirmAction`（唯一实现）：这个文件此前自己拼了一份，
    // 与另外十几处只差按钮颜色与「取消在左」的约定靠手抄。
    final ok = await confirmAction(
      context,
      title: '解散合并',
      message: '把「${c.name.isEmpty ? widget.authorName : c.name}」'
          '在 ${c.libs.length} 个基础库的目录拆回各自独立？'
          '只删分组记录，不动任何作者目录与作品文件。',
      confirmLabel: '解散',
      confirmKey: const ValueKey('ams-dissolve-ok'),
    );
    if (!ok) return;
    await _send(
      UnitAuthorRequest(
        unit: c.unit,
        action: UnitAuthorAction.delete,
        groupId: c.groupId,
      ),
      c.unit,
    );
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
              const Text(kAuthorMountTitle,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (busy)
                const SizedBox(width: 16, height: 16, child: InlineSpinner()),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '同一单元库里同名的作者目录默认就是同一位作者。这里按基础库列出他的分布：'
              '要分开某几个库，点「拆出」；要合回去，点「合并」。',
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
      return const Padding(padding: EdgeInsets.all(28), child: LoadingView());
    }
    if (err != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(err!, textAlign: TextAlign.center, style: kHintTextStyle),
          const SizedBox(height: 12),
          FilledButton(onPressed: load, child: const Text('重试')),
        ]),
      );
    }
    if (mounts.items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('没有找到这个作者的目录',
            textAlign: TextAlign.center, style: kHintTextStyle),
      );
    }

    final units = mounts.units;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            '共 ${mounts.libCount} 个基础库 · ${mounts.dirCount} 个文件夹'
            '${mounts.sameUnitOnly ? ' · 同一单元库内' : ' · 跨 ${units.length} 个单元库'}',
            style: const TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        ),
        for (final u in units) _unitSection(u, cs),
      ],
    );
  }

  Widget _unitSection(String unit, ColorScheme cs) {
    final items = [for (final i in mounts.items) if (i.unitRel == unit) i];
    final libs = <String>[];
    for (final i in items) {
      if (!libs.contains(i.lib)) libs.add(i.lib);
    }
    final card = cards[unit];
    // 「已合并」= 这张卡里包含 ≥2 个基础库。单库没有可合并的东西。
    final merged = card != null && card.libs.length >= 2;
    // 未合并但分布在多个基础库：可以合并。
    final splittable = libs.length >= 2;
    final unitLabel = unit.isEmpty ? '无归属' : lastRelName(unit);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.layers_outlined, size: 15, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(unitLabel.isEmpty ? unit : unitLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (merged ? cs.primary : Colors.grey).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(merged ? '已合并' : '分开 ${libs.length} 处',
                  style: TextStyle(
                      fontSize: 10,
                      color: merged ? cs.primary : Colors.grey)),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final lib in (merged ? card.libs : libs))
              Chip(
                label: Text(_libLabelOf(lib),
                    style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ]),
          if (card != null && card.files.length > (merged ? 0 : 1))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${card.files.length} 个目录 · '
                '${card.name.isEmpty ? widget.authorName : card.name}'
                '${card.works > 0 ? ' · ${formatCount(card.works)} 作品' : ''}',
                style: const TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
            ),
          if (splittable) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 4, children: [
              if (!merged)
                FilledButton.tonalIcon(
                  key: ValueKey('ams-merge-$unit'),
                  onPressed: busy ? null : () => _mergeUnit(unit),
                  icon: const Icon(Icons.merge_type, size: 16),
                  label: Text('合并这 ${libs.length} 处'),
                )
              else ...[
                TextButton.icon(
                  key: ValueKey('ams-split-$unit'),
                  onPressed: busy ? null : () => _splitCard(card),
                  icon: const Icon(Icons.call_split, size: 16),
                  label: const Text('拆出'),
                ),
                TextButton.icon(
                  key: ValueKey('ams-dissolve-$unit'),
                  onPressed: busy ? null : () => _dissolve(card),
                  icon: const Icon(Icons.link_off, size: 16),
                  label: const Text('解散'),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}
