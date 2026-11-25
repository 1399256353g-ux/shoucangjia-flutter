/// L5-C 封面规则（纯函数，便于单测）。
///
/// 取图优先级（高 → 低）：
///  1. 文件夹自定义封面：`_cover/<version>.<ext>`（版本指针由服务端扫描写入
///     `libraries.json` 的 `cover` / `cover_ext`；只新增文件、不改旧文件，
///     旧图因此全部保留，回滚只需把指针改回旧版本）。
///  2. 爬虫脚本抓取的封面（作品目录的 `cover.jpg`，服务端索引以 `cv` 下发）。
///  3. 本机「App 本地播放量最高」且带缩略图的作品封面：
///     基础库取库内最高，单元库取整棵子树（含下级单元库）最高。
///  4. 都没有 → 默认图（文件夹图标）。
///
/// 本文件不碰网络与文件系统，只做「该用哪张图」的判定。
library;

import 'api_url.dart';
import 'media_priority.dart';
import 'cover_ext.dart';
import 'media_path.dart';
import 'text_clip.dart';

// `kCoverExts` / `kCoverImageExts` / `isCoverImagePath` 的唯一定义在
// `cover_ext.dart`（第十二批收口）；本文件继续 re-export，
// 使既有 import 点不必改。
export 'cover_ext.dart' show kCoverExts, kCoverImageExts, isCoverImagePath;

// 后缀剥除（`?` / `#` 段）走 `media_path.dart`（已在上方 import），
// 取末段走 `rel_path.lastRelName`（连 `\` 一起认）。
import 'rel_path.dart' show lastRelName;

/// 自定义封面目录名（位于库/单元库文件夹内）。
const String kCoverDir = '_cover';

/// 版本号合法化：只允许 `[A-Za-z0-9_-]`，拒绝路径分隔符与 `..`。
/// 返回空串表示非法（调用方应回退到下一种封面来源）。
String normalizeCoverVersion(String raw) {
  // 先剥 `?query` / `#fragment` 再取文件名。
  //
  // 封面指针可以来自服务端下发的地址（`_cover/v1.png?w=480`）、也可以来自
  // 用户粘贴的链接。旧写法只按 `/` 取最后一段、再按最后一个 `.` 截扩展名，
  // 于是 `_cover/v1.png?w=200` 的最后一段是 `v1.png?w=200`，扩展名判成
  // `png?w=200`（不在白名单里）→ 整个版本号被白名单拒绝，返回**空串**
  // ——`coverImageRel` 拿不到路径，库封面退回默认图，看起来像「封面丢了」。
  // 同一份路径在 `isCoverImagePath` 里早就认得这两个后缀，这里也必须剥。
  var s = stripMediaSuffix(raw);
  if (s.isEmpty) return '';
  // 上级目录穿越一律拒绝（指针只允许是纯版本名）
  if (s.contains('..')) return '';
  // 兼容「_cover/xxx.jpg」这种带目录与扩展名的写法。
  // 取末段走 `lastRelName`（唯一实现，连 `\` 一起认）；旧写法手写
  // `lastIndexOf('/')`，Windows 风格的 `_cover\v3.png` 取不到末段，
  // 整串 `_cover\v3.png` 随后被白名单拒成空串。
  s = lastRelName(s);
  final dot = s.lastIndexOf('.');
  if (dot > 0 && kCoverExts.contains(s.substring(dot + 1).toLowerCase())) {
    s = s.substring(0, dot);
  }
  if (s.isEmpty || s == '.') return '';
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s)) return '';
  // 上面的白名单只放 ASCII，所以这里切到 40 不会切到代理对；
  // 仍走公共入口，让“按长度截断”在整个 lib/ 里只有一处实现。
  return clipToUnits(s, 40);
}

/// 扩展名合法化：不在白名单内一律回落 `jpg`。
String normalizeCoverExt(String raw) {
  final e = raw.trim().toLowerCase().replaceFirst('.', '');
  if (e == 'jpeg') return 'jpeg';
  return kCoverExts.contains(e) ? e : 'jpg';
}

/// 拼接相对路径（去掉多余分隔符）。
String joinRel(String a, String b) {
  final x = a.trim().replaceAll(RegExp(r'[\\/]+'), '/');
  final y = b.trim().replaceAll(RegExp(r'[\\/]+'), '/');
  if (x.isEmpty || x == '.') return y;
  if (y.isEmpty) return x;
  return '${x.replaceAll(RegExp(r'/+$'), '')}/$y';
}

/// 自定义封面目录的相对路径：`<rel>/_cover`。
String coverDirRel(String rel) => joinRel(rel, kCoverDir);

/// 某版本封面的相对路径：`<rel>/_cover/<version>.<ext>`。
/// 版本非法时返回空串。
String coverImageRel(String rel, String version, {String ext = 'jpg'}) {
  final v = normalizeCoverVersion(version);
  if (v.isEmpty) return '';
  return joinRel(coverDirRel(rel), '$v.${normalizeCoverExt(ext)}');
}

