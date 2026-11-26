/// 作者文件夹多选器：按「基础库」分叉展开，叶子是作者目录。
///
/// owner 2026-11-27：「挂载页：单元库树枝分叉展开，用户自己选哪些叶子目录
/// 属于同一作者（不同名字也可以）」。
///
/// 此前三处勾选（合并 / 拆出 / 编辑成员）都是一条**平铺**的
/// `CheckboxListTile` 列表：一个单元库几十个基础库、几百个作者目录全排在一列，
/// 用户要找「某某库里的两个目录」只能一路滚。这里只改呈现结构——
/// 哪些成员算同一个作者仍由服务端与 [unitAuthorRequestError] 决定。
///
/// 分组规则（唯一实现，[authorFileBranches]）：
///  - 一级＝基础库（`AuthorGroupFile.lib`）；
///  - 叶子＝该基础库下的作者目录（`authorDir`）；
///  - 分支与叶子都走 [stableSort]：同名基础库/同名目录之间没有次序依据，
///    裸 sort 会让对话框每次打开顺序都不一样。
library;

import 'package:flutter/material.dart';

import 'stable_order.dart';
import 'unit_author_groups.dart';

/// 一个基础库分支：该库里可以勾选的作者目录。
class AuthorFileBranch {
  final String lib;

  /// 分支显示名（基础库名；调用方拿不到名称时回落到 lib）。
  final String label;
  final List<AuthorGroupFile> leaves;

  const AuthorFileBranch({
    required this.lib,
    required this.label,
    required this.leaves,
  });
}

/// 把候选成员按基础库分组。
///
/// [labelOf] 由调用方注入（面板用作者卡里的基础库名，作者主页用挂载项里的
/// `libName`）；本函数不猜名称，只负责分组与排序。
List<AuthorFileBranch> authorFileBranches(
  Iterable<AuthorGroupFile> files, {
  String Function(String lib)? labelOf,
}) {
  final byLib = <String, List<AuthorGroupFile>>{};
  for (final f in files) {
    final lib = f.lib.trim();
    if (lib.isEmpty || f.authorDir.trim().isEmpty) continue;
    byLib.putIfAbsent(lib, () => <AuthorGroupFile>[]).add(f);
  }
  final out = <AuthorFileBranch>[];
  for (final e in byLib.entries) {
    final raw = labelOf?.call(e.key) ?? '';
    final label = raw.trim().isEmpty ? e.key : raw.trim();
    // 同一目录被重复传进来时只留一份（服务端 sanitizeGroupFiles 也去重）。
    final seen = <String>{};
    final leaves = <AuthorGroupFile>[
      for (final f in e.value)
        if (seen.add(f.key)) f
    ];
    stableSort(leaves, (a, b) => a.authorDir.compareTo(b.authorDir));
    out.add(AuthorFileBranch(lib: e.key, label: label, leaves: leaves));
  }
  // 分支顺序：名称升序，同名再按 lib 升序（完全确定）。
  return stableSort(out, (a, b) {
    final c = a.label.compareTo(b.label);
    return c != 0 ? c : a.lib.compareTo(b.lib);
  });
}

/// 按基础库分叉展开的多选列表。
///
/// 交互：
///  - 分支默认展开（候选通常只有十几个，折叠起来反而多一步）；
///  - 分支行尾部有「全选 / 全不选」，只作用于本分支；
///  - 叶子行显示目录名（`authorDir`），副标题是来源说明（可传空）。
///
/// 勾选状态由 [picked]（成员键集合）持有，本控件不自己存状态——
/// 三个对话框都要在关闭时把结果读回去，状态留在调用方只有一份。
class AuthorFilePicker extends StatelessWidget {
  final List<AuthorGroupFile> files;

  /// 已勾选的成员键（[AuthorGroupFile.key]）。
  final Set<String> picked;

  /// 勾选变化回调（参数是被点击的那个成员）。
  final void Function(AuthorGroupFile f, bool on) onToggle;

  /// 整分支全选/全不选。
  final void Function(List<AuthorGroupFile> branch, bool on) onToggleBranch;

  /// 基础库显示名；为空时用 lib。
  final String Function(String lib)? labelOf;

  /// 叶子的副标题（例如「已在组内」）。为空则不显示。
  final String Function(AuthorGroupFile f)? subtitleOf;

  /// 叶子行的 Key 前缀（三个对话框各用一套，避免互相命中）。
  ///
  /// 叶子的键是 `<前缀>-<成员键>`（与改造前的 `uag-pick-…` / `uag-split-…` /
  /// `uag-setfiles-…` 逐字相同），分支键在同一前缀上加 `-branch-`。
  final String leafKeyPrefix;

  const AuthorFilePicker({
    super.key,
    required this.files,
    required this.picked,
    required this.onToggle,
    required this.onToggleBranch,
    this.labelOf,
    this.subtitleOf,
    this.leafKeyPrefix = 'afp-pick',
  });

  @override
  Widget build(BuildContext context) {
    final branches = authorFileBranches(files, labelOf: labelOf);
    if (branches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('没有可选的作者文件夹', style: TextStyle(fontSize: 12)),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final b in branches)
        _BranchTile(
          branch: b,
          picked: picked,
          onToggle: onToggle,
          onToggleBranch: onToggleBranch,
          subtitleOf: subtitleOf,
          leafKeyPrefix: leafKeyPrefix,
          cs: cs,
        ),
    ]);
  }
}

class _BranchTile extends StatelessWidget {
  final AuthorFileBranch branch;
  final Set<String> picked;
  final void Function(AuthorGroupFile f, bool on) onToggle;
  final void Function(List<AuthorGroupFile> branch, bool on) onToggleBranch;
  final String Function(AuthorGroupFile f)? subtitleOf;
  final String leafKeyPrefix;
  final ColorScheme cs;

  const _BranchTile({
    required this.branch,
    required this.picked,
    required this.onToggle,
    required this.onToggleBranch,
    required this.subtitleOf,
    required this.leafKeyPrefix,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final n = branch.leaves.where((f) => picked.contains(f.key)).length;
    final all = n == branch.leaves.length && n > 0;
    return ExpansionTile(
      key: ValueKey('$leafKeyPrefix-branch-${branch.lib}'),
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(left: 8),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(Icons.account_tree_outlined,
          size: 18, color: cs.onSurfaceVariant),
      title: Row(children: [
        Expanded(
          child: Text(branch.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Text('$n/${branch.leaves.length}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ]),
      trailing: TextButton(
        key: ValueKey('$leafKeyPrefix-branchall-${branch.lib}'),
        onPressed: () => onToggleBranch(branch.leaves, !all),
        child: Text(all ? '全不选' : '全选',
            style: const TextStyle(fontSize: 11)),
      ),
      children: [
        for (final f in branch.leaves)
          CheckboxListTile(
            key: ValueKey('$leafKeyPrefix-${f.key}'),
            dense: true,
            value: picked.contains(f.key),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(f.authorDir,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            subtitle: (subtitleOf?.call(f) ?? '').isEmpty
                ? null
                : Text(subtitleOf!.call(f),
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
            onChanged: (v) => onToggle(f, v == true),
          ),
      ],
    );
  }
}
