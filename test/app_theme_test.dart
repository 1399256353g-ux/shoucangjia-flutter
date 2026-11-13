import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_theme.dart';

void main() {
  test('未知或空主题 id 回落到默认主题', () {
    expect(normalizeThemeId(null), kDefaultThemeId);
    expect(normalizeThemeId(''), kDefaultThemeId);
    expect(normalizeThemeId('nope'), kDefaultThemeId);
    expect(normalizeThemeId('aurora'), 'aurora');
  });

  test('主题 id 唯一且默认主题排在第一位', () {
    final ids = kAppThemes.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.first, kDefaultThemeId);
    expect(kAppThemes.length, greaterThanOrEqualTo(4));
  });

  test('themeSpec 返回对应定义，非法 id 回落默认', () {
    expect(themeSpec('rose').name, '暗夜玫瑰');
    expect(themeSpec('bogus').id, kDefaultThemeId);
  });

  test('每套主题生成独立配色与背景', () {
    final themes = kAppThemes.map(buildThemeData).toList();
    for (var i = 0; i < themes.length; i++) {
      final spec = kAppThemes[i];
      final t = themes[i];
      expect(t.brightness, spec.brightness);
      expect(t.scaffoldBackgroundColor, spec.background);
      expect(t.appBarTheme.backgroundColor, spec.background);
      expect(t.colorScheme.primary, isNot(Colors.transparent));
    }
    // 不同主题的主色应当不同，避免「换了等于没换」
    final primaries = themes.map((t) => t.colorScheme.primary.toARGB32()).toSet();
    expect(primaries.length, themes.length);
  });

  test('浅色主题使用浅色 scheme，深色主题使用深色 scheme', () {
    final light = buildThemeData(themeSpec('daylight'));
    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.brightness, Brightness.light);
    final dark = buildThemeData(themeSpec('deepblue'));
    expect(dark.colorScheme.brightness, Brightness.dark);
  });
}
