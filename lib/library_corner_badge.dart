import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'color_codec.dart';
import 'contrast.dart';
import 'prefs_json.dart';

/// 库种类 / 等级 —— 决定左上角角标的默认图案。
///
/// 与词条（颜色 + emoji）是两套东西：词条表达「属于哪个单元库」，
/// 角标表达「这是个什么层级的库」。所以角标只按种类区分，
/// 形状与尺寸在所有层级保持一致，仅图案（与可选颜色）不同。
enum LibBadgeKind {
  /// 顶级单元库（连接的媒体库根）。
  top,

  /// 中间层单元库。
  unit,

  /// 末梢基础库。
  basic,

  /// 无法判定归属（作者卡等非库语境）。
  other,
}

/// 角标图案的默认映射：每种层级一个固定图案。
const Map<LibBadgeKind, int> kDefaultCornerPattern = <LibBadgeKind, int>{
  LibBadgeKind.top: 0, // 六边形
  LibBadgeKind.unit: 1, // 层叠方块
  LibBadgeKind.basic: 2, // 书页
  LibBadgeKind.other: 5, // 圆点
};

/// 可选图案清单（顺序即 id）：图案用内置形状绘制，不依赖图标字体，
/// 保证桌面 / Android / iOS 上完全一致。
const List<String> kCornerPatternNames = <String>[
  '六边形', '层叠', '书页', '菱形', '三角', '圆点', '方框', '星',
];

/// 角标统一尺寸（形状一致是硬要求，任何层级都不得改）：
/// 逻辑边长 18dp、圆角 5dp、内边距 3dp。
const double kCornerBadgeSize = 18;
const double kCornerBadgeRadius = 5;
const double kCornerBadgePadding = 3;
const double kCornerBadgeInset = 6;

/// 图案色板：默认按层级取色，用户可改。
const Map<LibBadgeKind, int> kDefaultCornerColor = <LibBadgeKind, int>{
  LibBadgeKind.top: 0xFF1D4ED8,
  LibBadgeKind.unit: 0xFF047857,
  LibBadgeKind.basic: 0xFF6B7280,
  LibBadgeKind.other: 0xFF6B7280,
};

/// 角标设置：图案与颜色都可自定义，按层级存。
/// 纯数据 + 纯函数，便于单测；不依赖 UI。
class LibraryCornerBadge {
  static const String prefsKey = 'lib_corner_badge_v1';

  /// 唯一变更信号：任何层级改了图案/颜色就自增一次。
  ///
  /// 角标是按层级取值的**静态**数据，卡片一旦建好就不会自己重建；
  /// 只靠设置页 `setState` 只有设置页自己会刷新，已经渲染在主页/单元库页的
  /// 角标会停在旧图案上 —— 这就是「更换后即时生效」做不到的根因。
  /// 组件内部订阅这一个 notifier，设置改了所有可见角标一起重建，
  /// 不需要各页面自己往上递回调。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 层级 → 图案 id。
  static final Map<LibBadgeKind, int> pattern = <LibBadgeKind, int>{
    ...kDefaultCornerPattern,
  };

  /// 层级 → ARGB 颜色。
  static final Map<LibBadgeKind, int> color = <LibBadgeKind, int>{
    ...kDefaultCornerColor,
  };

  /// 从库属性判定层级。
  ///
  /// - `isTop`：该库就是连接根（顶级单元库）。
  /// - `unitRel` 非空且不是顶级 → 中间层单元库。
  /// - 其余（末梢基础库 / 未知）→ basic。
  ///
  /// 判定只接受调用方已经算好的结构事实，不看任何目录名文本。
  static LibBadgeKind kindOf({bool isTop = false, bool isUnit = false}) {
    if (isTop) return LibBadgeKind.top;
    if (isUnit) return LibBadgeKind.unit;
    return LibBadgeKind.basic;
  }

  static int patternFor(LibBadgeKind kind) =>
      pattern[kind] ?? kDefaultCornerPattern[kind] ?? 0;

  static int colorFor(LibBadgeKind kind) =>
      color[kind] ?? kDefaultCornerColor[kind] ?? 0xFF6B7280;

  /// 图案 id 夹到合法范围（非法值回默认，不抛异常）。
  static int clampPattern(LibBadgeKind kind, int id) {
    if (id < 0 || id >= kCornerPatternNames.length) {
      return kDefaultCornerPattern[kind] ?? 0;
    }
    return id;
  }

  static Map<String, dynamic> toJson() => {
        'pattern': {for (final e in pattern.entries) e.key.name: e.value},
        'color': {
          for (final e in color.entries) e.key.name: argbToHex(e.value)
        },
      };

  static void applyJson(Map<String, dynamic> j) {
    resetDefaults();
    _bump();
    final p = j['pattern'];
    if (p is Map) {
      for (final k in LibBadgeKind.values) {
        final v = p[k.name];
        if (v is num) pattern[k] = clampPattern(k, v.toInt());
      }
    }
    final c = j['color'];
    if (c is Map) {
      for (final k in LibBadgeKind.values) {
        final n = argbFromJson(c[k.name]);
        if (n != null) color[k] = n;
      }
    }
  }

