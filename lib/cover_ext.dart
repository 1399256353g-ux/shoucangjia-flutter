/// 封面扩展名规则（**单一真源**）。
///
/// 第十二批收口：这里有两条**不同**的规则，此前各自被抄了多份：
///
/// 规则 A「能显示成封面吗」（`isCoverImagePath`）——白名单除了可保存的四种，
/// 还要放宽到 gif/bmp/heic（服务端索引里可能出现，直接剔除会让封面永不显示）。
/// 原先是 `lib_cover.kCoverImageExts` 与 `media_priority._coverImageExts`
/// **两份逐字相同**的实现。
///
/// 规则 B「能作为封面版本存下来吗」（`kCoverExts`）——服务端只落这四种。
/// 原先是 `lib_cover.kCoverExts` 与 `cover_history._kCoverExts` 两份相同集合。
///
/// 之所以不从 `lib_cover` 直接引，是因为 `media_priority` 是最底层（零 import），
/// 让它反过来依赖 `lib_cover` 会形成环。两条规则单独放这里，谁都可以引。
library;

import 'media_path.dart' show stripMediaSuffix;

/// 规则 A：可以当作封面**渲染**的扩展名（含服务端索引里出现的图片格式）。
const List<String> kCoverImageExts = <String>[
  '.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic'
];

/// 规则 B：可以作为封面**版本文件**保存的扩展名（服务端只落这四种）。
const List<String> kCoverExts = <String>['jpg', 'jpeg', 'png', 'webp'];

/// 路径是否是可显示的封面图片（视频路径一律不是）。
///
/// 只看扩展名，忽略 `?query` 与 `#fragment`。**两个都要剥**：旧写法只写了
/// `split('?').first`，实测 `isCoverImagePath('/a.jpg#poster')` 返回 **false**
/// ——`pickCoverPath` 把这张唯一的候选剔除，卡片只剩一块空白，而地址本身
/// 完全能加载。后缀剥除走 [stripMediaSuffix]（与 `isVideoMediaPath`
/// 同一条规则，不再两份）。
bool isCoverImagePath(String p) {
  final l = stripMediaSuffix(p).toLowerCase();
  if (l.isEmpty) return false;
  for (final e in kCoverImageExts) {
    if (l.endsWith(e)) return true;
  }
  return false;
}