/// 从 `libraries.json` 的原始条目读取封面指针。
/// 兼容三种写法：`cover: "v1"`、`cover: {v: "v1", e: "png"}`、
/// `cover: "v1.png"`。返回 (版本, 扩展名)；无封面时版本为空。
({String version, String ext}) coverPointerOf(dynamic raw) {
  String v = '';
  String e = 'jpg';
  if (raw is String) {
    v = raw;
  } else if (raw is Map) {
    v = '${raw['v'] ?? raw['version'] ?? raw['name'] ?? ''}';
    final re = '${raw['e'] ?? raw['ext'] ?? ''}'.trim();
    if (re.isNotEmpty) e = re;
  }
  final version = normalizeCoverVersion(v);
  if (version.isEmpty) return (version: '', ext: 'jpg');
  // `cover: "v1.png"`：扩展名取自字符串本身。
  //
  // 先剥 `?` / `#`：服务端可能把封面指针写成地址形式
  // （`v1.webp?w=480`），旧写法直接取最后一个 `.` 之后作为扩展名，
  // 得到 `webp?w=480`（不在白名单）→ 回落 `jpg`，与 `normalizeCoverVersion`
  // 剥完取到的 `webp` **不是同一个扩展名**：请求的是 `v1.jpg`，磁盘上是
  // `v1.webp`，封面 404。剥后缀与取末段都走公共函数。
  if (raw is String && e == 'jpg') {
    final body = stripMediaSuffix(raw);
    final dot = body.lastIndexOf('.');
    if (dot > 0) {
      final tail = body.substring(dot + 1).toLowerCase();
      if (kCoverExts.contains(tail)) e = tail;
    }
  }
  return (version: version, ext: normalizeCoverExt(e));
}

/// 一张封面结果：路径 + 来源（用于 UI 区分「自定义」与「作品封面」）。
class CoverPick {
  /// 相对库根的媒体路径；空串表示无图，调用方显示默认图。
  final String path;
  final bool custom;

  const CoverPick(this.path, {this.custom = false});

  const CoverPick.none()
      : path = '',
        custom = false;

  bool get isEmpty => path.isEmpty;
}

/// 媒体路径统一成 `/media/<lib>/<相对路径>`：
///  - 已带 `/media/` 前缀（服务端索引下发的 `th`）原样返回；
///  - 相对路径按库前缀补齐（与 `Cfg.media` 规则一致）；
///  - 空路径返回空串。
String libraryMediaPath(String lib, String path) {
  final p = path.trim();
  if (p.isEmpty) return '';
  // 绝对地址是自描述的：爬虫封面（`cv`）可能直接是 `http(s)://…` 的外链。
  // 再补 `/media/<lib>/` 会拼出 `…/media/lib/http://cdn/x.jpg`，服务端把
  // `http:` 当库内子目录，必然 404。绝对地址原样返回。
  if (isAbsoluteMediaUrl(p)) return p;
  // 服务端接口地址（`th` 被扫描器写成 `/api/thumb/<lib>/<id>`）：它不是媒体
  // 文件，套 `/media/<lib>/` 会变成 `/media/lib-019/api/thumb/...`，服务端把
  // `api` 当库内子目录 → 404，卡片就永远只有底色。原样返回，交给
  // `absoluteMediaUrl` 只补服务器前缀。
  if (isApiMediaPath(p)) return p;
  if (isMediaPath(p)) return p;
  final l = lib.trim();
  final rest = p.replaceFirst(RegExp(r'^/+'), '');
  if (l.isEmpty) return '/media/$rest';
  return '/media/${Uri.encodeComponent(l)}/$rest';
}

/// 媒体绝对地址：`<base>/media/<lib>/<相对路径>`。
/// [base] 为空时返回空串（调用方回退默认图）。
///
/// 必须经过 [encodeMediaPath]：文件名里的 `#` / `?` / 空格会让 `Uri.parse`
/// 把路径断成 fragment / query。此前这条规则只在 `Cfg.mediaUrl` 里执行，
/// 库卡片封面走本函数直拼，同一个文件「作品列表能播、卡片 404」。
String absoluteMediaUrl(
  String base, {
  required String lib,
  required String path,
}) {
  final b = baseForJoin(base);
  final p = libraryMediaPath(lib, path);
  if (b.isEmpty || p.isEmpty) return '';
  // 绝对地址自带前缀（不补服务器）但**仍然要转义**：`encodeMediaPath` 对
  // 绝对地址一律原样返回是为了避免重复编码，所以这里只把路径部分交给它，
  // 再拼回前缀——直接传 `'$b$p'` 会让转义整个跳过。
  if (isAbsoluteMediaUrl(p)) {
    final slash = p.indexOf('/', p.indexOf('//') + 2);
    if (slash < 0) return p;
    return '${p.substring(0, slash)}${encodeMediaPath(p.substring(slash))}';
  }
  return '$b${encodeMediaPath(p)}';
}

