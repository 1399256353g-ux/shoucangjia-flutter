/// 卡片与头像的**尺寸表**（圆角、头像边长）。
///
/// 为什么要有这个文件（0.9.288）：
///
/// 同一批数字此前散在各自 widget 的 `static const` 和页面内联字面量里，
/// 每一处都「自己算得出一个值」，所以不会报错、也没有第二份实现可对比：
///
/// ```
/// lib/unit_library_view.dart  const kLibCardRadius = 12;      ← 库卡片
/// lib/main.dart               AuthorGridCard.radius = 12;     ← 作者卡片
/// lib/basic_lib_page.dart     BorderRadius.circular(12) ×2    ← 基础库页作者卡片
/// lib/main.dart               AuthorAvatar.gridSize = 58;     ← 作者网格头像
/// lib/main.dart               AuthorAvatar.rankSize = 42;     ← 排行榜头像
/// lib/main.dart               AuthorAvatar.headerSize = 64;   ← 作者页头像
/// ```
///
/// 三处 12 是同一个圆角的三份说法：作者总览卡与基础库页作者卡在视觉上必须
/// 完全一致（同一套排版、同一张头像、同一组词条），只改其中一处就会出现
/// 「同一个作者在两页里圆角不同」。头像尺寸同理——解码宽度按显示尺寸算
/// （`author_grid.avatarDecodeWidth`），多一个 58 的副本，解码宽度就会跟着
/// 分叉，同一张头像在两处各解码一次。
///
/// 本文件只有数字，不含任何布局逻辑。
library;

import 'package:flutter/painting.dart';

/// 库卡片与作者卡片的统一圆角（单元库卡 / 基础库卡 / 作者总览卡 /
/// 基础库页作者卡共用）。`kLibCardRadius` 与 `AuthorGridCard.radius`
/// 都转发它。
const double kCardRadius = 12;

/// 作品卡片圆角（`WorkCard`）。
///
/// 比 [kCardRadius] 小一档：作品卡在网格里更密（间距 2），更大的圆角会让
/// 相邻卡片的圆角互相「顶」在一起。这是一个**独立的决定**，不是 12 的副本，
/// 所以单独立名而不是复用。
const double kWorkCardRadius = 10;

/// 作者网格卡片上的头像边长（`AuthorAvatar.gridSize`）。
const double kAvatarGridSize = 58;

/// 排行榜行内头像边长（`AuthorAvatar.rankSize`）。
const double kAvatarRankSize = 42;

/// 作者主页头部头像边长（`AuthorAvatar.headerSize`）。
const double kAvatarHeaderSize = 64;

/// 作者主页信息头的内边距（四边同值）。
///
/// 0.9.306：真实头部写 `EdgeInsets.all(14)`，加载骨架又写一遍 `all(14)`，
/// 两处是同一个数却没有名字——改真实头部的留白，骨架仍按 14 铺，
/// 「加载完成」那一刻整块信息区横向跳一下。
const double kAuthorHeaderPadding = 14;

/// 作者主页信息头里「头像」与「文字列」之间的横向间距。
///
/// 同上：真实头部与骨架各写一遍 12。骨架按 12 排、真实头部改成别的值时，
/// 占位块与真实文字的左边界对不上，骨架阶段看起来像「两栏错位」。
const double kAuthorHeaderAvatarGap = 12;

/// 作者页加载骨架里三行占位文字的宽度（短 / 中 / 长）。
///
/// 0.9.317：这三个数此前是 `_AuthorPageSkeleton` 里的裸字面量 64 / 220 / 160。
/// 它们**不是**真实文字宽度的副本——真实头部那三行是 `Expanded` 里的
/// 自动换行文本，没有固定宽度。裸字面量的问题不是「和真实值不一致」，而是
/// 读代码的人会以为这三个数对应某处的真实排版，改真实头部时还去找它们。
/// 立名后语义明确：只描述骨架占位块的相对长短。
const double kAuthorHeaderLineShort = 64;
const double kAuthorHeaderLineMedium = 220;
const double kAuthorHeaderLineLong = 160;

/// 基础库页作者卡片上的头像边长（与作者总览一致）。
const double kAvatarBasicAuthorSize = kAvatarGridSize;

/// 播放页信息区（左下作者行）头像边长。
///
/// 0.9.291：这个 38 曾是播放页内联字面量，连解码宽度都是 `(38 * dpr).round()`
/// ——没有走 `avatarDecodeWidth`，与其它四处的解码宽度规则不同，同一张头像
/// 在播放页要按另一个尺寸再解码一次。
const double kAvatarPlayerSize = 38;

/// 作者「选一张作头像」弹窗的候选格边长。
///
/// 0.9.292：弹窗内容区固定 420dp、三列、间距 6 —— 每格实际 **136dp**；
/// 而解码宽度当时写的是 `avatarDecodeWidth(displaySize: 96)`（一个内联的
/// 「看起来差不多大」的数字）。后果不是样式不同，而是模糊：136dp 的格子
/// 按 96dp 解码后放大 1.4 倍显示。格子边长现在立名，解码宽度仍走
/// `avatarDecodeWidth`。
const double kAvatarCandidateSize = 136;

/// 删除记录列表里的缩略图边长（`main._deletedThumb`）。
///
/// 0.9.292：解码宽度当时是内联 `memCacheWidth: 160`，而图是 56dp——
/// 56 × 3 = 168，160 比真实像素少 8。尺寸与解码宽度两处都内联，改一处
/// 就会对不上（且 2x/3x 屏下 160 已经被放大）。
const double kDeletedThumbSize = 56;

/// 排行榜一行（`AuthorRankTile` 的 `ListTile`）的实测逻辑高度。
///
/// 0.9.289：首屏预热此前按 `firstScreenRowCount` 的默认 72 行高估算，实际
/// 排版是 67（`ListTile` + 两行 subtitle），多算约 7% —— 预热到的是屏幕外的
/// 最后一行头像。列表页的分隔线也是 1dp，两者一起决定真实行步进。
const double kAuthorRankTileHeight = 67;

/// 排行榜列表的分隔线高度（页面 `Divider(height: ...)`）。
const double kAuthorRankDividerHeight = 1;

/// 排行榜一行的纵向步进（行高 + 分隔线）：首屏预热算行数用它。
const double kAuthorRankRowExtent =
    kAuthorRankTileHeight + kAuthorRankDividerHeight;

/// 基础库页「作者」tab 搜索框高度（页面内唯一一份）。
///
/// 这个 38 与输入框自身的 `isDense` + 内边距一起决定行高：压低一格，
/// 下方作者网格就多一行，而首屏预热按网格约束算张数。
const double kBasicAuthorSearchHeight = 38;

/// 基础库页「作者」tab 卡片的内容内边距。
///
/// 上 12 / 下 10 是刻意不对称（名字行贴近底边），四边同值就不对了。
/// 这组数字在这页只出现一次，但它与网格行高（`kBasicAuthorGrid`
/// 0.86 比例）一起决定卡片里能放几行字——立名后改比例时不会忘了同步。
const EdgeInsets kBasicAuthorCardPadding =
    EdgeInsets.fromLTRB(10, 12, 10, 10);
