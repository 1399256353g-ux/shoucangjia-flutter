import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart'
    show
        Border,
        BorderRadius,
        BoxConstraints,
        BoxDecoration,
        BuildContext,
        Color,
        ConstrainedBox,
        Container,
        EdgeInsets,
        FontWeight,
        StatelessWidget,
        Text,
        TextAlign,
        TextOverflow,
        TextStyle,
        ValueListenableBuilder,
        ValueNotifier,
        Widget;

import 'app_settings.dart';
import 'color_codec.dart';
import 'index_prefix.dart';
import 'label_fallback.dart';
import 'unit_fraction.dart';
import 'json_num.dart';
import 'lib_id.dart';
import 'prefs_json.dart';
import 'contrast.dart';

/// 词条种类：**四种**（媒体库 / 单元库 / 基础库 / 作者）。
///
/// PROJECT_RULES §2.1（owner 原话）：「词条共四种：媒体库 / 单元库 /
/// 基础库 / 作者」。
///
/// 历史上这里是 top/unit/basic/other 四种，其中 `other`（「其它（作者卡等）」）
/// 是**无人使用的多余档**——没有任何页面会把词条画成它，设置页那一行也没人
/// 知道在控制哪里，已删除且不得复活。删掉它之后作者词条一直借用 `unit` 的
/// 外观：等级词条与单元库词条边框/底纹完全相同，于是「四种词条差异化」在
/// 作者这一档上根本没落地（owner 提的第四种词条在界面上不存在）。
///
/// 现在第四档是 **author**（作者等级词条），不是那个被删掉的 `other`：
/// 它有明确的控制对象（作者卡上那一枚等级词条），有独立外观，可单独恢复默认。
///
/// 四种词条**形状与尺寸完全一致**，差异只靠边框粗细/颜色与底纹浓度区分。
enum LibEntryKind {
  /// 媒体库（连接的根）：最粗边框 + 最亮边框色 + 最浓底纹。
  top,

  /// 中间层单元库：中等边框。
  unit,

  /// 末梢基础库：最细边框 + 最淡底纹。
  basic,

  /// 作者（等级词条）：挂在作者卡/播放页信息区的 D–S 那一枚。
  author,
}

/// 词条圆角：三种层级共用，**不可调**（形状一致是硬约束）。
const double kEntryRadius = 6;

/// 单个词条最大宽度（逻辑像素）。超出省略，不撑满信息区。
const double kBadgeChipMaxWidth = 120;

