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
import 'cover_ext.dart';
import 'media_path.dart';
import 'text_clip.dart';

// `kCoverExts` / `kCoverImageExts` / `isCoverImagePath` 的唯一定义在
// `cover_ext.dart`（第十二批收口）；本文件继续 re-export，
// 使既有 import 点不必改。
export 'cover_ext.dart'
    show
        kCoverExts,
        kCoverImageExts,
        isCoverImagePath,
        normalizeCoverExt,
        coverExtOrNull,
        coverExtInName;

// 扩展名归一（`normalizeCoverExt`）同样在 `cover_ext.dart`，经上面的
// re-export 暴露；本文件不再写转发函数（同名再定义会让调用方歧义）。

// 后缀剥除（`?` / `#` 段）走 `media_path.dart`（已在上方 import），
// 取末段走 `rel_path.lastRelName`（连 `\` 一起认）。
import 'rel_path.dart' show lastRelName, relSegments, relJoin;

/// 自定义封面目录名（位于库/单元库文件夹内）。
const String kCoverDir = '_cover';

/// 版本号合法化：只允许 `[A-Za-z0-9_-]`，拒绝路径分隔符与 `..`。
/// 返回空串表示非法（调用方应回退到下一种封面来源）。
///
/// [clip] 区分两种来源：用户输入按 40 截断（写入侧，截断后仍是用户自己的名字）；
/// 服务端已落盘的版本名超长时返回空串（读取侧，截断会指向一个不存在的文件、
/// 请求 404）。**判定规则只有这一份**：`cover_history.coverVersionFromJson`
/// 此前自己写了一遍 `^[A-Za-z0-9_-]{1,40}$`，两处只差「超长」这一种输入。
String normalizeCoverVersionName(String raw, {bool clip = true}) {
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
  if (!clip && s.length > 40) return '';
  if (s.length > 40) {
    // 上面的白名单只放 ASCII，所以这里切到 40 不会切到代理对；
    // 仍走公共入口，让“按长度截断”在整个 lib/ 里只有一处实现。
    return clipToUnits(s, 40);
  }
  return s;
}

/// 写入侧的口径（用户可输入的名字一律截断）。
String normalizeCoverVersion(String raw) => normalizeCoverVersionName(raw);

// 扩展名归一（`normalizeCoverExt`）的唯一实现在 `cover_ext.dart`，由上面的
// re-export 暴露。这里**不再**写一个同名转发：同名再定义一次会让同时
// import 两个文件的调用方变成歧义引用（实测 `test` 直接报
// `'normalizeCoverExt' is imported from both`）。

/// 拼接相对路径（去掉多余分隔符、`.` 段与首尾斜杠）。
///
/// 拆分/归一交给 `rel_path.relSegments` + `relJoin`（**唯一实现**）。此前这里
/// 自己写了一套「`replaceAll(RegExp(r'[\\\\/]+'), '/')` + 掐尾斜杠」，与那条
/// 链差三点，实测都能拼出请求不到的文件名：
///
/// ```
/// joinRel('A', '/B')   -> 'A//B'          ← 第二段的前导斜杠没吃掉
/// joinRel('A', ' /x')  -> 'A//x'          ← 空格在 trim 之后仍留了斜杠
/// coverImageRel('A/./B', 'v1') -> 'A/./B/_cover/v1.jpg'  ← `.` 段没消
/// ```
///
/// 三个返回值都能拼成 `/media/<lib>/A//B` 这类地址：服务端按字面路径找不到
/// 文件，封面 404 而界面只显示默认图，看不出是哪一层拼错。
String joinRel(String a, String b) =>
    relJoin([...relSegments(a), ...relSegments(b)]);

/// 自定义封面目录的相对路径：`<rel>/_cover`。
String coverDirRel(String rel) => joinRel(rel, kCoverDir);

/// 某版本封面的**文件名**：`<version>.<ext>`（不带目录）。
///
/// `cover_history.CoverVersion.fileName` 与 [coverImageRel] 此前各拼一遍
/// `'$v.$ext'`：前者用来去重与做 widget key，后者用来拼请求路径。两份拼法
/// 一旦差一个点或少一次 `normalizeCoverExt`，历史面板里那一项就点不动
/// （key 对得上、请求的文件名对不上）。
String coverVersionFileName(String version, {String ext = 'jpg'}) {
  final v = normalizeCoverVersion(version);
  if (v.isEmpty) return '';
  return '$v.${normalizeCoverExt(ext)}';
}

/// 某版本封面的相对路径：`<rel>/_cover/<version>.<ext>`。
/// 版本非法时返回空串。
String coverImageRel(String rel, String version, {String ext = 'jpg'}) {
  final name = coverVersionFileName(version, ext: ext);
  if (name.isEmpty) return '';
  return joinRel(coverDirRel(rel), name);
}

