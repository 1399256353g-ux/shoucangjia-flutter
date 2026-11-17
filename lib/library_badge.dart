import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// 库词条（作者卡片左上角）的配色与标签逻辑。
/// 纯函数部分不依赖 UI，便于单元测试；颜色统一用 ARGB int 表示。
class LibraryBadge {
  static const String prefsKey = 'lib_colors_v1';

  /// 词条 emoji 后缀（owner 2026-11-17）：每个单元库可选一个 emoji 追加在
  /// 词条名称后，作者卡/排行榜/基础库卡一眼区分。
  static const String emojiPrefsKey = 'lib_badge_emoji_v1';

  /// 顶级单元库（SECRET）与无归属词条的固定灰色。
  static const int gray = 0xFF6B7280;

  /// 自动配色调色板：按库注册顺序依次分配，保证同屏库颜色区分明显。
  static const List<int> palette = <int>[
    0xFF2563EB, // 蓝
    0xFF16A34A, // 绿
    0xFFF59E0B, // 橙
    0xFFDC2626, // 红
    0xFF7C3AED, // 紫
    0xFF0891B2, // 青
    0xFFDB2777, // 玫红
    0xFF65A30D, // 橄榄
    0xFFEA580C, // 深橙
    0xFF0D9488, // 蓝绿
    0xFF9333EA, // 紫罗兰
    0xFF475569, // 石板灰
  ];

  /// 用户在设置里为某个库自定义的颜色；id -> ARGB。
  static final Map<String, int> custom = <String, int>{};

  /// 用户在设置里为某个库选择的 emoji 后缀；id -> emoji（最多 8 个字符）。
  static final Map<String, String> emoji = <String, String>{};

  /// 词条 emoji 可选集合（设置页一键选择，也允许键盘输入其它 emoji）。
  static const List<String> emojiChoices = <String>[
    // 常用 / 标记
    '🔥', '⭐', '🌟', '✨', '💧', '💎', '🎯', '✅', '❗', '❓',
    // 媒体
    '🎬', '📷', '🎞️', '📺', '🎧', '🎵', '🎮', '🖼️',
    // 自然 / 动物
    '🌟', '🌙', '☀️', '🌈', '🍀', '🌊', '🌸', '🍁', '🐾', '🐱', '🐶', '🦋',
    // 物件 / 情绪
    '🎁', '🍭', '🍓', '☕', '🧿', '🪩', '🕯️', '🔮', '💡', '📌', '🧩', '🛡️',
    // 人物 / 手势
    '😀', '😎', '🥳', '😍', '🤍', '❤️', '💙', '💜', '👍', '👀', '🙌', '👑',
    // 其他常用
    '🦶', '🐻', '🦊', '🐼', '🍺', '🍷', '🧊', '🚀', '🏆', '🎨', '📚', '🗂️',
  ];

  static int autoColorAt(int index) {
    if (palette.isEmpty) return 0xFF6B7280;
    final i = (index % palette.length + palette.length) % palette.length;
    return palette[i];
  }

