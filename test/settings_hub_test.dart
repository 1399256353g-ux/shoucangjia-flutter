import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_theme.dart';
import 'package:shoucangjia/main.dart';

void main() {
  testWidgets('设置页使用「同步源」措辞，不再出现旧「收藏夹」入口', (tester) async {
    AppTheme.current.value = kDefaultThemeId;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.themeData,
      home: const SettingsHubPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('同步源选择'), findsOneWidget);
    expect(find.textContaining('同步源'), findsWidgets);
    expect(find.textContaining('收藏夹'), findsNothing);
    // 双击点赞开关（0.9.19）：默认开启，可在设置里关掉。列表懒加载，先滚到可见。
    await tester.scrollUntilVisible(find.text('双击点赞'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('双击点赞'), findsOneWidget);
  });
}
