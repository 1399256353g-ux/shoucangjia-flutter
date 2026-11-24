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
bool isApiMediaPath(String path) => path.trim().startsWith('/api/');

String encodeMediaPath(String path) {
  if (path.isEmpty) return path;
  if (isAbsoluteMediaUrl(path)) return path;
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
