import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/app_theme.dart';
import 'package:shoucangjia/main.dart';

void main() {
  testWidgets('主题设置页列出多套主题，点击后即时生效并高亮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AppTheme.current.value = kDefaultThemeId;

    await tester.pumpWidget(ValueListenableBuilder<String>(
      valueListenable: AppTheme.current,
      builder: (context, _, __) => MaterialApp(
        theme: AppTheme.themeData,
        home: const ThemeSettingsPage(),
      ),
    ));

    expect(find.text('主题外观'), findsOneWidget);
    // 主题数量增加后网格是懒加载的：逐个滚动到可见再断言，
    // 不能要求所有卡片同时存在于树上。
    final grid = find.byType(Scrollable).first;
    for (final t in kAppThemes) {
      await tester.scrollUntilVisible(find.text(t.name), 160, scrollable: grid);
      expect(find.text(t.name), findsOneWidget);
    }

    // 点「极光青」应立即切换全局主题，无需确认或重启
    await tester.scrollUntilVisible(find.text('极光青'), -160, scrollable: grid);
    await tester.pumpAndSettle();
    await tester.tap(find.text('极光青'));
    await tester.pumpAndSettle();
    expect(AppTheme.current.value, 'aurora');

    await tester.scrollUntilVisible(find.text('明亮日间'), 160, scrollable: grid);
    await tester.pumpAndSettle();
    await tester.tap(find.text('明亮日间'));
    await tester.pumpAndSettle();
    expect(AppTheme.current.value, 'daylight');
    // 不再依赖「示例条目」是否在可视区：直接从页面上下文取当前主题亮度。
    expect(Theme.of(tester.element(find.byType(ThemeSettingsPage))).brightness,
        Brightness.light);
  });

  testWidgets('主题设置页在窄屏下不溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AppTheme.current.value = kDefaultThemeId;
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.themeData,
      home: const ThemeSettingsPage(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
