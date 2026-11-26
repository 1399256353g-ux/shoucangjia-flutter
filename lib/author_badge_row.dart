/// 作者词条的**唯一渲染实现**（0.9.291 · 第六十九批）。
///
/// 为什么要有这个文件：
///
/// 「单元库词条 + 作者等级」这一组小标签在页面里被画了两次：
///
/// ```
/// main.UnitBadges              → LibBadges → LibBadgeChip
///                                （圆角 kEntryRadius、层级边框底纹、
///                                  名称带 emoji 后缀、等级用 LibBadgeChip）
/// basic_lib_page 作者卡         → 两个手写 Container
///                                （圆角 4、无 emoji、无层级边框、
///                                  等级字号 9 但字体 w600）
/// ```
///
/// 两份都「画得出来」，所以不报错；但同一个作者在作者总览卡与基础库页作者卡上
/// **词条长得不一样**——圆角、边框、emoji、字重全都有差异，而这两张卡在视觉上
/// 是并列的、必须完全一致（owner 早就要求「同一套」）。
///
/// 这里只做「给定已解析好的值，摆一排词条」：谁属于哪个单元库、等级是多少，
/// 仍由各自的页面按自己的数据算（`LibMeta` / 基础库页的 `author_stats`），
/// 那是**数据来源**，不是可以统一的规则。可以统一的只有渲染。
library;

import 'package:flutter/material.dart';

import 'author_grade.dart';
import 'library_badge.dart';

/// 一个词条的**全部已解析参数**：文字、底色、库 id、层级外观。
///
/// 两条入口（作者卡那组「单元库+等级」与 `main.LibBadges` 那组「多个库 id」）
/// 在这里之后不再各写一遍容器：配色、层级、`+N` 都先算成 [BadgeChipSpec]，
/// 绘制只剩 [BadgeChipWrap] 一处。
class BadgeChipSpec {
  final String label;
  final int color;
  final String unitId;
  final LibEntryKind kind;

  const BadgeChipSpec({
    required this.label,
    required this.color,
    this.unitId = '',
    this.kind = LibEntryKind.unit,
  });
}

/// 把一组词条排成一行（`Wrap` 间距 3/3）。
///
/// 0.9.291：`main.LibBadges` 与 `AuthorBadgeRow` 此前各写一个 `Wrap` + 各自的
/// `LibBadgeChip` 列表。两份只要有一处改了间距或补了「最多几个」的规则，
/// 同一排词条在两个页面就不一样宽——而它们本来就该长得一模一样。
class BadgeChipWrap extends StatelessWidget {
  final List<BadgeChipSpec> chips;
  final WrapAlignment alignment;

  const BadgeChipWrap({
    super.key,
    required this.chips,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      alignment: alignment,
      children: [
        for (final c in chips)
          LibBadgeChip(
            label: c.label,
            color: c.color,
            unitId: c.unitId,
            kind: c.kind,
          ),
      ],
    );
  }
}

/// 可折叠的一排词条（owner 2026-11-26）。
///
/// 需求原文：
/// > 「基础库词条的出现是配合文件夹挂载机制的，若在播放页作者卡等地方显示
/// >   过长可留一个小展开显示按键，平日里可把基础库等词条隐藏起来……或者点
/// >   媒体库词条显现所有下级词条也行」
///
/// 分层规则（**旧规则不变**）：
///  - 媒体库词条：媒体库根
///  - 单元库词条：仍由**最下级的单元库**生成（挂载归属那一层），不由上层冒充
///  - 基础库词条：配合文件夹挂载，回答「这个作者在这几个基础库里有目录」
///
/// 显示策略：
///  - 常态只显示媒体库 + 单元库两级（层级一眼可辨，不占地方）
///  - 有基础库词条时，末尾给一个小展开键（`▾N`）
///  - 点媒体库词条同样展开全部下级（两种入口，任一都能看到全部）
class CollapsibleBadgeWrap extends StatefulWidget {
  final List<BadgeChipSpec> chips;
  final WrapAlignment alignment;

  /// 初始是否展开。默认折叠——作者卡在播放页里空间有限。
  final bool startExpanded;

  const CollapsibleBadgeWrap({
    super.key,
    required this.chips,
    this.alignment = WrapAlignment.start,
    this.startExpanded = false,
  });

  @override
  State<CollapsibleBadgeWrap> createState() => _CollapsibleBadgeWrapState();
}

class _CollapsibleBadgeWrapState extends State<CollapsibleBadgeWrap> {
  late bool _expanded = widget.startExpanded;

  @override
  void didUpdateWidget(covariant CollapsibleBadgeWrap old) {
    super.didUpdateWidget(old);
    // 词条集合变了（换作品/换作者）：折叠回常态，避免上一张卡的展开状态串过去。
    if (old.chips.length != widget.chips.length) {
      _expanded = widget.startExpanded;
    }
  }