/// 单元库自定义封面的媒体路径（`cover: {u: "/media/<lib>/..."}`）。
///
/// 0.9.35：服务端把 owner 选定的单元库封面指针存在
/// `LIBDIR/unit-covers.json`，随 `/api/nodes`、`/api/libraries.json` 的节点
/// `cover.u` 下发（不改媒体目录、不动作品原图）。这里只做取值与校验：
/// 非 `/media/` 开头的一律当作没有，避免半截路径被当封面去请求。
String coverUrlOf(dynamic raw) {
  if (raw is! Map) return '';
  final u = '${raw['u'] ?? raw['url'] ?? ''}'.trim();
  if (u.isEmpty) return '';
  return isMediaPath(u) ? u : '';
}

/// 媒体路径里的库 id：`/media/lib-008/a/b.jpg` → `lib-008`；不是媒体路径返回空串。
/// 用于把「单元库封面」按其所归属的基础库路由到对应服务器。
///
/// 必须**解码**库段：`Cfg.media()` 写出的就是 `Uri.encodeComponent(l)`
/// （中文/空格库名会变成 `%E4%B8%AD%E6%96%87`），而调用方拿到的这个 id
/// 会直接去查绑定表 `_bindings` / 拼鉴权头。此前这里返回原文，于是中文库
/// 的封面/删除记录/头像全部解析不到连接，退回当前库 → 请求打错服务器。
/// 与 `serverAvatarFileFromPath` 的解码口径保持一致（同一规则不允许两份）。
String libOfMediaPath(String p) {
  final path = p.trim();
  if (!isMediaPath(path)) return '';
  final rest = path.substring(7);
  final at = rest.indexOf('/');
  if (at <= 0) return '';
  final seg = rest.substring(0, at);
  // 非法百分号编码：原样返回，让调用方按「未命中」处理，不抛异常。
  return decodeComponentOrRaw(seg);
}

/// 最后一级兜底：第一张作品的封面（只收图片）。
///
/// 只在「自定义 / 爬虫 / 播放量最高」都拿不到可用图片时才被用到；
/// 视频路径（mp4/mov…）当封面只会一直渲染失败，因此直接判为无图。
CoverPick pickFirstWorkCover(String firstThumb) {
  final fb = firstThumb.trim();
  if (!isCoverImagePath(fb)) return const CoverPick.none();
  return CoverPick(fb);
}

/// 基础库封面：
///  - 有自定义版本 → `_cover/<version>.<ext>`；
///  - 否则取本机播放量最高的作品缩略图（[bestThumb]，由 WorkPlaysStore 提供）；
///  - 再退到第一张作品的封面（[firstThumb]）；
///  - 都没有 → 空（显示默认图）。
CoverPick pickBasicCover({
  required String rel,
  String bestThumb = '',
  String firstThumb = '',
  String crawlerThumb = '',
  String version = '',
  String ext = 'jpg',
}) =>
    _pickLibCover(
      rel: rel,
      bestThumb: bestThumb,
      firstThumb: firstThumb,
      crawlerThumb: crawlerThumb,
      version: version,
      ext: ext,
    );

/// 单元库（上级文件夹）封面：
///  - 有自定义版本 → `_cover/<version>.<ext>`；
///  - 否则取子树内本机播放量最高的作品缩略图（[bestThumb]，整棵子树合并）；
///  - 再退到子树里第一张作品的封面（[firstThumb]）；
///  - 都没有 → 空（显示默认图）。
CoverPick pickUnitCover({
  required String rel,
  String bestThumb = '',
  String firstThumb = '',
  String crawlerThumb = '',
  String version = '',
  String ext = 'jpg',
}) =>
    _pickLibCover(
      rel: rel,
      bestThumb: bestThumb,
      firstThumb: firstThumb,
      crawlerThumb: crawlerThumb,
      version: version,
      ext: ext,
    );

/// 基础库与单元库共用的**唯一**取图实现。
///
/// 两者只有「为什么 bestThumb 是这一张」不同（单元库是整棵子树合并，
/// 基础库是本库），**取图优先级完全相同**：自定义 → 爬虫/最高播放 →
/// 第一张作品。此前这里有两份逐字相同的实现；改一处忘一处会让同一张封面
/// 在两个入口上优先级不一致（典型现象：单元库卡片显示了，基础库卡片没显示）。
CoverPick _pickLibCover({
  required String rel,
  String bestThumb = '',
  String firstThumb = '',
  String crawlerThumb = '',
  String version = '',
  String ext = 'jpg',
}) {
  final custom = coverImageRel(rel, version, ext: ext);
  if (custom.isNotEmpty) return CoverPick(custom, custom: true);
  final pick = pickCoverPath(crawler: crawlerThumb, auto: bestThumb);
  if (pick.isNotEmpty) return CoverPick(pick);
  // 高优先级来源都不可用时的兜底：第一张作品的封面（仅图片）。
  return pickFirstWorkCover(firstThumb);
}
