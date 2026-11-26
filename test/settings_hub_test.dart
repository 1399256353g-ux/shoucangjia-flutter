import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_theme.dart';
import 'package:shoucangjia/main.dart';

void main() {
  testWidgets('设置页不再有全局「收藏夹/同步源选择」入口', (tester) async {
    AppTheme.current.value = kDefaultThemeId;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.themeData,
      home: const SettingsHubPage(),
    ));
    await tester.pumpAndSettle();

    // 同步源已并入每个单元库的爬虫设置；设置页只保留「爬虫设置」入口。
    // owner 2026-11-27：「媒体库与爬虫设置更名为爬虫设置」。
    expect(find.text('同步源选择'), findsNothing);
    expect(find.text('爬虫设置'), findsOneWidget);
    expect(find.textContaining('收藏夹'), findsNothing);
    // 双击点赞（0.9.19 引入）已在 0.9.174 按 owner 要求整体移除：
    // 设置里不应再出现该开关，避免出现「有开关但画面已无点赞」的死配置。
    await tester.scrollUntilVisible(find.text('推荐数量'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('双击点赞'), findsNothing);
    expect(find.text('点赞'), findsNothing);
  });
}
