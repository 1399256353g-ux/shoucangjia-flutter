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
    for (final t in kAppThemes) {
      expect(find.text(t.name), findsOneWidget);
    }

    // 点「极光青」应立即切换全局主题，无需确认或重启
    await tester.ensureVisible(find.text('极光青'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('极光青'));
    await tester.pumpAndSettle();
    expect(AppTheme.current.value, 'aurora');

    await tester.ensureVisible(find.text('明亮日间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('明亮日间'));
    await tester.pumpAndSettle();
    expect(AppTheme.current.value, 'daylight');
    expect(Theme.of(tester.element(find.text('示例条目'))).brightness,
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
