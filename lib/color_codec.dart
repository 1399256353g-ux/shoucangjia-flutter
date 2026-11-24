/// 颜色序列化的唯一实现：`0xAARRGGBB` ⇄ 字符串 / JSON 数值（第十四批）。
///
/// 此前这组编解码被写了两次（`LibraryBadge.parse` / `encode` 与
/// `LibraryCornerBadge.applyJson` / `toJson`），两份都只是「够用」：
///
/// * 写入恒为 `value.toRadixString(16)`（8 位，含 alpha）；
/// * 读入恒为 `0xFF000000 | (n & 0xFFFFFF)`——**把已有 alpha 抹掉**；
/// * `#abc` 这种三位简写在两份实现里都被读成 `0xFF000ABC`（应为 `0xFFAABBCC`）。
///
/// 目前 owner 选的颜色都是不透明的，所以没炸；但「存 8 位、读只认 6 位」
/// 本身是同一件事的两种口径，改一处忘一处就会变成角标与词条不同色。
library;

import 'json_num.dart';

/// 解析 `#rgb` / `#rrggbb` / `#aarrggbb`（`#` 可省，大小写不限）。
/// 非法输入返回 null，由调用方保留旧值（不抛异常、不写半截）。
int? argbFromHex(String raw) {
  var s = raw.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
  if (s.isEmpty || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) return null;
  switch (s.length) {
    case 3: // #rgb → #rrggbb
      final r = s[0], g = s[1], b = s[2];
      s = '$r$r$g$g$b$b';
      break;
    case 6: // rrggbb → 不透明（下方统一补 ff）
    case 8: // aarrggbb
      break;
    default:
      return null;
  }
  // 三位已展开成六位；六位与八位都在这里统一按「六位补 ff」处理。
  final n = int.tryParse(s.length == 6 ? 'ff$s' : s, radix: 16);
  if (n == null) return null;
  return n & 0xFFFFFFFF;
}

/// JSON 值 → ARGB：数值直接用（越界/非有限值视为无效），字符串走 [argbFromHex]。
int? argbFromJson(Object? v) {
  if (v is num) {
    final n = intOrNull(v);
    if (n == null) return null;
    return (n >= 0 && n <= 0xFFFFFFFF) ? n : null;
  }
  if (v is String) return argbFromHex(v);
  return null;
}

/// ARGB → 8 位小写十六进制（不补 `0x`），供 prefs/JSON 存储使用。
String argbToHex(int argb) =>
    (argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
