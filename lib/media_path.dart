/// 媒体路径转义（**单一实现**）。
///
/// NAS 上的文件名可能带 `#`、`?` 或空格（如 `1#花絮.mp4`），直接拼进 URL 后
/// `Uri.parse` 会把 `#` 之后当 fragment、`?` 之后当 query，请求到的是另一个
/// 路径，表现为封面 404 / 播放失败。
///
/// 规则：
/// - 已有合法 `%XX` 原样保留，避免二次编码（`%25`）；
/// - 孤立 `%`（后面不是两位十六进制）转成 `%25`；
/// - `#`、`?`、空格、控制字符转义成 `%XX`；
/// - 其余字符（含中文、`/` 分段符）不动，交给 Uri 自己编码。
///
/// 0.9.231：这条规则此前只被 `Cfg.mediaUrl`（main.dart）用，而
/// `lib_cover.absoluteMediaUrl`（单元库卡片 / 基础库卡片的封面主路径）
/// 直接 `'$base$path'` 拼——同一个带 `#` 的文件名，走作品列表能播，
/// 走库卡片就 404。两份实现只差「有没有转义」，所以转义本身单独成模块，
/// 任何拼媒体地址的地方都必须经过它。
library;

/// 绝对 `http(s)` 地址？是则调用方不应再补服务器前缀。
bool isAbsoluteMediaUrl(String path) {
  final p = path.trim();
  return p.startsWith('http://') || p.startsWith('https://');
}

/// 服务端**接口**地址（`/api/thumb/<lib>/<id>` 等），不是媒体文件。
///
/// 扫描器会把这类地址写进作品的 `th`/`fc`，若再套 `/media/<lib>/` 就变成
/// `/media/<lib>/api/thumb/...`——服务端把 `api` 当库内子目录，必然 404。
/// 实测 2026-11-23：2288 条图文作品的 `th` 就是这种接口地址。
bool isApiMediaPath(String path) => path.trim().startsWith('/api/');

/// 已经是 `/media/` 起头的库内媒体路径？
///
/// **唯一定义**。此前这条判定在 6 处各写一遍
/// （`lib_cover.coverUrlOf` / `nodesFromMarks` / `cover_history` /
/// `unit_library` / `cover_upload` / `source_lib`），都是裸
/// `startsWith('/media/')`：哪天服务端把前缀改成 `/m/` 或加上域名，
/// 六处得同时改，漏一处就是「封面/头像/节点封面一半显示一半空」。
bool isMediaPath(String path) => path.trim().startsWith('/media/');

/// 百分号解码，非法编码原样返回（**唯一实现**）。
///
/// 媒体路径的库段与 `.avatars` 文件名都可能是百分号编码的，而文件名本身
/// 可以含孤立 `%`（如 `100%成品.jpg` 被拼进路径后仍是裸 `%`）。
/// `Uri.decodeComponent` 遇到非法编码直接抛 `ArgumentError`：
/// `libOfMediaPath` 早有 try 保护，`serverAvatarFileFromPath` 没有——
/// 点一次这种头像就在 UI 回调里抛异常。规则只允许有一份。
String decodeComponentOrRaw(String s) {
  if (s.isEmpty || !s.contains('%')) return s;
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

/// 媒体路径是否指向视频文件（按扩展名，忽略查询串与片段）。
///
/// **唯一定义**：此前 `work_cover.isVideoPath` 与 `work_forms.chapterIsImage`
/// 各写了一份视频扩展名清单，两份的成员不同（后者少了 mkv/avi）——
/// 同一个 `.mkv` 章节在「封面选取」里算视频、在「合集章节排序」里算图片，
/// 会被排到图片章节末尾。视频格式只在这里列一次。
const List<String> kVideoExts = <String>[
  '.mp4',
  '.mov',
  '.m4v',
  '.webm',
  '.mkv',
  '.avi',
];

bool isVideoMediaPath(String p) {
  var l = p.trim().toLowerCase();
  if (l.isEmpty) return false;
  final q = l.indexOf('?');
  if (q >= 0) l = l.substring(0, q);
  final h = l.indexOf('#');
  if (h >= 0) l = l.substring(0, h);
  for (final ext in kVideoExts) {
    if (l.endsWith(ext)) return true;
  }
  return false;
}

String encodeMediaPath(String path) {
  if (path.isEmpty) return path;
  if (isAbsoluteMediaUrl(path)) return path;
  // 接口地址（`/api/thumb/<lib>/<id>`）不是媒体文件：它自带的 `?v=` 是
  // 抽帧版本参数，把 `?` 转义成 `%3F` 会让服务端收到一个不存在的路径。
  if (isApiMediaPath(path)) return path;
  final hex2 = RegExp(r'^[0-9A-Fa-f]{2}$');
  final out = StringBuffer();
  for (var i = 0; i < path.length; i++) {
    final ch = path[i];
    if (ch == '%') {
      final hex = i + 2 < path.length ? path.substring(i + 1, i + 3) : '';
      if (hex2.hasMatch(hex)) {
        out.write(path.substring(i, i + 3));
        i += 2;
      } else {
        out.write('%25');
      }
      continue;
    }
    final code = ch.codeUnitAt(0);
    if (ch == '#' || ch == '?' || ch == ' ' || ch == '\u007f' || code < 0x20) {
      out.write(Uri.encodeComponent(ch));
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}
