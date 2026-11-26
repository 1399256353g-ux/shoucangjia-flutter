import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart'
    show
        Border,
        BorderRadius,
        BoxBorder,
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
        ValueListenableBuilder,
        ValueNotifier,
        Widget;

import 'app_settings.dart';
import 'color_codec.dart';
import 'index_prefix.dart';
import 'unit_fraction.dart';
import 'json_num.dart';
import 'lib_id.dart';
import 'prefs_json.dart';
import 'contrast.dart';

/// 词条层级：**只有三种**（媒体库 / 单元库 / 基础库）。
///
/// owner 2026-11-26：「我总共不就说了 4 种词条吗，没用赶紧删了」——
/// 原来是 top/unit/basic/other 四种，其中 `other`（作者卡等非库语境）没有
/// 任何用户可理解的含义，设置页里那条「其它（作者卡等）」也没人知道在控制
/// 哪里。已删除；没有归属的词条按「单元库」处理，不再单列一档。
///
/// 三种词条**形状与尺寸完全一致**，差异靠边框粗细/颜色与底纹浓度区分。
enum LibEntryKind {
  /// 媒体库（连接的根）：最粗边框 + 最亮边框色 + 最浓底纹。
  top,

  /// 中间层单元库：中等边框。
  unit,

  /// 末梢基础库：最细边框 + 最淡底纹。
  basic,
}

/// 词条圆角：四种层级共用，**不可调**（形状一致是硬约束）。
const double kEntryRadius = 6;

/// P1：单个层级的词条外观（只允许改边框粗细与底纹透明度）。
///
/// 刻意不暴露圆角/内边距/字号：形状与尺寸必须四级一致，
/// 层级差异只体现在边框与底纹上。
class EntryStyle {
  /// 边框粗细（逻辑像素），限制在 0–3。
  final double borderWidth;

  /// 边框不透明度（0–1）。
  final double borderAlpha;

  /// 底纹不透明度（0–1），即词条底色浓度。
  final double fillAlpha;

  /// 边框颜色（ARGB）。owner 2026-11-26：「边框颜色调不了」——此前边框色
  /// 写死在代码里（顶级白、其余黑），用户只能调粗细和透明度，没法调颜色。
  /// 现在可调；null 表示用该层级的默认色。
  final int? borderColor;

  const EntryStyle({
    required this.borderWidth,
    required this.borderAlpha,
    required this.fillAlpha,
    this.borderColor,
  });

  /// 边框粗细（0–3）。非有限值归 0——`NaN.clamp(0,3)` 实测返回 **3.0**，
  /// 会把「值损坏」画成最粗边框。
  static double clampW(double v) =>
      v.isFinite ? v.clamp(0.0, 3.0).toDouble() : 0.0;

  /// 不透明度（0–1），统一走 [unitFraction]。
  static double clampA(double v) => unitFraction(v);

  EntryStyle copyWith(
          {double? borderWidth,
          double? borderAlpha,
          double? fillAlpha,
          int? borderColor,
          bool clearBorderColor = false}) =>
      EntryStyle(
        borderWidth: clampW(borderWidth ?? this.borderWidth),
        borderAlpha: clampA(borderAlpha ?? this.borderAlpha),
        fillAlpha: clampA(fillAlpha ?? this.fillAlpha),
        borderColor:
            clearBorderColor ? null : (borderColor ?? this.borderColor),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'w': borderWidth,
        'ba': borderAlpha,
        'fa': fillAlpha,
        if (borderColor != null) 'bc': borderColor,
      };

