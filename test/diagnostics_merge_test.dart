import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/crash_guard.dart';
import 'package:shoucangjia/crash_reports_page.dart';
import 'package:shoucangjia/main.dart' show DiagnosticsPage;

// 「诊断」与「诊断信息」合并成一个页面：两个 tab，入口只留一个。
// 这里只断言结构（tab 数量/标题键），不看任何媒体内容。

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CrashLog.instance.clear();
  });

  testWidgets('诊断页：两个 tab（动作记录 / 错误记录）', (t) async {
    await t.pumpWidget(const MaterialApp(home: DiagnosticsPage()));
    // 动作记录 tab 里有加载圈（持续动画），不能用 pumpAndSettle。
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('动作记录'), findsOneWidget);
    expect(find.text('错误记录'), findsOneWidget);
    expect(find.byType(TabBarView), findsOneWidget);
  });

  testWidgets('错误记录 tab 复用 CrashReportsPage（嵌入模式无 AppBar）',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: DiagnosticsPage()));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.text('错误记录'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final page = find.byType(CrashReportsPage);
    expect(page, findsOneWidget);
    // 嵌入模式：内部不应再有第二个 Scaffold/AppBar
    final scaffolds = find.descendant(
        of: page, matching: find.byType(Scaffold));
    expect(scaffolds, findsNothing);
  });

  testWidgets('独立打开 CrashReportsPage 仍自带标题（默认非嵌入）', (t) async {
    await t.pumpWidget(const MaterialApp(home: CrashReportsPage()));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('诊断信息'), findsOneWidget);
  });
}
