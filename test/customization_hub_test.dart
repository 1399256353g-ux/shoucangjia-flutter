import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_theme.dart';
import 'package:shoucangjia/main.dart';

// P2：设置整合入口。外观类设置收进「自定义」一页，设置首层只保留
// 连接 / 库 / 诊断 / 自定义 / 关于；避免长列表找不到入口。
void main() {
  testWidgets('设置首层有「自定义」入口，外观类条目不再散落首层', (tester) async {
    AppTheme.current.value = kDefaultThemeId;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.themeData,
      home: const SettingsHubPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('自定义'), findsOneWidget);
    // 外观类条目统一收进「自定义」，首层不再重复出现
    expect(find.text('主题外观'), findsNothing);
    expect(find.text('播放设置'), findsNothing);
    expect(find.text('库词条配色'), findsNothing);
    expect(find.text('库角标'), findsNothing);
    expect(find.text('按键绑定'), findsNothing);
  });

  testWidgets('自定义页列出全部外观类入口', (tester) async {
    AppTheme.current.value = kDefaultThemeId;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.themeData,
      home: const CustomizationHubPage(),
    ));
    await tester.pumpAndSettle();

    for (final label in [
      '主题外观',
      '库词条配色',
      '库角标',
      '按键绑定',
      '播放设置',
      '缓存',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺少入口：$label');
    }
  });

  testWidgets('自定义页在窄屏下不溢出', (tester) async {
    AppTheme.current.value = kDefaultThemeId;
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.themeData,
      home: const CustomizationHubPage(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
