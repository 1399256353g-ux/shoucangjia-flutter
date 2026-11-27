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

/// 一个词条的**全部已解析参数**：文字、底色、库 id、层级外观、后缀。
///
/// 两条入口（作者卡那组「单元库+等级」与 `main.LibBadges` 那组「多个库 id」）
/// 在这里之后不再各写一遍容器：配色、层级、`+N` 都先算成 [BadgeChipSpec]，
/// 绘制只剩 [CollapsibleBadgeWrap] 一处（0.9.312 删掉了零调用点的
/// `BadgeChipWrap`——它只是「不可折叠」这个从未被使用的选项）。
class BadgeChipSpec {
  final String label;
  final int color;
  final String unitId;
  final LibEntryKind kind;

  /// 已算好的 emoji 后缀；null 表示按 [unitId] 走 `LibraryBadge.emojiFor`。
  ///
  /// 基础库词条要按「本库设过 → 所属单元库」取后缀（`basicEmojiFor`），
  /// 而 `emojiFor` 只认单元库 id——直接把基础库 id 传进去会拿不到单元库
  /// 那条继承链。这里显式带上结果，绘制层不再猜。
  final String? emoji;

  const BadgeChipSpec({
    required this.label,
    required this.color,
    this.unitId = '',
    this.kind = LibEntryKind.unit,
    this.emoji,
  });
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

  /// 单条词条最大宽度（透传给 [LibBadgeChip]）。
  ///
  /// 固定尺寸的小卡片必须传得比 [kBadgeChipMaxWidth] 更小：150dp 的作者卡
  /// 只放得下**一行**词条（卡片顶部预留 22dp），媒体库 + 单元库两级都按
  /// 120dp 上限排版时会各占一行，第二行压到头像上。这里不是「字太长」，
  /// 是容器宽度决定了单条上限，由容器自己声明。
  final double chipMaxWidth;

  const CollapsibleBadgeWrap({
    super.key,
    required this.chips,
    this.alignment = WrapAlignment.start,
    this.startExpanded = false,
    this.chipMaxWidth = kBadgeChipMaxWidth,
  });

  @override
  State<CollapsibleBadgeWrap> createState() => _CollapsibleBadgeWrapState();
}

class _CollapsibleBadgeWrapState extends State<CollapsibleBadgeWrap> {
  late bool _expanded = widget.startExpanded;

  @override
  void didUpdateWidget(covariant CollapsibleBadgeWrap old) {
    super.didUpdateWidget(old);
    // 词条内容变了（换作品/换作者）：折叠回常态，避免上一张卡的展开状态串过去。
    //
    // 0.9.306：原来只比 `chips.length`。播放页左右滑到下一条作品时，
    // 两条作品的词条条数**恰好相同**（同一个单元库 + 同一等级 + 同样两个基础库）
    // 是非常常见的情形，于是就绪状态一路带过去：用户从未点过展开，
    // 下一条作品的卡片却是展开的——「平日隐藏」形同虚设。
    // 判据改成「内容是否完全相同」：条数相同但文字/颜色/层级不同也算变。
    if (!_sameChips(old.chips, widget.chips)) {
      _expanded = widget.startExpanded;
    }
  }

  static bool _sameChips(List<BadgeChipSpec> a, List<BadgeChipSpec> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label ||
          a[i].color != b[i].color ||
          a[i].unitId != b[i].unitId ||
          a[i].kind != b[i].kind ||
          a[i].emoji != b[i].emoji) {
        return false;
      }
    }
    return true;
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
                    emoji: c.emoji,
                    maxWidth: widget.chipMaxWidth,
                  ),
                )
              : LibBadgeChip(
                  label: c.label,
                  color: c.color,
                  unitId: c.unitId,
                  kind: c.kind,
                  emoji: c.emoji,
                  maxWidth: widget.chipMaxWidth,
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
    // 0.9.306：展开键的底色/描边/文字此前写死成白色（`Colors.white` /
    // `white70`）。主题里有浅色主题（`daylight`，背景 `0xFFF5F7FB`）：
    // 白字压在浅色卡片上等于看不见——真缺陷，不是风格差异。
    // 改用主题前景色，深/浅主题都自洽。
    final fg = Theme.of(context).colorScheme.onSurface;
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
            color: fg.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(kEntryRadius),
            border: Border.all(color: fg.withValues(alpha: 0.28), width: 0.8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.expand_more, size: 11, color: fg.withValues(alpha: 0.75)),
            Text('$count',
                style: TextStyle(
                    fontSize: 9,
                    height: 1.2,
                    color: fg.withValues(alpha: 0.75))),
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

  /// 单元库 id：决定 emoji 后缀与三级词条外观（媒体库/单元库/基础库）。
  final String unitId;

  /// 作者等级（D–S）；空串不显示。
  final String grade;

  final WrapAlignment alignment;

  /// 额外词条（基础库词条、媒体库词条）。标记为 [LibEntryKind.basic] 的
  /// 会被折叠收纳；[LibEntryKind.top] 固定排在最前。
  final List<BadgeChipSpec> extraChips;

  /// 单条词条最大宽度（透传）。固定尺寸的小卡片传更小的值，避免换行。
  final double chipMaxWidth;

  const AuthorBadgeRow({
    super.key,
    this.unitLabel = '',
    this.unitColor,
    this.order = const <String>[],
    this.unitId = '',
    this.grade = '',
    this.alignment = WrapAlignment.center,
    this.extraChips = const <BadgeChipSpec>[],
    this.chipMaxWidth = kBadgeChipMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnit = unitLabel.trim().isNotEmpty;
    final g = grade.trim();
    if (!hasUnit && g.isEmpty && extraChips.isEmpty) {
      return const SizedBox.shrink();
    }
    // 层级顺序固定为「媒体库 → 单元库 → 等级 → 其余（基础库、折叠）」。
    // 媒体库词条是 external 传入的（基础库页拿不到父级，由调用方算好），
    // 排在最前才与作者主页/播放页一致——同一作者在三个页面上词条顺序相同，
    // 否则“第一眼看到的是哪一级”随页面变。
    final tops = <BadgeChipSpec>[
      for (final c in extraChips)
        if (c.kind == LibEntryKind.top) c,
    ];
    final rest = <BadgeChipSpec>[
      for (final c in extraChips)
        if (c.kind != LibEntryKind.top) c,
    ];
    // 播放页作者卡空间有限：基础库词条默认折进末尾的展开键（owner 2026-11-26）。
    return CollapsibleBadgeWrap(
      alignment: alignment,
      chipMaxWidth: chipMaxWidth,
      chips: [
        ...tops,
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
        ...rest,
      ],
    );
  }
}