  void _expand() {
    if (_expanded) return;
    setState(() => _expanded = true);
  }

  @override
  Widget build(BuildContext context) {
    final chips = widget.chips;
    if (chips.isEmpty) return const SizedBox.shrink();

    // 基础库词条是「可收纳」的那一级：它只为挂载服务，不参与层级辨识。
    final basics = <BadgeChipSpec>[
      for (final c in chips)
        if (c.kind == LibEntryKind.basic) c,
    ];
    final visible = <BadgeChipSpec>[
      for (final c in chips)
        if (c.kind != LibEntryKind.basic) c,
    ];
    // 不能把卡片藏空：若去掉基础库后什么都不剩，就全部照常显示、不给展开键。
    // （此前这里只是「补回显示」，却仍把 hasHidden 置真，于是出现
    //  「全都已经显示了，还给一个展开键」的矛盾状态。）
    final canFold = visible.isNotEmpty && basics.isNotEmpty;
    final hasHidden = canFold && !_expanded;
    final shown = <BadgeChipSpec>[
      if (canFold && !_expanded) ...visible else ...chips,
    ];
    final hiddenCount = hasHidden ? basics.length : 0;

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      alignment: widget.alignment,
      children: [
        for (final c in shown)
          // 点媒体库词条＝展开全部下级（owner 提的第二种入口）。
          c.kind == LibEntryKind.top && hasHidden
              ? GestureDetector(
                  onTap: _expand,
                  child: LibBadgeChip(
                    label: c.label,
                    color: c.color,
                    unitId: c.unitId,
                    kind: c.kind,
                  ),
                )
              : LibBadgeChip(
                  label: c.label,
                  color: c.color,
                  unitId: c.unitId,
                  kind: c.kind,
                ),
        if (hasHidden)
          _BadgeExpandChip(count: hiddenCount, onTap: _expand),
      ],
    );
  }
}

/// 折叠时在末尾显示的小展开键：`▾N`。
///
/// 尺寸比词条更小、无底纹，避免它自己被当成一个「词条」参与层级辨识。
class _BadgeExpandChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _BadgeExpandChip({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '展开 $count 个基础库词条',
      child: InkWell(
        key: const ValueKey('badge-expand'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(kEntryRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(kEntryRadius),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.22), width: 0.8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.expand_more, size: 11, color: Colors.white70),
            Text('$count',
                style: const TextStyle(
                    fontSize: 9, height: 1.2, color: Colors.white70)),
          ]),
        ),
      ),
    );
  }
}

/// 一排作者词条：单元库（可选）+ 等级（可选）。两者都空时占位为零尺寸。
class AuthorBadgeRow extends StatelessWidget {
  /// 单元库名称（可以带目录序号，渲染前统一 `stripIndex`）；空串不显示。
  final String unitLabel;

  /// 单元库底色（ARGB）。null 表示按 [unitId] 走 [LibraryBadge.colorForUnit]
  /// ——调用方已经算好颜色（例如无归属固定灰）时直接传入，避免再算一遍、
  /// 也算出另一个值。
  final int? unitColor;

  /// 配色顺序（只在 [unitColor] 为 null 时用到），与主页词条同源。
  final List<String> order;

  /// 单元库 id：决定 emoji 后缀与四级词条外观（顶级/单元/基础库）。
  final String unitId;

  /// 作者等级（D–S）；空串不显示。
  final String grade;

  final WrapAlignment alignment;

  /// 额外词条（基础库词条等）。标记为 [LibEntryKind.basic] 的会被折叠收纳。
  final List<BadgeChipSpec> extraChips;

  const AuthorBadgeRow({
    super.key,
    this.unitLabel = '',
    this.unitColor,
    this.order = const <String>[],
    this.unitId = '',
    this.grade = '',
    this.alignment = WrapAlignment.center,
    this.extraChips = const <BadgeChipSpec>[],
  });

  @override
  Widget build(BuildContext context) {
    final hasUnit = unitLabel.trim().isNotEmpty;
    final g = grade.trim();
    if (!hasUnit && g.isEmpty && extraChips.isEmpty) {
      return const SizedBox.shrink();
    }
    // 播放页作者卡空间有限：基础库词条默认折进末尾的展开键（owner 2026-11-26）。
    return CollapsibleBadgeWrap(
      alignment: alignment,
      chips: [
        if (hasUnit)
          BadgeChipSpec(
            label: unitLabel,
            color: unitColor ??
                LibraryBadge.colorForUnit(unitId, order: order),
            unitId: unitId,
            // 层级外观（边框/底纹）与主页词条同一处决定；id 为空时是 other。
            kind: LibraryBadge.entryKindOfUnit(unitId),
          ),
        if (g.isNotEmpty)
          BadgeChipSpec(label: g, color: AuthorGrade.colorForGrade(g)),
        ...extraChips,
      ],
    );
  }
}
