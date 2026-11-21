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

    // 同步源已并入每个单元库的爬虫设置；设置页只保留「媒体库与爬虫」。
    expect(find.text('同步源选择'), findsNothing);
    expect(find.text('媒体库与爬虫'), findsOneWidget);
    expect(find.textContaining('收藏夹'), findsNothing);
    // 双击点赞开关（0.9.19）：默认开启，可在设置里关掉。列表懒加载，先滚到可见。
    await tester.scrollUntilVisible(find.text('双击点赞'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('双击点赞'), findsOneWidget);
  });
}