  /// 容错解析：缺失或非法字段保留 [fallback] 的对应值。
  static EntryStyle fromJson(Object? v, EntryStyle fallback) {
    if (v is! Map) return fallback;
    final w = doubleOrNull(v['w']);
    final ba = doubleOrNull(v['ba']);
    final fa = doubleOrNull(v['fa']);
    // `bc` 缺失时必须是 fallback 的边框色，不能用 0 当哨兵：合法的黑色
    // 边框也是 0x00000000 之外的值，而「没有 bc 字段」与「bc 写了 0」在
    // intOf 下都得到 0，会把默认白边悄悄变成黑边。
    final hasBc = v.containsKey('bc');
    final bc = hasBc ? intOf(v['bc']) : null;
    return EntryStyle(
      borderWidth: clampW(w ?? fallback.borderWidth),
      borderAlpha: clampA(ba ?? fallback.borderAlpha),
      fillAlpha: clampA(fa ?? fallback.fillAlpha),
      borderColor: (bc == null || bc == 0) ? fallback.borderColor : bc,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EntryStyle &&
      other.borderWidth == borderWidth &&
      other.borderAlpha == borderAlpha &&
      other.fillAlpha == fillAlpha &&
      other.borderColor == borderColor;

  @override
  int get hashCode =>
      Object.hash(borderWidth, borderAlpha, fillAlpha, borderColor);
}

/// 三层级默认外观。
///
/// owner 2026-11-26：「各种词条区分不够明显，改方案」。
///
/// 旧的差异只有 1.2 / 0.8 / 0.5 的边框粗细，三档挤在一起，同屏几乎看不出；
/// 边框色还写死成「顶级白、其余黑」，跟底色接近时等于没有边框。
///
/// 新方案从**三个维度同时拉开**，任一眼都能分：
///  1. 边框粗细：2.0 / 1.3 / 0.8（差一倍以上）
///  2. 边框色：白 / 浅灰 / 极浅灰（与底色形成明确描边，且可自行调色）
///  3. 底纹浓度：0.96 / 0.90 / 0.80（逐级变透）
const Map<LibEntryKind, EntryStyle> kDefaultEntryStyle =
    <LibEntryKind, EntryStyle>{
  LibEntryKind.top: EntryStyle(
      borderWidth: 2.0,
      borderAlpha: 0.95,
      fillAlpha: 0.96,
      borderColor: 0xFFFFFFFF),
  LibEntryKind.unit: EntryStyle(
      borderWidth: 1.3,
      borderAlpha: 0.70,
      fillAlpha: 0.90,
      borderColor: 0xFFE2E8F0),
  LibEntryKind.basic: EntryStyle(
      borderWidth: 0.8,
      borderAlpha: 0.45,
      fillAlpha: 0.80,
      borderColor: 0xFFCBD5E1),
};

/// 库词条（作者卡片左上角）的配色与标签逻辑。
/// 纯函数部分不依赖 UI，便于单元测试；颜色统一用 ARGB int 表示。
/// 词条颜色来源（owner 2026-11-25）。
///
/// 原来「自己没设色」时只有一条路：先继承所属顶级单元库色，顶级设过色就永远
/// 落回同一个颜色——看起来就是「默认被锁死在继承顶级」。
///
/// 现在给出显式选择：
///  - [inheritTop]：继承所属顶级单元库色（旧行为，默认）
///  - [autoAssign]：自动配色，按注册顺序在调色板里依次分配
///  - [fixedCustom]：本层自定义色
enum BadgeColorSource { inheritTop, autoAssign, fixedCustom }

class LibraryBadge {
  static const String prefsKey = 'lib_colors_v1';

  /// 唯一变更信号：任何颜色/外观/emoji 改了都自增一次。
  ///
  /// 词条取值来自静态 Map，卡片建好就不会自己重建；只靠设置页 setState
  /// 只能刷新设置页里的预览，**已显示在作者卡/基础库卡/播放页上的词条
  /// 会停在旧颜色**。组件内部订阅这一个 notifier，改完即刻生效。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bump() => revision.value++;

  /// P1：媒体库词条色。与单元库/基础库的自定义色分开存：
  /// 顶级色是**向下继承**的默认值，单元库/基础库自己设了色才覆盖它。
  static const String topPrefsKey = 'lib_top_colors_v1';

  /// 词条 emoji 后缀（owner 2026-11-17）：每个单元库可选一个 emoji 追加在
  /// 词条名称后，作者卡/排行榜/基础库卡一眼区分。
  static const String emojiPrefsKey = 'lib_badge_emoji_v1';

  /// owner 2026-11-25：「还有默认为什么是继承顶级锁死，好歹给几个选项吧，
  /// 比如自动分配颜色」。
  ///
  /// 原来「自己没设色」时**只有一条路**：先继承所属顶级单元库的色，顶级设过色
  /// 就永远落回同一个颜色——看起来就是「默认被锁死在继承顶级」。
  ///
  /// 现在给出显式来源选择（per-unit，缺省仍是继承顶级以保持既有观感）：
  ///  - [inheritTop]：继承所属顶级单元库色（旧行为，默认）
  ///  - [autoAssign]：自动配色——按注册顺序在调色板里依次分配，同屏易区分
  ///  - [fixedCustom]：自定义色（存在 [custom] 里，等价于以前「设过色」）
  /// 颜色来源偏好：unitId -> 来源。没记录的按 [BadgeColorSource.inheritTop]。
  static final Map<String, String> colorSource = <String, String>{};
  static const String colorSourcePrefsKey = 'lib_badge_color_source_v1';

  /// 基础库的颜色来源单独存：同一个字符串在单元库/基础库两种语境下都可能
  /// 出现，共用一张表会串色（与 [basicCustom] 分开的理由相同）。
  static final Map<String, String> basicSource = <String, String>{};
  static const String basicSourcePrefsKey = 'lib_badge_basic_source_v1';

  static BadgeColorSource _sourceFromWire(String? raw) {
    switch (raw) {
      case 'auto':
        return BadgeColorSource.autoAssign;
      case 'custom':
        return BadgeColorSource.fixedCustom;
      default:
        return BadgeColorSource.inheritTop;
    }
  }

  static String _wireOf(BadgeColorSource src) => switch (src) {
        BadgeColorSource.autoAssign => 'auto',
        BadgeColorSource.fixedCustom => 'custom',
        BadgeColorSource.inheritTop => 'inherit',
      };

  /// 基础库的颜色来源（缺省继承顶级）。
  static BadgeColorSource sourceForBasic(String basicId) {
    if (basicId.isEmpty) return BadgeColorSource.inheritTop;
    return _sourceFromWire(basicSource[basicId]);
  }

  static Future<void> _saveSources() async {
    await savePrefString(
        colorSourcePrefsKey,
        jsonEncode({
          for (final e in colorSource.entries) e.key: e.value,
        }));
    await savePrefString(
        basicSourcePrefsKey,
        jsonEncode({
          for (final e in basicSource.entries) e.key: e.value,
        }));
  }

  /// 某单元库的颜色来源（缺省继承顶级）。
  static BadgeColorSource sourceFor(String unitId) {
    if (unitId.isEmpty) return BadgeColorSource.inheritTop;
    return _sourceFromWire(lookupByLibId(colorSource, unitId));
  }

  /// 设置颜色来源。选 [BadgeColorSource.fixedCustom] 之前应已写入 [custom]；
  /// 切到其它来源时清掉本层自定义色，避免「来源说自动、实际还有残留自定义」。
  static Future<void> setSource(String unitId, BadgeColorSource src,
      {bool basic = false}) async {
    if (unitId.isEmpty) return;
    final table = basic ? basicSource : colorSource;
    removeByLibId(table, unitId);
    table[unitId] = _wireOf(src);
    if (src != BadgeColorSource.fixedCustom) {
      // 来源不是「自定义」时清掉本层自定义色：否则会出现「来源写着自动、
      // 实际还在用残留自定义色」——这正是 owner 说的「恢复自动没反应」。
      //
      // 顶级与普通单元库的自定义色分属两张表；这里两张都清。
      // 不按 [isTopSelf] 分支：结构表没加载时它判不出顶级，旧色就会留着
      // （实测顶级切自动后 child 仍是 `0xFFFF0000`）。多清一次不存在的键
      // 是空操作（[removeByLibId] 只删命中的键）。
      if (basic) {
        removeByLibId(basicCustom, unitId);
      } else {
        removeByLibId(custom, unitId);
        removeByLibId(topCustom, unitId);
      }
    }
    _bump();
    await _saveSources();
  }

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

  /// 媒体库自定义色；topId -> ARGB。
  static final Map<String, int> topCustom = <String, int>{};

  /// P1：基础库（末梢）词条自定义色；basicId -> ARGB。
  /// 与单元库 id 分开存：同一字符串在两种语境下都可能出现，共用会串色。
  static final Map<String, int> basicCustom = <String, int>{};
  static const String basicPrefsKey = 'lib_basic_colors_v1';

  /// P1：层级 → 自定义外观（边框粗细 / 边框透明度 / 底纹浓度）。
  /// 没设过的层级走 [kDefaultEntryStyle]。
  static const String stylePrefsKey = 'lib_entry_style_v1';
  static final Map<LibEntryKind, EntryStyle> entryStyle =
      <LibEntryKind, EntryStyle>{...kDefaultEntryStyle};

  /// 某层级的生效外观（未自定义即为默认）。
  ///
  /// 统一在这里夹紧范围：即使有人直接写 `entryStyle[k] = EntryStyle(...)`
  /// 绕过 copyWith，渲染时也不会出现负边宽或超范围透明度。
  static EntryStyle styleFor(LibEntryKind kind) {
    final s = entryStyle[kind] ?? kDefaultEntryStyle[kind]!;
    // borderColor 必须一起带出来：漏掉它会让 `styleFor == kDefaultEntryStyle`
    // 永远不成立（默认白边被丢成 null），「恢复默认」与「是否自定义」都失灵。
    return EntryStyle(
      borderWidth: EntryStyle.clampW(s.borderWidth),
      borderAlpha: EntryStyle.clampA(s.borderAlpha),
      fillAlpha: EntryStyle.clampA(s.fillAlpha),
      borderColor: s.borderColor,
    );
  }

  /// 设置某层级外观；传 null 恢复该层默认。
  static Future<void> setStyle(LibEntryKind kind, EntryStyle? style) async {
    final next = style ?? kDefaultEntryStyle[kind]!;
    if (entryStyle[kind] == next) return;
    entryStyle[kind] = next;
    _bump();
    await saveStyle();
  }

  static Future<void> resetStyle(LibEntryKind kind) => setStyle(kind, null);

  /// 该层级是否已偏离默认（设置页用来显示「已自定义」）。
  static bool isStyleCustom(LibEntryKind kind) =>
      styleFor(kind) != kDefaultEntryStyle[kind];

  static String encodeStyle() => jsonEncode(<String, dynamic>{
        for (final e in entryStyle.entries) e.key.name: e.value.toJson(),
      });

  static Future<void> saveStyle() => savePrefString(stylePrefsKey, encodeStyle());

  /// 容错读入：任何层级缺失/非法都回落默认，不阻断启动。
  static void applyStyleJson(Object? v) {
    entryStyle
      ..clear()
      ..addAll(kDefaultEntryStyle);
    _bump();
    if (v is! Map) return;
    for (final k in LibEntryKind.values) {
      entryStyle[k] = EntryStyle.fromJson(v[k.name], kDefaultEntryStyle[k]!);
    }
  }

  /// 单元库 → 所属顶级单元库 id。由 `UnitBadgeRegistry.setFrom` 填入，
  /// 只做数据查询，不在这里解析目录名。
  static final Map<String, String> topOfUnit = <String, String>{};

  /// P1：单元库 id → 是否末梢（没有下级单元库）。同样由注册表从树结构填入。
  /// 分发规则：**只有末梢单元库的词条向下分发**给它的基础库/作品/作者；
  /// 非末梢单元库自定义色只作用于自己这一层，不参与分发。
  static final Map<String, bool> leafUnits = <String, bool>{};

  /// 该单元库能否向下分发词条。注册表为空（结构未加载）时不阻断，
  /// 否则冷启动阶段所有词条都会退化成自动色。
  static bool canDistribute(String unitId) {
    if (unitId.isEmpty) return false;
    if (leafUnits.isEmpty) return true;
    return lookupByLibId(leafUnits, unitId) ?? true;
  }

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

  /// 单元库配色：同一单元库在主页（`node:rel`）与 LibMeta（`rel`）里 id
  /// 形式不同，这里统一归一，保证作者词条与基础库卡颜色一致。
  /// [allowCustom] 为 false 时忽略本层自定义色（供「非末梢不下发」的基础库
  /// 落色使用），继承链其余部分不变。
  /// 自动配色：按注册顺序取色，顺序里没有就按 id 稳定散列——同一个库任何时候
  /// 都得到同一个色（不用随机，避免每次重建换个颜色）。
  ///
  /// **绝不读用户自定义表**。0.9.265 修：上一版末尾 `return colorFor(relOf(...))`，
  /// 而 [colorFor] 第一步就是查 `custom`，于是「来源=自动分配」仍可能返回残留
  /// 自定义色（实测 `basicSource=auto` + 单元库 `custom` 有值 → 直接返回旧色）。
  /// 自动色能等于自定义色时，「来源」这个选项就名存实亡：用户选了自动、看到
  /// 的还是自己以前挑的颜色，只会认为开关又没生效。
  static int autoColorOf(String unitId, {List<String> order = const []}) {
    for (final f in idFormsOf(unitId)) {
      final i = order.indexOf(f);
      if (i >= 0) return autoColorAt(i);
    }
    final rel = relOf(unitId);
    var h = 0;
    for (final u in rel.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return autoColorAt(h);
  }

  static int colorForUnit(String unitId,
      {List<String> order = const [], bool allowCustom = true}) {
    if (unitId.isEmpty) return gray;
    // 「secret」（无归属的库根词条）是固定灰，不参与自动配色：
    // 它有 topCustom 覆盖时用覆盖色，否则恒为 gray。
    if (unitId == 'secret') return topColorFor('secret') ?? gray;
    // owner 2026-11-25：按「颜色来源」决定走哪条链，不再写死「先继承顶级」。
    final src = sourceFor(unitId);
    if (src == BadgeColorSource.autoAssign) {
      return autoColorOf(unitId, order: order);
    }
    if (allowCustom) {
      // 本层生效中的自定义色。普通单元库存在 [custom]，顶级单元库存在
      // [topCustom]——此前这里只查 `custom`，于是「顶级选了自定义色」在
      // 卡片上要靠调用方再写一遍 `topColorFor(id) ?? …` 才显示得出来：
      // 两处口径，第二处一定会漏（实测顶级切「自动分配」后仍显示旧色）。
      // 两张表都查不会串色：[topCustom] 只由 [setTopColor] 写入顶级 id。
      final own = lookupByLibId(custom, unitId) ?? topColorFor(unitId);
      if (own != null) return own;
    }
    if (src == BadgeColorSource.fixedCustom) {
      // 声明了自定义但没有值（被清过）：回落到自动配色，不留一个空壳状态。
      return autoColorOf(unitId, order: order);
    }
    // 默认：继承所属顶级单元库的词条色（顶级设过、且它自己没有选「自动分配」）。
    // 自己就是顶级时不存在「继承自己」，直接走自动配色。
    final topId = lookupByLibId(topOfUnit, unitId);
    if (topId != null && relOf(topId) != relOf(unitId)) {
      final inherited = topEntryColor(topId, order: order);
      if (inherited != null) return inherited;
    }
    return autoColorOf(unitId, order: order);
  }

  /// 顶级单元库**实际生效**的词条色；没有可继承色时返回 null。
  ///
  /// 与 [topColorFor] 的区别：后者只读存储，用于设置页判断「设没设过」。
  /// 顶级自己选了「自动分配」时，`topCustom` 里可能还残留旧色（手工改过的
  /// 配置、或从别的入口写的），继承链不能再拿它去染下级——否则用户给顶级
  /// 选了自动、下级却仍是一片旧色，选项形同虚设。
  static int? topEntryColor(String topId, {List<String> order = const []}) {
    if (topId.isEmpty) return null;
    if (sourceFor(topId) == BadgeColorSource.autoAssign) return null;
    return topColorFor(topId);
  }

  /// P1：词条外观。四种层级共用同一圆角与内边距，只改边框与底纹强度，
  /// 因此「形状与尺寸保持一致」由这一个函数保证，调用方不再各写一份。
  ///
  /// 边框粗细与底纹浓度可在「设置 → 自定义 → 库词条配色」里按层级调整；
  /// 圆角与内边距**不可调**，形状尺寸永远一致。
  /// 词条的边框（用 `foregroundDecoration` 叠加，**不占布局**）。
  ///
  /// 返回 null 表示不画（厚度为 0）。
  static BoxBorder? borderFor(LibEntryKind kind) {
    final st = styleFor(kind);
    if (st.borderWidth <= 0) return null;
    final base = Color(st.borderColor ??
        (kDefaultEntryStyle[kind]?.borderColor ?? 0xFF000000));
    return Border.all(
        color: base.withValues(alpha: st.borderAlpha), width: st.borderWidth);
  }

  static BoxDecoration decorationFor(LibEntryKind kind, int argb) {
    final st = styleFor(kind);
    // 边框不在这里画。owner 2026-11-26：「叫你不要动词条占用面积的大小，调粗
    // 边框占用不就变大了吗」——`border:` 会**向内挤占**内容盒，边框一变粗
    // 文字可用宽度就变小，词条看起来被撑大/换行。边框改由 [borderFor]
    // 配合 `foregroundDecoration` 叠加，只改变视觉、**不改变占位**。
    return BoxDecoration(
      color: Color(argb).withValues(alpha: st.fillAlpha),
      borderRadius: BorderRadius.circular(kEntryRadius),
    );
  }

  /// P1：单元库 id → 词条层级（顶级单元库 / 中间单元库 / 其它）。
  ///
  /// 判定只看 [topOfUnit] 这张结构表：一个单元库自己就是顶级单元库时，
  /// 表里会有 `unitId → unitId`；否则它是下级单元库。
  /// 该单元库自己就是「连接的库根」（顶级单元库）。
  ///
  /// 只有这一种情形下，本层自定义色存在 [topCustom] 而不是 [custom]：
  /// 顶级色的读写走的是另一张表。判定必须只有一处——[entryKindOfUnit]、
  /// [colorForUnit]、[setSource] 三处各写一遍之后，必有一处忘记 `rel` 归一，
  /// 于是「顶级切自动」清的是空的 `custom` 表，`topCustom` 里的旧色原样留着。
  static bool isTopSelf(String unitId) {
    if (unitId.isEmpty || unitId == 'secret') return false;
    final top = lookupByLibId(topOfUnit, unitId);
    if (top == null) return false;
    final rel = relOf(unitId);
    return top == unitId || top == rel || relOf(top) == rel;
  }

  static LibEntryKind entryKindOfUnit(String unitId) {
    // owner 2026-11-26：删掉 `other` 后，没有归属的词条按「单元库」画——
    // 它本来就是库级词条，不该单独占一档用户无法理解的层级。
    if (unitId.isEmpty || unitId == 'secret') return LibEntryKind.unit;
    if (lookupByLibId(topOfUnit, unitId) == null) return LibEntryKind.unit;
    return isTopSelf(unitId) ? LibEntryKind.top : LibEntryKind.unit;
  }

  /// 顶级单元库自定义色；没设过返回 null（调用方继续走自动配色/继承链）。
  static int? topColorFor(String topId) {
    if (topId.isEmpty) return null;
    return lookupByLibId(topCustom, topId);
  }

  /// 基础库词条色：自己的自定义色优先，其次继承所属上级单元库 →
  /// 顶级单元库色，最后才是自动配色（顺序不可倒置：越具体越优先）。
  static int basicColorFor(String basicId, String unitId,
      {List<String> order = const []}) {
    final src = sourceForBasic(basicId);
    if (src == BadgeColorSource.autoAssign && basicId.isNotEmpty) {
      return autoColorOf(basicId, order: order);
    }
    if (basicId.isNotEmpty) {
      final c = basicCustom[basicId];
      if (c != null) return c;
    }
    if (src == BadgeColorSource.fixedCustom) {
      return autoColorOf(basicId.isEmpty ? unitId : basicId, order: order);
    }
    // P1 分发规则：上级单元库自定义色只有它是末梢时才分发到这里；
    // 非末梢单元库只影响自己那层，基础库继续继承顶级单元库色。
    if (unitId.isNotEmpty && !canDistribute(unitId)) {
      final topId = lookupByLibId(topOfUnit, unitId);
      final inherited = topId == null ? null : topEntryColor(topId, order: order);
      if (inherited != null) return inherited;
      return colorForUnit(unitId, order: order, allowCustom: false);
    }
    return colorForUnit(unitId, order: order);
  }

  /// 本层是否真有「生效中的」自定义色。
  ///
  /// 判定必须同时看来源：来源是自动分配时，表里即便还留着旧自定义色
  /// （手工改过的配置）也不生效，界面不能报「自定义」。
  /// 顶级单元库的颜色存在另一张表（[topCustom]），这里一并收口，
  /// 调用方不要再各写 `topColorFor(...) ?? ...` / `customColorFor(...)`。
  static bool hasOwnColor(String unitId) {
    if (unitId.isEmpty) return false;
    if (sourceFor(unitId) == BadgeColorSource.autoAssign) return false;
    // 与 [colorForUnit] 同一条读法：两张表都查，不依赖 [topOfUnit] 是否
    // 已由注册表填好（冷启动阶段结构表还是空的）。
    return lookupByLibId(custom, unitId) != null ||
        topColorFor(unitId) != null;
  }

  /// 基础库是否真有生效中的自定义色（来源=自动时不算）。
  static bool hasOwnBasicColor(String basicId) {
    if (basicId.isEmpty) return false;
    if (sourceForBasic(basicId) == BadgeColorSource.autoAssign) return false;
    return basicCustom[basicId] != null;
  }

  /// 本层此刻是否正在继承顶级色（没有本层色，且顶级有可继承色）。
  static bool inheritsTopColor(String unitId, {List<String> order = const []}) {
    if (unitId.isEmpty || hasOwnColor(unitId)) return false;
    final topId = lookupByLibId(topOfUnit, unitId);
    if (topId == null) return false;
    if (relOf(topId) == relOf(unitId)) return false;
    return topEntryColor(topId, order: order) != null;
  }

  /// 设置页「来源」文案的**唯一**出口。
  ///
  /// 三处各写一遍 switch 之后必然分叉：基础库那行写成
  /// `own ? '自定义' : '继承'`，于是「来源=自动分配」被显示成「继承」，
  /// 用户改完看到文案没变，会以为开关没生效。
  /// [hasOwn] 本层真有自定义色；[inherits] 本层当前从顶级继承到了色。
  /// 来源文案：**自动就是自动、继承就是继承**，不许按「当前有没有顶级色」
  /// 把继承说成自动。
  ///
  /// owner 2026-11-26：「自动就是自动，继承就是继承，不要混淆说法，误导用户」。
  /// 原来 `inheritTop` 在顶级没设色时返回「自动分配」——用户选的是「继承」，
  /// 界面却告诉他现在是「自动」，于是他以为自己选的没生效，反复来回改。
  /// 选了继承就显示继承；实际回落由颜色解析链负责，不该改写来源名称。
  static String sourceLabelOf(BadgeColorSource src,
      {required bool hasOwn, required bool inherits}) {
    if (hasOwn) return '自定义';
    switch (src) {
      case BadgeColorSource.autoAssign:
        return '自动分配';
      case BadgeColorSource.fixedCustom:
        // 声明了自定义、但色被清掉：此时真实生效的是自动配色。
        return '自动分配';
      case BadgeColorSource.inheritTop:
        return '继承顶级';
    }
  }

  /// 设置/清除基础库词条色。
  static Future<void> setBasicColor(String basicId, int? argb) async {
    if (basicId.isEmpty) return;
    if (basicCustom[basicId] == argb) return;
    basicCustom.remove(basicId);
    if (argb != null) basicCustom[basicId] = argb;
    _bump();
    await saveBasic();
  }

  static String encodeBasic({Map<String, int>? source}) {
    final src = source ?? basicCustom;
    return jsonEncode({
      for (final e in src.entries) e.key: argbToHex(e.value),
    });
  }

  static Future<void> saveBasic() => savePrefString(basicPrefsKey, encodeBasic());

  /// 设置/清除顶级单元库颜色。清空即撤销该顶级单元库的向下继承。
  static Future<void> setTopColor(String topId, int? argb) async {
    if (topId.isEmpty) return;
    if (topColorFor(topId) == argb) return;
    removeByLibId(topCustom, topId);
    if (argb != null) topCustom[topId] = argb;
    _bump();
    await saveTop();
  }

  static String encodeTop({Map<String, int>? source}) {
    final src = source ?? topCustom;
    return jsonEncode({
      for (final e in src.entries) e.key: argbToHex(e.value),
    });
  }

  static Future<void> saveTop() => savePrefString(topPrefsKey, encodeTop());

  /// 根据底色亮度选择黑/白文字，保证对比度。
  /// 实现只在 [foregroundArgbOn] 一处（角标与本处必须同色）。
  static int textColorOn(int argb) => foregroundArgbOn(argb);

  /// 位置词条统一去掉文件夹名前面的序号：
  /// `(1) 名称` / `（1）名称` / `[1] 名称` / `01. 名称` / `01、名称` → `名称`。
  /// 目录名里的序号只是排序用，不应出现在作者/作品词条上。
  static String stripIndex(String name) {
    if (!AppSettings.stripLibIndex) return name.trim();
    final s = name.trim();
    if (s.isEmpty) return s;
    final out = stripIndexPrefix(s);
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
          final n = argbFromJson(e.value);
          if (n != null) m['${e.key}'] = n;
        }
      }
    } catch (_) {}
    return m;
  }

