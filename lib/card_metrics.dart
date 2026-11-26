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

/// 基础库页作者卡片上的头像边长（与作者总览一致）。
const double kAvatarBasicAuthorSize = kAvatarGridSize;

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
