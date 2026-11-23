import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart'
    show
        Border,
        BorderRadius,
        BoxDecoration,
        BuildContext,
        Color,
        Container,
        EdgeInsets,
        FontWeight,
        StatelessWidget,
        Text,
        TextOverflow,
        TextStyle,
        Widget;

import 'app_settings.dart';

/// P1：词条层级。四种词条**形状与尺寸完全一致**，差异只在边框/底纹，
/// 保证「层级一眼可辨、位置与排版不动」。
enum LibEntryKind {
  /// 顶级节点（连接的媒体库根）：实线粗边框 + 轻微底纹。
  top,

  /// 中间层单元库：实线细边框。
  unit,

  /// 末梢基础库：虚线（用浅色描边模拟）+ 无底纹。
  basic,

  /// 其它（作者卡、非库语境）：无边框。
  other,
}

/// 库词条（作者卡片左上角）的配色与标签逻辑。
/// 纯函数部分不依赖 UI，便于单元测试；颜色统一用 ARGB int 表示。
class LibraryBadge {
  static const String prefsKey = 'lib_colors_v1';

  /// P1：顶级节点（媒体库根）词条色。与单元库/基础库的自定义色分开存：
  /// 顶级色是**向下继承**的默认值，单元库/基础库自己设了色才覆盖它。
  static const String topPrefsKey = 'lib_top_colors_v1';

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

  /// 顶级节点（媒体库根）自定义色；topId -> ARGB。
  static final Map<String, int> topCustom = <String, int>{};

  /// P1：基础库（末梢）词条自定义色；basicId -> ARGB。
  /// 与单元库 id 分开存：同一字符串在两种语境下都可能出现，共用会串色。
  static final Map<String, int> basicCustom = <String, int>{};
  static const String basicPrefsKey = 'lib_basic_colors_v1';