  static void resetDefaults() {
    pattern
      ..clear()
      ..addAll(kDefaultCornerPattern);
    color
      ..clear()
      ..addAll(kDefaultCornerColor);
  }

  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) applyJson(j);
    } catch (_) {}
  }

  static Future<void> save() => savePrefString(prefsKey, jsonEncode(toJson()));

  static Future<void> setPattern(LibBadgeKind kind, int id) async {
    final next = clampPattern(kind, id);
    if (pattern[kind] == next) return;
    pattern[kind] = next;
    _bump();
    await save();
  }

  static Future<void> setColor(LibBadgeKind kind, int argb) async {
    if (color[kind] == argb) return;
    color[kind] = argb;
    _bump();
    await save();
  }

  /// 恢复某层级的图案与颜色。
  static Future<void> resetKind(LibBadgeKind kind) async {
    final p = kDefaultCornerPattern[kind] ?? 0;
    final c = kDefaultCornerColor[kind] ?? 0xFF6B7280;
    if (pattern[kind] == p && color[kind] == c) return;
    pattern[kind] = p;
    color[kind] = c;
    _bump();
    await save();
  }

  static void _bump() => revision.value++;
}

/// 左上角角标：所有层级同一形状尺寸，只有图案与颜色不同。
class LibCornerBadge extends StatelessWidget {
  final LibBadgeKind kind;

  const LibCornerBadge({super.key, required this.kind});

  @override
  Widget build(BuildContext context) {
    // 订阅唯一变更信号：设置页改了图案/颜色，所有已渲染角标立即跟着变。
    return ValueListenableBuilder<int>(
      valueListenable: LibraryCornerBadge.revision,
      builder: (_, __, ___) => _paint(),
    );
  }

  Widget _paint() {
    final argb = LibraryCornerBadge.colorFor(kind);
    final fg = foregroundArgbOn(argb);
    return Container(
      key: ValueKey('lib-corner-badge-${kind.name}'),
      width: kCornerBadgeSize,
      height: kCornerBadgeSize,
      decoration: BoxDecoration(
        color: Color(argb).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(kCornerBadgeRadius),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(kCornerBadgePadding),
      child: CustomPaint(
        painter: _CornerGlyphPainter(
          pattern: LibraryCornerBadge.patternFor(kind),
          color: Color(fg),
        ),
      ),
    );
  }

}

/// 内置图案：只用标准几何形状绘制，跨平台一致、无字体依赖。
class _CornerGlyphPainter extends CustomPainter {
  final int pattern;
  final Color color;

  const _CornerGlyphPainter({required this.pattern, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;
    switch (pattern % kCornerPatternNames.length) {
      case 0: // 六边形
        final path = Path();
        for (var i = 0; i < 6; i++) {
          final a = -1.5707963 + i * 1.0471976;
          final x = cx + cx * 0.98 * math.cos(a);
          final y = cy + cy * 0.98 * math.sin(a);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, p);
        break;
      case 1: // 层叠：两层错开的圆角块
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, h * 0.28, w * 0.72, h * 0.62),
              Radius.circular(w * 0.14)),
          p,
        );
        p.color = color.withValues(alpha: 0.55);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.28, 0, w * 0.72, h * 0.62),
              Radius.circular(w * 0.14)),
          p,
        );
        break;
      case 2: // 书页：竖线 + 折角
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.1, 0, w * 0.8, h),
              Radius.circular(w * 0.12)),
          p,
        );
        p.color = color.withValues(alpha: 0.45);
        canvas.drawRect(Rect.fromLTWH(w * 0.34, h * 0.34, w * 0.1, h * 0.48), p);
        canvas.drawRect(Rect.fromLTWH(w * 0.54, h * 0.34, w * 0.1, h * 0.48), p);
        break;
      case 3: // 菱形
        final path = Path()
          ..moveTo(cx, 0)
          ..lineTo(w, cy)
          ..lineTo(cx, h)
          ..lineTo(0, cy)
          ..close();
        canvas.drawPath(path, p);
        break;
      case 4: // 三角
        final path = Path()
          ..moveTo(cx, 0)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
        canvas.drawPath(path, p);
        break;
      case 5: // 圆点
        canvas.drawCircle(Offset(cx, cy), w * 0.42, p);
        break;
      case 6: // 方框（空心）
        p.style = PaintingStyle.stroke;
        p.strokeWidth = w * 0.18;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(w * 0.12, h * 0.12, w * 0.76, h * 0.76),
              Radius.circular(w * 0.1)),
          p,
        );
        break;
      default: // 星
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final a = -1.5707963 + i * 0.6283185;
          final r = i.isEven ? 1.0 : 0.46;
          final x = cx + cx * 0.98 * r * math.cos(a);
          final y = cy + cy * 0.98 * r * math.sin(a);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, p);
        break;
    }
  }


  @override
  bool shouldRepaint(covariant _CornerGlyphPainter old) =>
      old.pattern != pattern || old.color != color;
}
