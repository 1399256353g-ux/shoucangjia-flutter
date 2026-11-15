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
  });
}