  /// 单元库 → 所属顶级节点 id。由 `UnitBadgeRegistry.setFrom` 填入，
  /// 只做数据查询，不在这里解析目录名。
  static final Map<String, String> topOfUnit = <String, String>{};

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
    if (unitId.isEmpty) return gray;
    if (unitId == 'secret') return topColorFor('secret') ?? gray;
    final rel =
        unitId.startsWith('node:') ? unitId.substring(5) : unitId;
    final prefixed = 'node:$rel';
    final c = custom[unitId] ?? custom[rel] ?? custom[prefixed];
    if (c != null) return c;
    // P1：自己没设色 → 继承所属顶级节点的词条色（顶级设了才有）。
    final topId = topOfUnit[unitId] ?? topOfUnit[rel] ?? topOfUnit[prefixed];
    final inherited = topId == null ? null : topColorFor(topId);
    if (inherited != null) return inherited;
    var i = order.indexOf(unitId);
    if (i < 0) i = order.indexOf(rel);
    if (i < 0) i = order.indexOf(prefixed);
    if (i >= 0) return autoColorAt(i);
    return colorFor(rel, order: order);
  }

  /// P1：词条外观。四种层级共用同一圆角与内边距，只改边框与底纹强度，
  /// 因此「形状与尺寸保持一致」由这一个函数保证，调用方不再各写一份。
  static BoxDecoration decorationFor(LibEntryKind kind, int argb) {
    final (borderColor, borderWidth) = switch (kind) {
      // 顶级节点：亮实线粗边，表示「这是媒体库根」。
      LibEntryKind.top => (const Color(0xD9FFFFFF), 1.2),
      // 单元库：深细边。
      LibEntryKind.unit => (const Color(0x59000000), 0.8),
      // 基础库：极浅边（视觉上最弱）。
      LibEntryKind.basic => (const Color(0x2E000000), 0.5),
      // 其它：中性细边。
      LibEntryKind.other => (const Color(0x40000000), 0.5),
    };
    final fill = switch (kind) {
      LibEntryKind.top => 0.94,
      LibEntryKind.unit => 0.90,
      LibEntryKind.basic => 0.86,
      LibEntryKind.other => 0.92,
    };
    return BoxDecoration(
      color: Color(argb).withValues(alpha: fill),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: borderColor, width: borderWidth),
    );
  }

  /// P1：单元库 id → 词条层级（顶级节点 / 中间单元库 / 其它）。
  ///
  /// 判定只看 [topOfUnit] 这张结构表：一个单元库自己就是顶级节点时，
  /// 表里会有 `unitId → unitId`；否则它是下级单元库。
  static LibEntryKind entryKindOfUnit(String unitId) {
    if (unitId.isEmpty || unitId == 'secret') return LibEntryKind.other;
    final rel = unitId.startsWith('node:') ? unitId.substring(5) : unitId;
    String? top =
        topOfUnit[unitId] ?? topOfUnit[rel] ?? topOfUnit['node:$rel'];
    if (top == null) return LibEntryKind.other;
    final topRel = top.startsWith('node:') ? top.substring(5) : top;
    return (top == unitId || top == rel || topRel == rel)
        ? LibEntryKind.top
        : LibEntryKind.unit;
  }

  /// 顶级节点自定义色；没设过返回 null（调用方继续走自动配色/继承链）。
  static int? topColorFor(String topId) {
    if (topId.isEmpty) return null;
    final rel = topId.startsWith('node:') ? topId.substring(5) : topId;
    return topCustom[topId] ?? topCustom[rel] ?? topCustom['node:$rel'];
  }

  /// 基础库词条色：自己的自定义色优先，其次继承所属上级单元库 →
  /// 顶级节点色，最后才是自动配色（顺序不可倒置：越具体越优先）。
  static int basicColorFor(String basicId, String unitId,
      {List<String> order = const []}) {
    if (basicId.isNotEmpty) {
      final c = basicCustom[basicId];
      if (c != null) return c;
    }
    return colorForUnit(unitId, order: order);
  }

  /// 设置/清除基础库词条色。
  static Future<void> setBasicColor(String basicId, int? argb) async {
    if (basicId.isEmpty) return;
    basicCustom.remove(basicId);
    if (argb != null) basicCustom[basicId] = argb;
    await saveBasic();
  }

  static String encodeBasic({Map<String, int>? source}) {
    final src = source ?? basicCustom;
    return jsonEncode({
      for (final e in src.entries) e.key: e.value.toRadixString(16),
    });
  }

  static Future<void> saveBasic() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(basicPrefsKey, encodeBasic());
    } catch (_) {}
  }

  /// 设置/清除顶级节点颜色。清空即撤销该顶级节点的向下继承。
  static Future<void> setTopColor(String topId, int? argb) async {
    if (topId.isEmpty) return;
    final rel = topId.startsWith('node:') ? topId.substring(5) : topId;
    topCustom
      ..remove(topId)
      ..remove(rel)
      ..remove('node:$rel');
    if (argb != null) topCustom[topId] = argb;
    await saveTop();
  }

  static String encodeTop({Map<String, int>? source}) {
    final src = source ?? topCustom;
    return jsonEncode({
      for (final e in src.entries) e.key: e.value.toRadixString(16),
    });
  }

  static Future<void> saveTop() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(topPrefsKey, encodeTop());
    } catch (_) {}
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
      topCustom
        ..clear()
        ..addAll(parse(sp.getString(topPrefsKey)));
      basicCustom
        ..clear()
        ..addAll(parse(sp.getString(basicPrefsKey)));
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

// 库词条：作者卡片左上角的小标签，颜色按库自动分配（设置里可改）
class LibBadgeChip extends StatelessWidget {
  final String label;
  final int color;

  /// 单元库 id（`rel` 或 `node:rel`）；给出时追加该库 emoji 后缀。
  final String unitId;

  /// P1：词条层级。四种层级共用同一形状/内边距/字号，只改边框与底纹。
  final LibEntryKind kind;

  const LibBadgeChip(
      {super.key,
      required this.label,
      required this.color,
      this.unitId = '',
      this.kind = LibEntryKind.other});

  @override
  Widget build(BuildContext context) {
    // 位置词条自动省略目录名前缀序号（`(1) 名称` → `名称`）。
    final text = label.startsWith('+')
        ? label
        : LibraryBadge.labelWithEmoji(LibraryBadge.stripIndex(label), unitId);
    // 层级差异只由 LibraryBadge.decorationFor 决定（形状/尺寸统一，只改边框底纹）。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: LibraryBadge.decorationFor(kind, color),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: Color(LibraryBadge.textColorOn(color)),
        ),
      ),
    );
  }
}
