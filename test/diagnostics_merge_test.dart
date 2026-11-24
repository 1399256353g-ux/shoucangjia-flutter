import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/crash_guard.dart';
import 'package:shoucangjia/crash_reports_page.dart';
import 'package:shoucangjia/main.dart' show DiagnosticsPage;
import 'package:shoucangjia/perf_diagnostics.dart';

// 「诊断」「诊断信息」「性能计数」收在同一个页面：入口只留一个。
// 这里只断言结构（tab 数量/标题键/计数行形状），不看任何媒体内容。

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CrashLog.instance.clear();
    PerfDiagnostics.instance.reset();
  });

  testWidgets('诊断页：三个 tab（动作记录 / 错误记录 / 性能计数）', (t) async {
    await t.pumpWidget(const MaterialApp(home: DiagnosticsPage()));
    // 动作记录 tab 里有加载圈（持续动画），不能用 pumpAndSettle。
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('动作记录'), findsOneWidget);
    expect(find.text('错误记录'), findsOneWidget);
    expect(find.text('性能计数'), findsOneWidget);
    expect(find.byType(TabBarView), findsOneWidget);
  });

  testWidgets('性能计数 tab 显示计数（数字进产品，不只是测试里）', (t) async {
    // 造两条可辨认的计数：一个槽位 + 一次解码采样。
    PerfDiagnostics.instance.slotCreated();
    PerfDiagnostics.instance.recordDecode(active: 3, waiting: 1, limit: 4);
    await t.pumpWidget(const MaterialApp(home: DiagnosticsPage()));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.text('性能计数'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('slots_created=1'), findsOneWidget);
    expect(find.textContaining('decode_peak_active=3'), findsOneWidget);
    expect(find.textContaining('decode_limit=4'), findsOneWidget);
    // 数值口径与落盘日志同源：计数本身不得带出任何路径/文件名。
    expect(find.textContaining('/media/'), findsNothing);
  });

  testWidgets('页面已打开时计数变化要实时刷新（靠 perfRevision，不是轮询）', (t) async {
    await t.pumpWidget(const MaterialApp(home: DiagnosticsPage()));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.text('性能计数'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('decode_peak_active=0'), findsOneWidget);

    // 页面开着的时候产生新计数：必须当场反映出来。
    //
    // 这里刻意用 `recordDecode`（只记计数、**不写日志行**）：如果页面只靠
    // 「log 顺带刷新」就会在这条上露馅——状态层没有自己的变更信号，
    // 只是碰巧被另一个副作用带了一次重建。
    PerfDiagnostics.instance.recordDecode(active: 7, waiting: 2, limit: 9);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('decode_peak_active=7'), findsOneWidget,
        reason: '计数变了但页面没刷新——perfRevision 没被自增，或页面没监听它');
    expect(find.textContaining('decode_peak_active=0'), findsNothing);
  });

  testWidgets('错误记录 tab 复用 CrashReportsPage（嵌入模式无 AppBar）', (t) async {
    await t.pumpWidget(const MaterialApp(home: DiagnosticsPage()));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.text('错误记录'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final page = find.byType(CrashReportsPage);
    expect(page, findsOneWidget);
    // 嵌入模式：内部不应再有第二个 Scaffold/AppBar
    final scaffolds =
        find.descendant(of: page, matching: find.byType(Scaffold));
    expect(scaffolds, findsNothing);
  });

  testWidgets('独立打开 CrashReportsPage 仍自带标题（默认非嵌入）', (t) async {
    await t.pumpWidget(const MaterialApp(home: CrashReportsPage()));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('诊断信息'), findsOneWidget);
  });
}