/// P1：单个层级的词条外观（只允许改边框粗细与底纹透明度）。
///
/// 刻意不暴露圆角/内边距/字号：形状与尺寸必须三级一致，
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
  // 2026-11-27 事故复盘：上一版把这里从 1.2/0.8/0.5 改成 2.0/1.3/0.8，
  // 还把单元库/基础库的边框色从黑改成浅灰 —— 浅灰压在浅底纹上几乎看不见，
  // 词条发虚、层级也分不出来。默认值恢复到 owner 认可的原观感。
  LibEntryKind.top: EntryStyle(
      borderWidth: 1.2,
      borderAlpha: 0.85,
      fillAlpha: 0.94,
      borderColor: 0xFFFFFFFF),
  LibEntryKind.unit: EntryStyle(
      borderWidth: 0.8,
      borderAlpha: 0.35,
      fillAlpha: 0.90,
      borderColor: 0xFF000000),
  LibEntryKind.basic: EntryStyle(
      borderWidth: 0.5,
      borderAlpha: 0.18,
      fillAlpha: 0.86,
      borderColor: 0xFF000000),
  // 作者词条要能在同一排里与「基础库」分开，又不能抢过单元库/媒体库：
  // 边宽取 0.65（介于 0.8 与 0.5 之间），底纹 0.88（介于 0.90 与 0.86 之间）。
  // 形状/圆角/内边距/字号与其他三档完全相同（形状一致是硬约束）。
  LibEntryKind.author: EntryStyle(
      borderWidth: 0.65,
      borderAlpha: 0.26,
      fillAlpha: 0.88,
      borderColor: 0xFF000000),
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
    // 读端与写端同一条规则：写端用 `removeByLibId` 删掉 `b` / `node:b`
    // 两种等价键，读端原样按下标查就会「设置页写着自动、卡片还是旧色」。
    return _sourceFromWire(lookupByLibId(basicSource, basicId));
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

  static Future<void> saveStyle() =>
      savePrefString(stylePrefsKey, encodeStyle());

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

  /// 单元库 → **直接上级**单元库。分发链逐级上行要靠它（`topOfUnit` 只到根）。
  ///
  /// owner 2026-11-27：「上级结构生成的词条要分发给下级啊」——中间层单元库
  /// 设的色此前无处可传：查询方只能一下跳到媒体库根，中间那层被跳过。
  static final Map<String, String> parentOfUnit = <String, String>{};

  /// 用户在设置里为某个库选择的 emoji 后缀；id -> emoji（最多 8 个字符）。
  static final Map<String, String> emoji = <String, String>{};

  /// 词条 emoji 可选集合（设置页一键选择，也允许键盘输入其它 emoji）。
  static const List<String> emojiChoices = <String>[
    // 常用 / 标记
    '🔥', '⭐', '🌟', '✨', '💧', '💎', '🎯', '✅', '❗', '❓',
    // 媒体
    '🎬', '📷', '🎞️', '📺', '🎧', '🎵', '🎮', '🖼️',
    // 自然 / 动物
    '🌻', '🌙', '☀️', '🌈', '🍀', '🌊', '🌸', '🍁', '🐾', '🐱', '🐶', '🦋',
    // 物件 / 情绪
    '🎁', '🍭', '🍓', '☕', '🧿', '🪩', '🕯️', '🔮', '💡', '📌', '🧩', '🛡️',
    // 人物 / 手势
    '😀', '😎', '🥳', '😍', '🤍', '❤️', '💙', '💜', '👍', '👀', '🙌', '👑',
    // 其他常用
    '🦶', '🐻', '🦊', '🐼', '🍺', '🍷', '🧊', '🚀', '🏆', '🎨', '📚', '🗂️',
  ];

  /// [emojiChoices] 的唯一性不变式：选择器按列表顺序铺格子，重复项会让
  /// 同一图案相邻出现两次，用户点哪一格都「没反应」（其实已经选中了同样
  /// 的后缀）。0.9.336 之前 `🌟` 就是这样出现了两次（66 项 / 65 个唯一值）。
  ///
  /// 这里只提供判定，**不做静默去重**：悄悄丢掉重复项会让「又加了一个重复」
  /// 在界面上看不出来；契约测试直接拿它断言，重复即红。
  static bool get emojiChoicesAreUnique =>
      emojiChoices.toSet().length == emojiChoices.length;

  static int autoColorAt(int index) {
    if (palette.isEmpty) return 0xFF6B7280;
    final i = (index % palette.length + palette.length) % palette.length;
    return palette[i];
  }

  // 0.9.346：`colorFor(libId)` 已删。它是**第三个取色入口**，而且只挂在
  // 测试上（`lib/` 零调用）：真实渲染全部走 `colorForUnit` /
  // `basicColorFor` / `autoColorOf`。留着它的坏处不是“多一个函数”，而是
  // 它第一步就查 `custom`——即 0.9.265 从 `autoColorOf` 里特意删掉的
  // 「自动配色读到残留自定义色」那条路径。测试拿它当“自动色基准”时，
  // 只要 `custom` 里还有旧值，断言就会以旧值为准，看起来“自动色就是那个”。
  // 自动色现在只能用 `autoColorOf`（永读自定义表）。

  /// 单元库配色：同一单元库在主页（`node:rel`）与 LibMeta（`rel`）里 id
  /// 形式不同，这里统一归一，保证作者词条与基础库卡颜色一致。
  /// [allowCustom] 为 false 时忽略本层自定义色（供「非末梢不下发」的基础库
  /// 落色使用），继承链其余部分不变。
  /// 自动配色：按注册顺序取色，顺序里没有就按 id 稳定散列——同一个库任何时候
  /// 都得到同一个色（不用随机，避免每次重建换个颜色）。
  ///
  /// **绝不读用户自定义表**。0.9.265 修：上一版末尾 `return colorFor(relOf(...))`，
  /// 而那个入口第一步就是查 `custom`，于是「来源=自动分配」仍可能返回残留
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
      final own = colorValueAt(unitId);
      if (own != null) return own;
    }
    if (src == BadgeColorSource.fixedCustom) {
      // 声明了自定义但没有值（被清过）：回落到自动配色，不留一个空壳状态。
      return autoColorOf(unitId, order: order);
    }
    // owner 2026-11-27：「上级结构生成的词条要分发给下级啊」。
    //
    // 从**直接上级**开始逐级上行，第一个设过色的那层就是分发源。
    // 此前只有「末梢分发 / 否则直达媒体库根」两种走法，中间层单元库
    // （有下级、自己也设了色）的色谁都拿不到——下级跳过它直达根。
    //
    // 遍历本身只有 [_upstreamOf] 一处：emoji 后缀必须与颜色走同一条链
    // （见 [emojiFor]），两处各写一遍必然分叉。
    final srcUnit = _upstreamOf(unitId, hasColorAt);
    if (srcUnit.isNotEmpty) {
      final inherited = colorValueAt(srcUnit);
      if (inherited != null) return inherited;
    }
    return autoColorOf(unitId, order: order);
  }

  /// 分发源：从 [startId] 向上逐级找第一个「该层这一项有值」的层。
  ///
  /// [hasValue] 判断该层这一项是否设过（颜色查 `custom`/`topCustom`，
  /// emoji 查 `emoji`）。来源显式选了「自动分配」的层不向下传——它表达的是
  /// 「这一层不要用上级的值」，对颜色和 emoji 是同一个意思。
  ///
  /// [includeStart] 为 true 时先看 [startId] 自己（基础库词条色要从它所属的
  /// 单元库本层开始找）；为 false 时从直接上级开始（单元库自身颜色在
  /// [colorForUnit] 里已经先查过了）。
  ///
  /// 颜色与 emoji **必须**共用这一处：此前 `emojiFor` 只看「本层 → 媒体库根」，
  /// 中间层设的后缀谁都拿不到，而它的颜色却能分发下去——同一句「上级分发给
  /// 下级」在两项配置上表现不同，用户按颜色的预期设 emoji 就会觉得没生效。
  static String _upstreamOf(String startId, bool Function(String id) hasValue,
      {bool includeStart = false}) {
    // 不包含起点时先把起点标成已访问：数据里出现环（父子互为上级）时，
    // 循环会绕回起点自己，那会把「本层已查过」的色当成继承值返回。
    final visited = <String>{if (!includeStart) relOf(startId)};
    var cursor = includeStart
        ? startId
        : (lookupByLibId(parentOfUnit, startId) ?? '');
    while (cursor.isNotEmpty) {
      if (!visited.add(relOf(cursor))) break;
      if (sourceFor(cursor) != BadgeColorSource.autoAssign && hasValue(cursor)) {
        return cursor;
      }
      cursor = lookupByLibId(parentOfUnit, cursor) ?? '';
    }
    final topId = lookupByLibId(topOfUnit, startId);
    if (topId != null &&
        relOf(topId) != relOf(startId) &&
        visited.add(relOf(topId)) &&
        sourceFor(topId) != BadgeColorSource.autoAssign &&
        hasValue(topId)) {
      return topId;
    }
    return '';
  }

  /// P1：词条外观。三种层级共用同一圆角与内边距，只改边框与底纹强度，
  /// 因此「形状与尺寸保持一致」由这一个函数保证，调用方不再各写一份。
  ///
  /// 边框粗细与底纹浓度可在「设置 → 自定义 → 库词条配色」里按层级调整；
  /// 圆角与内边距**不可调**，形状尺寸永远一致。

  static BoxDecoration decorationFor(LibEntryKind kind, int argb) {
    // 组合视图（设置页预览与既有测试读的是「一个带边框的 BoxDecoration」）。
    // 渲染层**不再**用它：见 [fillDecorationFor] / [borderDecorationFor]。
    final fill = fillDecorationFor(kind, argb);
    final border = borderDecorationFor(kind);
    return BoxDecoration(
      color: fill.color,
      borderRadius: fill.borderRadius,
      border: border.border,
    );
  }

  /// 词条底纹（**不含边框**）。
  ///
  /// 拆成两层的唯一理由（owner 2026-11-27）：
  /// > 「还有叫你不要动词条占用面积的大小，调粗边框占用不就变大了吗」
  ///
  /// `Container` 会把 `decoration` 的 `padding`（即 `Border.dimensions`）
  /// 加到内容内边距上——边框一旦画在 `decoration` 里，边框粗细就同时决定
  /// 词条占位面积：1.2 与 0.5 三档并排时宽度差 1.4dp，改成设置里的 3.0 会
  /// 让整排词条跟着变宽、换行位置漂移。边框必须画在不参与测量的层。
  static BoxDecoration fillDecorationFor(LibEntryKind kind, int argb) {
    final st = styleFor(kind);
    return BoxDecoration(
      color: Color(argb).withValues(alpha: st.fillAlpha),
      borderRadius: BorderRadius.circular(kEntryRadius),
    );
  }

  /// 词条边框（前景层，`Container.foregroundDecoration` 用）。
  ///
  /// 前景装饰不参与布局：同一个词条无论边框 0.5 还是 3.0，占位面积与
  /// 文字位置都不变，只有视觉描边变粗。
  static BoxDecoration borderDecorationFor(LibEntryKind kind) {
    final st = styleFor(kind);
    final base = Color(st.borderColor ??
        (kind == LibEntryKind.top ? 0xFFFFFFFF : 0xFF000000));
    return BoxDecoration(
      borderRadius: BorderRadius.circular(kEntryRadius),
      border: Border.all(
          color: base.withValues(alpha: st.borderAlpha), width: st.borderWidth),
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

  /// 这一层「有没有设过颜色」——分发链上的唯一判定。
  ///
  /// 0.9.347：此前这句 `lookupByLibId(custom, id) != null ||
  /// topColorFor(id) != null` 在 `colorForUnit`、`basicColorFor`、
  /// `inheritedColorFrom`、`inheritedColorFromBasic` 里各抄了一遍（四份逐字
  /// 相同），emoji 那一条又在 `emojiFor` 里写成另一种形态。四份里只要有一份
  /// 漏掉 `topCustom`，「顶级设的色能不能被下级拿到」就随调用路径不同而不同
  /// ——设置页说继承了、卡片上没有，两边都不报错。
  ///
  /// 现在分发链（[_upstreamOf]）的 `hasValue` 只允许传这三个判定函数。
  static bool hasColorAt(String id) => colorValueAt(id) != null;

  /// 这一层「设过的颜色值」；没设过返回 null。
  ///
  /// 普通单元库存在 [custom]、媒体库根存在 [topCustom]。这个「两张表依次查」
  /// 的表达式此前在 `colorForUnit`（本层 / 继承）、`basicColorFor`、
  /// `hasOwnColor`、`inheritedColorFrom*` 里共写了五遍；任何一遍漏掉
  /// `topCustom`，就会出现「媒体库设的色在某些路径上能用、另一些路径上是空」
  /// ——两边都不报错。现在取值和判有值都只走这里。
  static int? colorValueAt(String id) =>
      id.isEmpty ? null : (lookupByLibId(custom, id) ?? topColorFor(id));

  /// 这一层「有没有设过 emoji 后缀」（只看本层，不含继承）。
  static bool hasEmojiAt(String id) =>
      id.isNotEmpty && (lookupByLibId(emoji, id) ?? '').isNotEmpty;

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
      final c = basicColorAt(basicId);
      if (c != null) return c;
    }
    if (src == BadgeColorSource.fixedCustom) {
      return autoColorOf(basicId.isEmpty ? unitId : basicId, order: order);
    }
    // owner 2026-11-27：分发链要**逐级上行**，不能一下跳到媒体库根。
    //
    // 旧实现只有「末梢单元库才分发，否则直接取媒体库根色」。中间层单元库
    // （有下级、自己也设了色）的色因此谁都拿不到：下级跳过它、直达根。
    // 现在从「所属单元库本层」开始一级级往上找，第一个设过自定义色的
    // 就是分发源；与 [colorForUnit] / [emojiFor] 同一个 [_upstreamOf]。
    //
    // 此前这里另写了一份循环且**不看颜色来源**：中间层选了「自动分配」、
    // 表里却还留着旧色的情况下，它的颜色照样传给下级基础库，而它自己的
    // 词条已经显示自动色——同一层两个说法。
    final srcUnit = _upstreamOf(unitId, hasColorAt, includeStart: true);
    if (srcUnit.isNotEmpty) {
      final hit = colorValueAt(srcUnit);
      if (hit != null) return hit;
    }
    return colorForUnit(unitId, order: order, allowCustom: false);
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
    return hasColorAt(unitId);
  }

  /// 基础库是否真有生效中的自定义色（来源=自动时不算）。
  static bool hasOwnBasicColor(String basicId) {
    if (basicId.isEmpty) return false;
    if (sourceForBasic(basicId) == BadgeColorSource.autoAssign) return false;
    return basicColorAt(basicId) != null;
  }

  /// 基础库本层**设过的**颜色；没设过返回 null。
  ///
  /// 0.9.350：写端（[setBasicColor] / [setSource]）一直用 [removeByLibId]
  /// 清掉 `<id>` 与 `node:<id>` 两种等价键，读端却写成 `basicCustom[basicId]`
  /// 只认原样那一个键。只要有调用方传过带前缀的 id（单元库树里的
  /// `LibNode.id` 就是 `node:<rel>` 形态），就会出现
  /// 「同一个基础库：设置页显示自定义、卡片上是自动色」——两边都不报错。
  ///
  /// 现在读只有这一处，且与写端共用 [lookupByLibId]。
  static int? basicColorAt(String basicId) =>
      basicId.isEmpty ? null : lookupByLibId(basicCustom, basicId);

  /// 本层此刻是否从**上级**继承到颜色（没有本层色，且逐级上行有可继承色）。
  ///
  /// 判定必须走同一条分发链（[_upstreamOf]）：owner 2026-11-27 之后，颜色
  /// 可以由**中间层**单元库分发，不再是「只有媒体库根一层」。旧实现只查
  /// `topOfUnit` 那一跳，于是「基础库的色其实是从中间层单元库拿的」在设置页
  /// 显示成「没有继承」——而卡片上明明是那个中间层的色。
  static bool inheritsTopColor(String unitId, {List<String> order = const []}) {
    if (unitId.isEmpty || unitId == 'secret') return false;
    if (hasOwnColor(unitId)) return false;
    return inheritedColorFrom(unitId).isNotEmpty;
  }

  /// 本层实际从哪一层继承了颜色；没有（或本层自己就有色）返回空串。
  ///
  /// 唯一实现是 [_upstreamOf]——颜色、后缀、基础库颜色三处共用，设置页只读
  /// 这个结果，不再自己写「查 topOfUnit 再看 topCustom」的短链。
  ///
  /// `hasValue` 一律走 [hasColorAt]（0.9.347）：这句判定此前在这个文件里
  /// 有四份拷贝，任何一份漏掉 `topCustom` 都会让「顶级色能否分发」随调用
  /// 路径而变。
  static String inheritedColorFrom(String unitId) {
    if (unitId.isEmpty || unitId == 'secret') return '';
    if (hasOwnColor(unitId)) return '';
    if (sourceFor(unitId) == BadgeColorSource.autoAssign) return '';
    return _upstreamOf(unitId, hasColorAt);
  }

  /// 基础库实际从哪一层继承了颜色（从所属单元库本层开始逐级上行）。
  static String inheritedColorFromBasic(String basicId, String unitId) {
    if (hasOwnBasicColor(basicId)) return '';
    if (sourceForBasic(basicId) == BadgeColorSource.autoAssign) return '';
    if (unitId.isEmpty || unitId == 'secret') return '';
    return _upstreamOf(unitId, hasColorAt, includeStart: true);
  }

  /// 设置页「来源」文案的**唯一**出口。
  ///
  /// 三处各写一遍 switch 之后必然分叉：基础库那行写成
  /// `own ? '自定义' : '继承'`，于是「来源=自动分配」被显示成「继承」，
  /// 用户改完看到文案没变，会以为开关没生效。
  /// [hasOwn] 本层真有自定义色；[inherits] 本层当前从上级继承到了色；
  /// [sourceName] 实际分发源的名字（媒体库名 / 单元库名）。
  ///
  /// 「继承上级」不告诉用户跟谁一样——同一个设置页上并列着媒体库、若干个
  /// 单元库与基础库，光说「继承」用户无法判断该去改哪一层。带上来源名
  /// 才能回答「我现在的色是从哪里来的」。
  static String sourceLabelOf(BadgeColorSource src,
      {required bool hasOwn, required bool inherits, String sourceName = ''}) {
    if (hasOwn) return '自定义';
    switch (src) {
      case BadgeColorSource.autoAssign:
        return '自动分配';
      case BadgeColorSource.fixedCustom:
        // 声明了自定义、但色被清掉：此时真实生效的是自动配色。
        return '自动分配';
      case BadgeColorSource.inheritTop:
        // 继承源可能是媒体库根，也可能是更近的一层单元库（逐级分发），
        // 所以文案用「上级」而不是「顶级」——「顶级单元库」按 PROJECT_RULES
        // 只能在设计结构设置页内部使用，界面上叫「媒体库」。
        final n = sourceName.trim();
        return n.isEmpty ? '继承上级' : '继承 $n';
    }
  }

  /// 设置/清除基础库词条色。
  static Future<void> setBasicColor(String basicId, int? argb) async {
    if (basicId.isEmpty) return;
    if (basicColorAt(basicId) == argb) return;
    // 清除必须清掉全部等价键（`b` / `node:b`）。
    //
    // 旧写法只 `remove(basicId)`：传进来的 id 若带 `node:` 前缀
    // （单元库树里 `LibNode.id` 就是这种形态），带前缀那条键原样留着，
    // 于是点「恢复自动」后 [basicColorAt] 仍读得到旧色——按钮点了没反应，
    // 而表里已经没有任何界面能改到它。写端与读端、清端现在共用
    // [lookupByLibId] / [removeByLibId] 这一对。
    removeByLibId(basicCustom, basicId);
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

  static Future<void> saveBasic() =>
      savePrefString(basicPrefsKey, encodeBasic());

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
      // 名字为空回落 id 的规则只有 `labelOrId` 一处：这里旧写法是裸
      // `name.isEmpty`，与服务端下发纯空格名字时的其他入口不一致。
      out.add(stripIndex(labelOrId(ids[i], names[ids[i]])));
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
  /// 口径与颜色**完全同一条链**（[_upstreamOf]）：
  ///  1. 本层设过 → 用自己的；
  ///  2. 本层来源是「自动分配」→ 不继承（用户显式要求不要上级的）；
  ///  3. 否则从直接上级逐级上行，第一个设过后缀的层就是分发源，
  ///     一路没有才退到媒体库根。
  ///
  /// 此前这里只查「本层 → 媒体库根」，中间层单元库设的后缀在此处是死值：
  /// 层级跳过一次，就与它的颜色分发行为相反。
  ///
  /// `secret`（无归属兜底）不参与继承：它不在任何媒体库下面。
  static String emojiFor(String unitId) {
    if (unitId.isEmpty || unitId == 'secret') return '';
    final own = lookupByLibId(emoji, unitId);
    if (own != null && own.isNotEmpty) return own;
    // 显式选了「自动分配」：不继承上级，避免与颜色语义分叉。
    if (sourceFor(unitId) == BadgeColorSource.autoAssign) return '';
    final src = _upstreamOf(unitId, hasEmojiAt);
    if (src.isEmpty) return '';
    return lookupByLibId(emoji, src) ?? '';
  }

  /// 基础库词条的后缀：本库设过用自己的，否则与所属单元库走同一条上行链。
  ///
  /// 两个调用点此前各写一份：基础库卡片把后缀拼进文字、再把 chip 的
  /// `unitId` 置空；作者卡那排基础库词条却把 `unitId` 设成基础库 id，
  /// 于是「基础库自己设过后缀」只在后者出现，前者永远丢掉。
  static String basicEmojiFor(String basicId, String unitId) {
    if (basicId.isNotEmpty) {
      final own = lookupByLibId(emoji, basicId);
      if (own != null && own.isNotEmpty) return own;
    }
    return emojiFor(unitId);
  }

  /// 本层**自己设过**的后缀（不含继承）。设置页的「已自定义 N 项」用它：
  /// [emojiFor] 会回传继承来的后缀，拿它数「设过什么」会把整棵子树算成
  /// 自定义项，group 摘要变成永远一堆数字。
  static String ownEmoji(String id) => lookupByLibId(emoji, id) ?? '';

  /// 词条样式弹窗里 emoji 输入框的初值：**只取本层设置**。
  ///
  /// 0.9.347 修的真缺陷：那个输入框此前用 [emojiFor]（含继承）初始化。于是
  /// 打开一个「本层没设、从上级继承到 🔥」的单元库，只想改个颜色、直接点
  /// 保存，就把继承来的 🔥 原样写进了本层——从此上级换后缀它不再跟。
  /// 用户什么都没做，继承关系却断了，而且界面上看不出任何变化。
  ///
  /// 与 [ownEmoji] 的区别只是语义命名：写路径读它就必须是本层值，
  /// 这样「谁允许返回继承值」在调用点一眼可辨。
  static String emojiForEdit(String id) => ownEmoji(id);

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
      // P1：三层级外观（边框粗细/透明度 + 底纹浓度）。
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

  static Future<void> saveEmoji() =>
      savePrefString(emojiPrefsKey, encodeEmoji());

  /// 设置或清除单元库 emoji 后缀；同一单元库的 `rel` / `node:rel` 形式
  /// 一起清掉，避免两种 id 各留一份导致显示不一致。
  ///
  /// 去重比较用的是 [ownEmoji]（本层设置）而不是 [emojiFor]（含继承）。
  /// 旧写法比 `emojiFor`：本层没有自设后缀、刚好与上级继承来的那个相同时，
  /// 写入被当成「没变」直接 return——用户在本层显式选了一个后缀，表里却没有
  /// 这一条，之后上级改了后缀，这一层会跟着变。用户看到的是「我在这里设的
  /// 后缀自己没了」。
  static Future<void> setEmoji(String unitId, String? value) async {
    if (unitId.isEmpty) return;
    final v = sanitizeEmoji(value ?? '');
    if (ownEmoji(unitId) == v) return;
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

  /// P1：词条层级。三种层级共用同一形状/内边距/字号，只改边框与底纹。
  final LibEntryKind kind;

  /// 已算好的 emoji 后缀；null 表示按 [unitId] 走 [LibraryBadge.emojiFor]。
  final String? emoji;

  /// 单条词条最大宽度。信息区（播放页/作者头）用 [kBadgeChipMaxWidth]；
  /// 固定尺寸的小卡片（150dp 作者卡）必须传更小的值，否则媒体库+单元库
  /// 两级词条会换行、压到头像上——不是字太长的问题，是**卡片放不下两行**。
  final double maxWidth;

  const LibBadgeChip(
      {super.key,
      required this.label,
      required this.color,
      this.unitId = '',
      this.kind = LibEntryKind.unit,
      this.emoji,
      this.maxWidth = kBadgeChipMaxWidth});

  @override
  Widget build(BuildContext context) {
    // 订阅唯一变更信号：设置页改了颜色/外观/emoji，所有已显示词条立即跟着变。
    return ValueListenableBuilder<int>(
      valueListenable: LibraryBadge.revision,
      builder: (_, __, ___) => _paint(),
    );
  }

  Widget _paint() {
    final text = label.startsWith('+')
        ? label
        : () {
            final e = emoji ?? LibraryBadge.emojiFor(unitId);
            final base = LibraryBadge.stripIndex(label);
            return e.isEmpty ? base : '$base$e';
          }();
    // owner 2026-11-27：词条在播放页太长。库名最长 42 字、中位 15 字，
    // 不设上限就会撑满信息区。上限按「一行两三条」取，超出省略。
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        // 内边距是**固定值**（不是 `decoration.padding`）：边框改粗细时
        // 占位面积与文字位置都不许变（owner 2026-11-27「调粗边框占用不就
        // 变大了吗」）。底纹画在 decoration、边框画在 foregroundDecoration，
        // 后者不参与测量。
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: LibraryBadge.fillDecorationFor(kind, color),
        foregroundDecoration: LibraryBadge.borderDecorationFor(kind),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // `height: 1`：行高等于字号，文字在上下固定的内边距里自然居中。
          // 用 1.25 时多出的行距并不均匀分到上下两半，单行文本看起来会
          // 偏下（owner 2026-11-27：「词条里的文字要放在词条区域的中央」）。
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            height: 1.0,
            fontWeight: FontWeight.w600,
            color: Color(LibraryBadge.textColorOn(color)),
          ),
        ),
      ),
    );
  }
}