/// 从 `libraries.json` 的原始条目读取封面指针。
/// 兼容三种写法：`cover: "v1"`、`cover: {v: "v1", e: "png"}`、
/// `cover: "v1.png"`。返回 (版本, 扩展名)；无封面时版本为空。
({String version, String ext}) coverPointerOf(dynamic raw) {
  String v = '';
  // `e` 只保留**服务端真的写了什么**：默认空串，不能预先填 'jpg'——
  // 预填会让「没写 e」与「e: jpg」两种输入变得不可区分（下面的三态判定失效）。
  String e = '';
  if (raw is String) {
    v = raw;
  } else if (raw is Map) {
    v = '${raw['v'] ?? raw['version'] ?? raw['name'] ?? ''}';
    e = '${raw['e'] ?? raw['ext'] ?? ''}'.trim();
  }
  final version = normalizeCoverVersion(v);
  if (version.isEmpty) return (version: '', ext: 'jpg');
  // 扩展名优先级：**显式声明的 `e`（合法时）> 版本名自带的扩展名 > jpg**。
  //
  // 旧写法只在 `raw is String` 时才看版本名里的扩展名，`cover:{v:"v1.png"}`
  // （服务端把版本名与扩展名合成一个字段的写法）实测返回 `ext: jpg`——
  // 请求 `v1.jpg`、磁盘是 `v1.png`，封面 404。另一半是反过来的：
  // `cover:{v:"v1.png", e:"gif"}` 里 `e` 不在白名单，旧写法先把它兜底成
  // `jpg` 再也没机会看版本名，于是明明有 `png` 可用却请求 `jpg`。
  //
  // 所以先把「显式 e」判成 `合法 / 没写 / 写错` 三态（`coverExtOrNull`），
  // 只有「没写」才回落到版本名自带扩展名（`coverExtInName`）。
  final declared = raw is Map ? coverExtOrNull(e) : null;
  if (declared != null) return (version: version, ext: declared);
  return (version: version, ext: coverExtInName(v) ?? 'jpg');
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

/// 封面候选来源，**声明顺序就是优先级（高 → 低）**。
///
/// owner 的口径只有一条链：手动指定 > 自定义 `_cover/` > 爬虫封面 `cv` >
/// 本机播放量最高 > 首张作品图。这条链此前在四处各写一遍（`pickBasicCover` /
/// `pickUnitCover` / `main._basicCoverUrl` / `main._unitCoverUrl`），
/// 每处的「顺序」和「哪几种参与」都略有不同——所以会出现「单元库卡片显示了、
/// 基础库卡片没显示」这类只在某个入口复现的灰卡。
///
/// 现在顺序只在这一张表里；[resolveCover] 是唯一走表的人。
enum CoverSource { manual, custom, crawler, best, first }

const List<CoverSource> kCoverSourceOrder = <CoverSource>[
  CoverSource.manual,
  CoverSource.custom,
  CoverSource.crawler,
  CoverSource.best,
  CoverSource.first,
];

/// 封面解析结果：路径 + 命中来源（都没命中时路径为空、来源为 `first`）。
typedef CoverHit = ({String path, CoverSource source});

/// 按 [kCoverSourceOrder] 取第一个可用候选（**唯一实现**）。
///
/// - [manualUrl]：服务端 `cover.u`（完整媒体路径，路由由调用方按它自己的库段决定）
/// - [rel] + [version] + [ext]：自定义封面文件 `<rel>/_cover/<version>.<ext>`
/// - [crawlerThumb]：爬虫抓到的封面（`cv`）
/// - [bestThumb]：本机播放量最高的作品封面
/// - [firstThumb]：服务端下发的首张作品封面（`fc`）
///
/// 只有图片类路径能当封面（`isCoverImagePath` 已含 heic/avif 等可渲染格式）；
/// 视频路径一律跳过，否则卡片会对着一个永远渲染不出来的 mp4 转圈。
CoverHit resolveCover({
  String manualUrl = '',
  String rel = '',
  String version = '',
  String ext = 'jpg',
  String crawlerThumb = '',
  String bestThumb = '',
  String firstThumb = '',
  bool ignoreManual = false,
  bool ignoreCustom = false,
}) {
  for (final src in kCoverSourceOrder) {
    switch (src) {
      case CoverSource.manual:
        final m = ignoreManual ? '' : manualUrl.trim();
        if (m.isNotEmpty) return (path: m, source: src);
        break;
      case CoverSource.custom:
        final c =
            ignoreCustom ? '' : coverImageRel(rel, version, ext: ext);
        if (c.isNotEmpty) return (path: c, source: src);
        break;
      case CoverSource.crawler:
        final c = crawlerThumb.trim();
        if (isCoverImagePath(c)) return (path: c, source: src);
        break;
      case CoverSource.best:
        final b = bestThumb.trim();
        if (isCoverImagePath(b)) return (path: b, source: src);
        break;
      case CoverSource.first:
        final f = firstThumb.trim();
        if (isCoverImagePath(f)) return (path: f, source: src);
        break;
    }
  }
  return (path: '', source: CoverSource.first);
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
  //
  // 协议相对地址（`//cdn/x.jpg`）同理——旧写法只判了带协议的，于是它被当成
  // 库内相对路径补成 `/media/lib/cdn/x.jpg`，爬虫封面永远 404。判定走
  // `media_path.isNetworkMediaUrl`（绝对 + 协议相对的唯一出口）。
  if (isNetworkMediaUrl(p)) return p;
  // 服务端接口地址（`th` 被扫描器写成 `/api/thumb/<lib>/<id>`）：它不是媒体
  // 文件，套 `/media/<lib>/` 会变成 `/media/lib-019/api/thumb/...`，服务端把
  // `api` 当库内子目录 → 404，卡片就永远只有底色。原样返回，交给
  // `absoluteMediaUrl` 只补服务器前缀。
  if (isApiMediaPath(p)) return p;
  if (isMediaPath(p)) return p;
  // 前缀拼装只有 `media_path.libMediaPrefix` 一处（库段编码也在那里）。
  return libMediaPrefix(lib, p);
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
  // 协议相对地址先按服务器协议补全，再走绝对地址分支（那段负责路径转义）；
  // 否则 `'$b$p'` 会拼出 `http://nas:8090//cdn/x.jpg`。
  final p = resolveProtocolRelative(b, libraryMediaPath(lib, path));
  if (b.isEmpty || p.isEmpty) return '';
  // 绝对地址自带前缀（不补服务器）但**路径部分仍然要转义**：`encodeMediaPath`
  // 对绝对地址一律原样返回是为了避免重复编码，所以这里只把路径段交给它，
  // 再拼回前缀——直接传 `'$b$p'` 会让转义整个跳过。
  //
  // 查询串与片段必须留在路径段之外：外链封面（CDN）的 `?w=480` 是真正的
  // 查询、`#poster` 是真正的片段，整串丢给 `encodeMediaPath` 会被转成
  // `%3Fw=480` /  `%23poster`——服务端收到一个不存在的路径，封面 404。
  //
  // 切分走 `media_path.splitMediaSuffix`（唯一实现）。旧写法在这里自己又写了
  // 一遍「先找 `#` 截断、再在截断结果里找 `?`」，**片段里带 `?`** 时顺序就错了：
  // `http://cdn/x.jpg#f?w=1` 会把 `?w=1` 当成片段的一部分保留，
  // 而 `withImageWidth` 那边对同一段字符的判定是反的——两处对同一个地址给出
  // 两种「查询串在哪」，缩图参数与转义各按各的理解拼。
  if (isAbsoluteMediaUrl(p)) {
    final authorityEnd = p.indexOf('/', p.indexOf('//') + 2);
    if (authorityEnd < 0) return p;
    final head = p.substring(0, authorityEnd);
    final parts = splitMediaSuffix(p.substring(authorityEnd));
    final suffix = parts.query.isEmpty
        ? parts.fragment
        : '?${parts.query}${parts.fragment}';
    return '$head${encodeMediaPath(parts.path)}$suffix';
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
  // 「取库段」只有 `media_path.mediaLibSplitOrNull` 一处实现的本文件不再
  // 自己 `indexOf('/')` + 切片（`Cfg.media` 与 `authorPrefixOfMedia` 也转发它）：
  // 三份里只要有一份对「没有文件段」处理不同，同一份路径就会在封面解析里
  // 认得出库、在媒体拼接里认不出（被再前缀一次 → 404）。
  final parts = mediaLibSplitOrNull(p);
  if (parts == null || parts.rel.isEmpty) return '';
  return parts.lib;
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

/// 基础库封面：按 [kCoverSourceOrder]（自定义 → 爬虫 → 最高播放 → 首张作品）。
///
/// 只保留签名兼容的转发：顺序本体在 [resolveCover]。
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

/// 单元库（上级文件夹）封面：与基础库同一条优先级链。
///
/// 两者只有「为什么 bestThumb 是这一张」不同（单元库是整棵子树合并，
/// 基础库是本库），**取图优先级完全相同**。
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

/// 基础库与单元库共用的取图实现：**转发 [resolveCover]**，不自己写顺序。
///
/// 旧实现里这里自己按「自定义 → `pickCoverPath(爬虫,最高)` → 首张」三步走，
/// 而 `main._basicCoverUrl` / `main._unitCoverUrl` 又各自写了一遍同样的顺序
/// （外加服务端 `cover.u` 那一级），四处各一份——任何一处漏一级，那个入口的
/// 卡片就是灰的。现在顺序只在 [kCoverSourceOrder] 里出现一次。
CoverPick _pickLibCover({
  required String rel,
  String bestThumb = '',
  String firstThumb = '',
  String crawlerThumb = '',
  String version = '',
  String ext = 'jpg',
}) {
  final hit = resolveCover(
    rel: rel,
    version: version,
    ext: ext,
    crawlerThumb: crawlerThumb,
    bestThumb: bestThumb,
    firstThumb: firstThumb,
  );
  if (hit.path.isEmpty) return const CoverPick.none();
  return CoverPick(hit.path, custom: hit.source == CoverSource.custom);
}
