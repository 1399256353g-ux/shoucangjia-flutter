import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emoji_text.dart';

/// 一套主题的外观定义。
///
/// 主题只描述「种子色 + 明暗 + 背景」三件事，具体组件配色由 Material 3
/// 从种子色生成，保证新增主题时不必逐页改色。
class AppThemeSpec {
  final String id;
  final String name;
  final String subtitle;
  final Color seed;
  final Brightness brightness;
  final Color background;

  const AppThemeSpec({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.seed,
    required this.brightness,
    required this.background,
  });

  bool get isLight => brightness == Brightness.light;
}

/// 可选主题列表（第一个为默认「深空蓝」）。
const List<AppThemeSpec> kAppThemes = <AppThemeSpec>[
  AppThemeSpec(
    id: 'deepblue',
    name: '深空蓝',
    subtitle: '默认 · 沉稳蓝调',
    seed: Color(0xFF4A7FB5),
    brightness: Brightness.dark,
    background: Color(0xFF101418),
  ),
  AppThemeSpec(
    id: 'obsidian',
    name: '曜石黑',
    subtitle: '纯黑省电 · 冷灰点缀',
    seed: Color(0xFF9AA5B1),
    brightness: Brightness.dark,
    background: Color(0xFF000000),
  ),
  AppThemeSpec(
    id: 'aurora',
    name: '极光青',
    subtitle: '青绿流光 · 清爽',
    seed: Color(0xFF19C3B1),
    brightness: Brightness.dark,
    background: Color(0xFF07120F),
  ),
  AppThemeSpec(
    id: 'rose',
    name: '暗夜玫瑰',
    subtitle: '粉紫微光 · 柔和',
    seed: Color(0xFFE879A9),
    brightness: Brightness.dark,
    background: Color(0xFF170B10),
  ),
  AppThemeSpec(
    id: 'amber',
    name: '日落琥珀',
    subtitle: '暖橙夕照 · 温润',
    seed: Color(0xFFF0A34A),
    brightness: Brightness.dark,
    background: Color(0xFF171008),
  ),
  AppThemeSpec(
    id: 'daylight',
    name: '明亮日间',
    subtitle: '浅色背景 · 白天好用',
    seed: Color(0xFF2F6FEB),
    brightness: Brightness.light,
    background: Color(0xFFF5F7FB),
  ),
];

const String kDefaultThemeId = 'deepblue';
const String kThemePrefsKey = 'app_theme_v1';

/// 未知 / 空 id 一律回落到默认主题，避免旧版本或损坏配置导致无主题可用。
String normalizeThemeId(String? id) {
  if (id == null) return kDefaultThemeId;
  for (final t in kAppThemes) {
    if (t.id == id) return id;
  }
  return kDefaultThemeId;
}

AppThemeSpec themeSpec(String? id) =>
    kAppThemes.firstWhere((t) => t.id == normalizeThemeId(id));

/// 由主题定义生成 ThemeData。
ThemeData buildThemeData(AppThemeSpec spec) {
  final scheme = ColorScheme.fromSeed(
    seedColor: spec.seed,
    brightness: spec.brightness,
  );
  final foreground = scheme.onSurface;
  return ThemeData(
    brightness: spec.brightness,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: spec.background,
    fontFamilyFallback: kEmojiFontFallback,
    appBarTheme: AppBarTheme(
      backgroundColor: spec.background,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.35),
      space: 1,
      thickness: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: scheme.onSurface),
    ),
  );
}

/// 全局当前主题：用 ValueNotifier 让设置页改动立即驱动 MaterialApp 重建，
/// 即「即时预览」；选择结果异步写入 SharedPreferences。
class AppTheme {
  static final ValueNotifier<String> current =
      ValueNotifier<String>(kDefaultThemeId);

  static String get id => normalizeThemeId(current.value);

  static ThemeData get themeData => buildThemeData(themeSpec(current.value));

  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      current.value = normalizeThemeId(sp.getString(kThemePrefsKey));
    } catch (_) {
      current.value = kDefaultThemeId;
    }
  }

  static Future<void> select(String id) async {
    final v = normalizeThemeId(id);
    if (current.value != v) current.value = v;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kThemePrefsKey, v);
    } catch (_) {}
  }
}
