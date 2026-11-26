/// 封面扩展名规则（**单一真源**）。
///
/// 第十二批收口：这里有两条**不同**的规则，此前各自被抄了多份：
///
/// 规则 A「能显示成封面吗」（`isCoverImagePath`）——白名单除了可保存的四种，
/// 还要放宽到 gif/bmp/heic（服务端索引里可能出现，直接剔除会让封面永不显示）。
/// 原先是 `lib_cover.kCoverImageExts` 与 `media_priority._coverImageExts`
/// **两份逐字相同**的实现。
///
/// 规则 B「能作为封面版本存下来吗」（`kCoverExts` / `normalizeCoverExt`）——
/// 服务端只落这四种。原先是 `lib_cover.kCoverExts` 与
/// `cover_history._kCoverExts` 两份相同集合，**归一函数**又各写一份：
/// `lib_cover.normalizeCoverExt` 只 `replaceFirst('.', '')`、
/// `cover_history.coverVersionFromJson` 只 `startsWith('.')` 截点，
/// 两者都不剥 `?query` / `#fragment`，也都不取末段。
///
/// 之所以不从 `lib_cover` 直接引，是因为 `media_priority` 是最底层（零 import），
/// 让它反过来依赖 `lib_cover` 会形成环。两条规则单独放这里，谁都可以引。
library;

import 'media_path.dart' show isImageMediaPath, kImageExts, stripMediaSuffix;
import 'rel_path.dart' show lastRelName;

/// 规则 A：可以当作封面**渲染**的扩展名（含服务端索引里出现的图片格式）。
///
/// 0.9.281：成员表移到 `media_path.kImageExts`（与服务端 `IMAGE_EXT` 同源），
/// 这里只是同一张表的引用。此前本文件列 7 种（有 heic、缺 avif），
/// `author_avatar.kAvatarImageExts` 列 7 种（有 avif、缺 heic），
/// `playback_error` 又列第三份——同一份 `.avif` 封面「能显示」但「不能当封面」。
const List<String> kCoverImageExts = kImageExts;

/// 规则 B：可以作为封面**版本文件**保存的扩展名（服务端只落这四种）。
const List<String> kCoverExts = <String>['jpg', 'jpeg', 'png', 'webp'];

/// 路径是否是**服务端能吃**的图片（缩图与头像注册共用这一条判定）。
///
/// 服务端的两个接口认的是同一组四个扩展名，但客户端此前各写了一份：
///  - `media_resize._imageExt = RegExp(r'\.(jpe?g|png|webp)$')`（是否加 `?w=`）；
///  - `author_avatar_store.isServerAvatarFileName` 里又一条同义正则。
///
/// 两份都只看「末段是否匹配」，但都不剥 `?query` / `#fragment` 之外的形态，
/// 且以后服务端加一种格式（或去掉一种）时必须两处同时改。成员集合只有
/// [kCoverExts] 一份，判定也只有这一处。
///
/// 注意这是「服务端能处理」的规则，**不是**「能显示」（见 [kCoverImageExts]）：
/// heic/gif 能显示，但缩图与头像注册都不吃。
bool isServerImagePath(String p) {
  final l = stripMediaSuffix(p).toLowerCase();
  if (l.isEmpty) return false;
  for (final e in kCoverExts) {
    if (l.endsWith('.$e')) return true;
  }
  return false;
}

/// 扩展名归一（**唯一定义**）：剥 `?query`/`#fragment` → 取末段 → 去空白 →
/// 去前导点 → 小写；不在 [kCoverExts] 内一律回落 `jpg`。
///
/// ```
/// lib_cover.normalizeCoverExt('png?w=1')                 -> 'jpg'   ← 同一张 png 存成 jpg
/// coverVersionFromJson({'e': 'png?w=1'}).ext             -> 'jpg'   ← 同一个串第二种判法
/// normalizeCoverExt('_cover/v1.PNG?w=480')               -> 'jpg'   ← 连末段都没取
/// ```///
/// 扩展名判错的后果不是「显示错」，是**请求另一个文件**：`coverImageRel`
/// 用 `v1.jpg` 拼地址、磁盘上是 `v1.png`，封面 404，退回默认图。
///
/// 取末段走 `rel_path.lastRelName`（连 `\` 一起认），后缀剥除走
/// `media_path.stripMediaSuffix`——两件已有公共出口的事不再各写一份。
String normalizeCoverExt(String raw) => coverExtOrNull(raw) ?? 'jpg';

/// 同 [normalizeCoverExt]，但**不在白名单时返回 null**（区分「没写」与「写错」）。
///
/// 需要「有就用、没有再看别处」的调用方用它：封面指针里 `e` 字段缺失、
/// 或写了一个服务端并不支持的扩展名（`gif`）时，必须能判断出「这一项没说」，
/// 而不是拿到一个被兜底成 `jpg` 的值再当成用户的真实意图。
String? coverExtOrNull(String raw) {
  // 先剥 `?query`/`#fragment`，再取末段（`_cover/v3.PNG` 也能到 `PNG`）。
  var e = lastRelName(stripMediaSuffix(raw)).trim().toLowerCase();
  // 传进来的可能是「扩展名」本身（`png` / `.webp`），也可能是带扩展名的
  // 文件名（`v3.PNG`）——两种都归一到点后那一段。
  final dot = e.lastIndexOf('.');
  if (dot >= 0) e = e.substring(dot + 1);
  return kCoverExts.contains(e) ? e : null;
}

/// 从**文件名**里取扩展名（要求末段确实带 `.`）；没有返回 null。
///
/// 与 [coverExtOrNull] 的区别只在「裸版本名」这一种输入：版本名 `v1` 不含点，
/// 不能被当成「扩展名 v1」；而版本名恰好叫 `png` 时也不该被认成 png 扩展名。
String? coverExtInName(String raw) {
  final name = lastRelName(stripMediaSuffix(raw));
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  final e = name.substring(dot + 1).trim().toLowerCase();
  return kCoverExts.contains(e) ? e : null;
}

/// 路径是否是可显示的封面图片（视频路径一律不是）。
///
/// 只看扩展名，忽略 `?query` 与 `#fragment`。**两个都要剥**：旧写法只写了
/// `split('?').first`，实测 `isCoverImagePath('/a.jpg#poster')` 返回 **false**
/// ——`pickCoverPath` 把这张唯一的候选剔除，卡片只剩一块空白，而地址本身
/// 完全能加载。后缀剥除走 [stripMediaSuffix]（与 `isVideoMediaPath`
/// 同一条规则，不再两份）。
bool isCoverImagePath(String p) {
  // 判定转发 `media_path.isImageMediaPath`（唯一分类表）：这里再列一遍
  // 循环，就等于给同一张表写了第二个解析器。
  return isImageMediaPath(p);
}
