/// L5-C 封面规则（纯函数，便于单测）。
///
/// 取图优先级（高 → 低）：
///  1. 文件夹自定义封面：`_cover/<version>.<ext>`（版本指针由服务端扫描写入
///     `libraries.json` 的 `cover` / `cover_ext`；只新增文件、不改旧文件，
///     旧图因此全部保留，回滚只需把指针改回旧版本）。
///  2. 基础库：本机「App 本地播放量最高」且带缩略图的作品封面。
///  3. 单元库（上级文件夹）：默认图（文件夹图标），不借用作品封面。
///
/// 本文件不碰网络与文件系统，只做「该用哪张图」的判定。
library;

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
  // 兼容「_cover/xxx.jpg」这种带目录与扩展名的写法
  s = s.replaceAll('\\', '/');
  final slash = s.lastIndexOf('/');
  if (slash >= 0) s = s.substring(slash + 1);
  final dot = s.lastIndexOf('.');
  if (dot > 0 && kCoverExts.contains(s.substring(dot + 1).toLowerCase())) {
    s = s.substring(0, dot);
  }
  if (s.isEmpty || s == '.' || s == '..' || s.contains('..')) return '';
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

/// 基础库封面：
///  - 有自定义版本 → `_cover/<version>.<ext>`；
///  - 否则取本机播放量最高的作品缩略图（[bestThumb]，由 WorkPlaysStore 提供）；
///  - 都没有 → 空（显示默认图）。
CoverPick pickBasicCover({
  required String rel,
  String bestThumb = '',
  String version = '',
  String ext = 'jpg',
}) {
  final custom = coverImageRel(rel, version, ext: ext);
  if (custom.isNotEmpty) return CoverPick(custom, custom: true);
  final th = bestThumb.trim();
  if (th.isNotEmpty) return CoverPick(th);
  return const CoverPick.none();
}

/// 单元库（上级文件夹）封面：只用自定义封面，否则默认图。
CoverPick pickUnitCover({
  required String rel,
  String version = '',
  String ext = 'jpg',
}) {
  final custom = coverImageRel(rel, version, ext: ext);
  return custom.isEmpty ? const CoverPick.none() : CoverPick(custom, custom: true);
}