  /// 库词条颜色：自定义优先，其次按库注册顺序，最后按 id 稳定散列。
  static int colorFor(String libId, {List<String> order = const []}) {
    final c = custom[libId];
    if (c != null) return c;
    if (libId.isEmpty) return gray;
    final i = order.indexOf(libId);
    if (i >= 0) return autoColorAt(i);
    var h = 0;
    for (final u in libId.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return autoColorAt(h);
  }

  /// 单元库词条颜色：顶级 SECRET / 空 id 固定灰色，其余按库配色。
  static int unitColor(String unitId, {List<String> order = const []}) {
    return colorForUnit(unitId, order: order);
  }

  /// 单元库配色：同一单元库在主页（`node:rel`）与 LibMeta（`rel`）里 id
  /// 形式不同，这里统一归一，保证作者词条与基础库卡颜色一致。
  static int colorForUnit(String unitId, {List<String> order = const []}) {
    if (unitId.isEmpty || unitId == 'secret') return gray;
    final rel =
        unitId.startsWith('node:') ? unitId.substring(5) : unitId;
    final prefixed = 'node:$rel';
    final c = custom[unitId] ?? custom[rel] ?? custom[prefixed];
    if (c != null) return c;
    var i = order.indexOf(unitId);
    if (i < 0) i = order.indexOf(rel);
    if (i < 0) i = order.indexOf(prefixed);
    if (i >= 0) return autoColorAt(i);
    return colorFor(rel, order: order);
  }

  /// 根据底色亮度选择黑/白文字，保证对比度。
  static int textColorOn(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    return lum > 0.62 ? 0xFF111827 : 0xFFFFFFFF;
  }

  /// 位置词条统一去掉文件夹名前面的序号：
  /// `(1) 名称` / `（1）名称` / `[1] 名称` / `01. 名称` / `01、名称` → `名称`。
  /// 目录名里的序号只是排序用，不应出现在作者/作品词条上。
  static String stripIndex(String name) {
    if (!AppSettings.stripLibIndex) return name.trim();
    var s = name.trim();
    if (s.isEmpty) return s;
    final bracket = RegExp(r'^[(（\[【]\s*\d{1,4}\s*[)）\]】]\s*[._\-·]?\s*');
    var out = s.replaceFirst(bracket, '').trim();
    if (out != s && out.isNotEmpty) return out;
    final dotted = RegExp(r'^\d{1,4}\s*[.、]\s*');
    out = s.replaceFirst(dotted, '').trim();
    return out.isEmpty ? s : out;
  }

  /// 卡片上最多展示 [max] 个库词条，多余的折叠为「+N」。
  static List<String> labels(List<String> libIds,
      {int max = 2, Map<String, String> names = const {}}) {
    final seen = <String>{};
    final ids = <String>[];
    for (final id in libIds) {
      if (id.isEmpty || !seen.add(id)) continue;
      ids.add(id);
    }
    final out = <String>[];
    for (var i = 0; i < ids.length && i < max; i++) {
      final name = names[ids[i]] ?? '';
      out.add(stripIndex(name.isEmpty ? ids[i] : name));
    }
    if (ids.length > max) out.add('+${ids.length - max}');
    return out;
  }

  static Map<String, int> parse(String? raw) {
    final m = <String, int>{};
    if (raw == null || raw.isEmpty) return m;
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        for (final e in j.entries) {
          final v = e.value;
          if (v is int && v >= 0 && v <= 0xFFFFFFFF) {
            m['${e.key}'] = v;
          } else if (v is String) {
            final p = int.tryParse(v.replaceFirst('#', ''), radix: 16);
            if (p != null) m['${e.key}'] = 0xFF000000 | (p & 0xFFFFFF);
          }
        }
      }
    } catch (_) {}
    return m;
  }

  /// 单元库的 emoji 后缀：id 形式在主页（`node:rel`）与 LibMeta（`rel`）
  /// 之间不一致，两种形式都查；顶级 SECRET / 空 id 不显示。
  static String emojiFor(String unitId) {
    if (unitId.isEmpty || unitId == 'secret') return '';
    final rel = unitId.startsWith('node:') ? unitId.substring(5) : unitId;
    return emoji[unitId] ?? emoji[rel] ?? emoji['node:$rel'] ?? '';
  }

  /// 词条展示文字：去序号后的名称 + 该库 emoji 后缀。
  static String labelWithEmoji(String label, String unitId) {
    if (label.isEmpty || label.startsWith('+')) return label;
    final e = emojiFor(unitId);
    return e.isEmpty ? label : '$label$e';
  }

  /// 清洗用户输入的 emoji 后缀：去空白/控制字符，最多 8 个 UTF-16 单元。
  static String sanitizeEmoji(String raw) {
    final s = raw.replaceAll(RegExp(r'\s'), '');
    final buf = StringBuffer();
    var units = 0;
    for (final r in s.runes) {
      final w = r > 0xFFFF ? 2 : 1;
      if (units + w > 8) break;
      buf.writeCharCode(r);
      units += w;
    }
    return buf.toString();
  }

  static Map<String, String> parseEmoji(String? raw) {
    final m = <String, String>{};
    if (raw == null || raw.isEmpty) return m;
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        for (final e in j.entries) {
          final v = e.value;
          if (v is String) {
            final s = sanitizeEmoji(v);
            if (s.isNotEmpty) m['${e.key}'] = s;
          }
        }
      }
    } catch (_) {}
    return m;
  }

  static String encodeEmoji({Map<String, String>? source}) {
    final src = source ?? emoji;
    return jsonEncode({for (final e in src.entries) e.key: e.value});
  }

  static String encode({Map<String, int>? source}) {
    final src = source ?? custom;
    return jsonEncode({
      for (final e in src.entries) e.key: e.value.toRadixString(16),
    });
  }

  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      custom
        ..clear()
        ..addAll(parse(sp.getString(prefsKey)));
      emoji
        ..clear()
        ..addAll(parseEmoji(sp.getString(emojiPrefsKey)));
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(prefsKey, encode());
    } catch (_) {}
  }

  /// 单元库自定义颜色的当前值（`rel` / `node:rel` 两种形式都认）。
  /// 设置页用它判断「自动 / 自定义」，避免只删一种 id 后仍显示自定义色。
  static int? customColorFor(String unitId) {
    if (unitId.isEmpty) return null;
    final rel = unitId.startsWith('node:') ? unitId.substring(5) : unitId;
    return custom[unitId] ?? custom[rel] ?? custom['node:$rel'];
  }

  /// 设置或清除单元库自定义颜色。
  /// 清除时把同一单元库的 `rel` / `node:rel` 两种键一起删掉。
  static Future<void> setColor(String libId, int? argb) async {
    if (libId.isEmpty) return;
    final rel = libId.startsWith('node:') ? libId.substring(5) : libId;
    custom
      ..remove(libId)
      ..remove(rel)
      ..remove('node:$rel');
    if (argb != null) custom[libId] = argb;
    await save();
  }

  static Future<void> saveEmoji() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(emojiPrefsKey, encodeEmoji());
    } catch (_) {}
  }

  /// 设置或清除单元库 emoji 后缀；同一单元库的 `rel` / `node:rel` 形式
  /// 一起清掉，避免两种 id 各留一份导致显示不一致。
  static Future<void> setEmoji(String unitId, String? value) async {
    if (unitId.isEmpty) return;
    final rel = unitId.startsWith('node:') ? unitId.substring(5) : unitId;
    emoji
      ..remove(unitId)
      ..remove(rel)
      ..remove('node:$rel');
    final v = sanitizeEmoji(value ?? '');
    if (v.isNotEmpty) emoji[unitId] = v;
    await saveEmoji();
  }
}