  /// 单元库的 emoji 后缀：id 形式在主页（`node:rel`）与 LibMeta（`rel`）
  /// 之间不一致，两种形式都查；顶级 SECRET / 空 id 不显示。
  /// 词条 emoji 后缀（**含向下分发**）。
  ///
  /// owner 2026-11-26：「媒体库和基础库词条还没有分发」。
  ///
  /// 实测（探针跑过）：顶级设 `🔥` 后，下级单元库/基础库拿到的都是空串——
  /// 颜色有继承链，emoji 没有。同一层级的两项配置只有一半会分发，用户按
  /// 颜色的行为预期去设 emoji，就会觉得「设了没反应」。
  ///
  /// 现按与颜色完全相同的口径：
  ///  1. 本层设过 → 用自己的；
  ///  2. 本层来源是「自动分配」→ 不继承（用户显式要求不要上级的）；
  ///  3. 否则继承所属顶级单元库的 emoji。
  ///
  /// `secret`（无归属兜底）不参与继承：它不在任何媒体库下面。
  static String emojiFor(String unitId) {
    if (unitId.isEmpty || unitId == 'secret') return '';
    final own = lookupByLibId(emoji, unitId);
    if (own != null && own.isNotEmpty) return own;
    // 显式选了「自动分配」：不继承上级，避免与颜色语义分叉。
    if (sourceFor(unitId) == BadgeColorSource.autoAssign) return '';
    final topId = lookupByLibId(topOfUnit, unitId);
    if (topId == null || relOf(topId) == relOf(unitId)) return '';
    // 顶级自己若选了自动分配，同样不向下传。
    if (sourceFor(topId) == BadgeColorSource.autoAssign) return '';
    return lookupByLibId(emoji, topId) ?? '';
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
      for (final e in src.entries) e.key: argbToHex(e.value),
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
      final rawSrc = sp.getString(colorSourcePrefsKey);
      colorSource.clear();
      if (rawSrc != null && rawSrc.isNotEmpty) {
        try {
          final m = jsonDecode(rawSrc);
          if (m is Map) {
            for (final e in m.entries) {
              colorSource[e.key.toString()] = e.value.toString();
            }
          }
        } catch (_) {}
      }
      final rawBasicSrc = sp.getString(basicSourcePrefsKey);
      basicSource.clear();
      if (rawBasicSrc != null && rawBasicSrc.isNotEmpty) {
        try {
          final m = jsonDecode(rawBasicSrc);
          if (m is Map) {
            for (final e in m.entries) {
              basicSource[e.key.toString()] = e.value.toString();
            }
          }
        } catch (_) {}
      }
      emoji
        ..clear()
        ..addAll(parseEmoji(sp.getString(emojiPrefsKey)));
      // P1：四层级外观（边框粗细/透明度 + 底纹浓度）。
      final rawStyle = sp.getString(stylePrefsKey);
      if (rawStyle != null && rawStyle.isNotEmpty) {
        try {
          applyStyleJson(jsonDecode(rawStyle));
        } catch (_) {
          applyStyleJson(null);
        }
      } else {
        applyStyleJson(null);
      }
    } catch (_) {}
  }

  static Future<void> save() => savePrefString(prefsKey, encode());

  /// 单元库自定义颜色的当前值（`rel` / `node:rel` 两种形式都认）。
  /// 设置页用它判断「自动 / 自定义」，避免只删一种 id 后仍显示自定义色。
  static int? customColorFor(String unitId) {
    if (unitId.isEmpty) return null;
    return lookupByLibId(custom, unitId);
  }

  /// 设置或清除单元库自定义颜色。
  /// 清除时把同一单元库的 `rel` / `node:rel` 两种键一起删掉。
  static Future<void> setColor(String libId, int? argb) async {
    if (libId.isEmpty) return;
    if (customColorFor(libId) == argb) return;
    removeByLibId(custom, libId);
    if (argb != null) custom[libId] = argb;
    _bump();
    await save();
  }

  static Future<void> saveEmoji() => savePrefString(emojiPrefsKey, encodeEmoji());

  /// 设置或清除单元库 emoji 后缀；同一单元库的 `rel` / `node:rel` 形式
  /// 一起清掉，避免两种 id 各留一份导致显示不一致。
  static Future<void> setEmoji(String unitId, String? value) async {
    if (unitId.isEmpty) return;
    final v = sanitizeEmoji(value ?? '');
    if (emojiFor(unitId) == v) return;
    removeByLibId(emoji, unitId);
    if (v.isNotEmpty) emoji[unitId] = v;
    _bump();
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
      this.kind = LibEntryKind.unit});

  @override
  Widget build(BuildContext context) {
    // 订阅唯一变更信号：设置页改了颜色/外观/emoji，所有已显示词条立即跟着变。
    return ValueListenableBuilder<int>(
      valueListenable: LibraryBadge.revision,
      builder: (_, __, ___) => _paint(),
    );
  }

  Widget _paint() {
    // 位置词条自动省略目录名前缀序号（`(1) 名称` → `名称`）。
    final text = label.startsWith('+')
        ? label
        : LibraryBadge.labelWithEmoji(LibraryBadge.stripIndex(label), unitId);
    // 层级差异只由 LibraryBadge 的外观决定（形状/尺寸统一，只改边框底纹）。
    // 边框走 foregroundDecoration：加粗只影响视觉，**不改变词条占位**。
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: LibraryBadge.decorationFor(kind, color),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kEntryRadius),
        border: LibraryBadge.borderFor(kind),
      ),
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
