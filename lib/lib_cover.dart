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

import 'media_priority.dart';

/// 自定义封面目录名（位于库/单元库文件夹内）。
const String kCoverDir = '_cover';

/// 版本指针文件名（服务端读取其内容得到当前版本号）。
const String kCoverPointerName = 'current';

/// 支持的封面扩展名（按优先级）。
const List<String> kCoverExts = <String>['jpg', 'jpeg', 'png', 'webp'];

/// 版本号合法化：只允许 `[A-Za-z0-9_-]`，拒绝路径分隔符与 `..`。
/// 返回空串表示非法（调用方应回退到下一种封面来源）。
String normalizeCoverVersion(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  // 上级目录穿越一律拒绝（指针只允许是纯版本名）
  if (s.contains('..')) return '';
  // 兼容「_cover/xxx.jpg」这种带目录与扩展名的写法
  s = s.replaceAll('\\', '/');
  final slash = s.lastIndexOf('/');
  if (slash >= 0) s = s.substring(slash + 1);
  final dot = s.lastIndexOf('.');
  if (dot > 0 && kCoverExts.contains(s.substring(dot + 1).toLowerCase())) {
    s = s.substring(0, dot);
  }
  if (s.isEmpty || s == '.') return '';
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s)) return '';
  return s.length > 40 ? s.substring(0, 40) : s;
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

/// 版本指针文件相对路径：`<rel>/_cover/current`。
String coverPointerRel(String rel) => joinRel(coverDirRel(rel), kCoverPointerName);

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
  // `cover: "v1.png"`：扩展名取自字符串本身
  if (raw is String && e == 'jpg') {
    final dot = raw.trim().lastIndexOf('.');
    if (dot > 0) {
      final tail = raw.trim().substring(dot + 1).toLowerCase();
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
  if (p.startsWith('/media/')) return p;
  final l = lib.trim();
  final rest = p.replaceFirst(RegExp(r'^/+'), '');
  if (l.isEmpty) return '/media/$rest';
  return '/media/${Uri.encodeComponent(l)}/$rest';
}

/// 媒体绝对地址：`<base>/media/<lib>/<相对路径>`。
/// [base] 为空时返回空串（调用方回退默认图）。
String absoluteMediaUrl(
  String base, {
  required String lib,
  required String path,
}) {
  final b = base.trim().replaceFirst(RegExp(r'/+$'), '');
  final p = libraryMediaPath(lib, path);
  if (b.isEmpty || p.isEmpty) return '';
  return '$b$p';
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
  return u.startsWith('/media/') ? u : '';
}

/// 媒体路径里的库 id：`/media/lib-008/a/b.jpg` → `lib-008`；不是媒体路径返回空串。
/// 用于把「单元库封面」按其所归属的基础库路由到对应服务器。
String libOfMediaPath(String p) {
  final path = p.trim();
  if (!path.startsWith('/media/')) return '';
  final rest = path.substring(7);
  final at = rest.indexOf('/');
  if (at <= 0) return '';
  return rest.substring(0, at);
}

/// 封面必须是图片：视频文件（mp4/mov…）当封面会一直渲染失败。
const List<String> kCoverImageExts = <String>[
  '.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic'
];

bool isCoverImagePath(String p) {
  final l = p.trim().toLowerCase();
  if (l.isEmpty) return false;
  final q = l.split('?').first;
  for (final e in kCoverImageExts) {
    if (q.endsWith(e)) return true;
  }
  return false;
}

/// 第一张作品的封面路径（无播放数据时的兜底，纯函数）：
/// 优先作品 `th` 缩略图，否则取 `m` 里第一张图片；都没有返回空串。
String firstWorkCoverPath(List<dynamic> works) {
  const imageExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
  for (final w in works) {
    if (w is! Map) continue;
    final th = '${w['th'] ?? ''}'.trim();
    if (th.isNotEmpty) return th;
    final m = w['m'];
    if (m is List) {
      for (final e in m) {
        final p = '${e ?? ''}'.trim();
        if (p.isEmpty) continue;
        final low = p.toLowerCase();
        if (imageExts.any(low.endsWith)) return p;
      }
    }
  }
  return '';
}

/// 基础库封面：
///  - 有自定义版本 → `_cover/<version>.<ext>`；
///  - 否则取本机播放量最高的作品缩略图（[bestThumb]，由 WorkPlaysStore 提供）；
///  - 都没有 → 空（显示默认图）。
CoverPick pickBasicCover({
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
  // 无播放数据时的兜底：第一张作品的封面（仅图片）。
  final fb = firstThumb.trim();
  if (fb.isNotEmpty && !isCoverImagePath(fb)) return const CoverPick.none();
  if (fb.isNotEmpty) return CoverPick(fb);
  return const CoverPick.none();
}

/// 单元库（上级文件夹）封面：
///  - 有自定义版本 → `_cover/<version>.<ext>`；
///  - 否则取子树内本机播放量最高的作品缩略图（[bestThumb]，整棵子树合并）；
///  - 都没有 → 空（显示默认图）。
CoverPick pickUnitCover({
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
  // 无播放数据时的兜底：第一张作品的封面（仅图片）。
  final fb = firstThumb.trim();
  if (fb.isNotEmpty && !isCoverImagePath(fb)) return const CoverPick.none();
  if (fb.isNotEmpty) return CoverPick(fb);
  return const CoverPick.none();
}
