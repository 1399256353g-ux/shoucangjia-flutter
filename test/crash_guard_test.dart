import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/crash_guard.dart';
import 'package:shoucangjia/crash_reports_page.dart';

void main() {
  setUp(() => CrashLog.instance.clear());

  test('同名错误合并计数并置顶，清空后恢复', () {
    final log = CrashLog.instance;
    log.record(StateError('列表为空'), kind: 'widget');
    log.record(StateError('另一处'), kind: 'async');
    expect(log.count, 2);
    expect(log.entries.first.message, contains('另一处'));

    log.record(StateError('列表为空'), kind: 'widget');
    expect(log.count, 2, reason: '同一条错误不重复追加');
    expect(log.entries.first.message, contains('列表为空'), reason: '再次出现要置顶');
    expect(log.entries.first.hits, 2);

    log.clear();
    expect(log.count, 0);
    expect(log.dump(), isEmpty);
  });

  test('记录条数上限 50，错误文本去换行并限长', () {
    final log = CrashLog.instance;
    for (var i = 0; i < 60; i++) {
      log.record(Exception('err-$i'));
    }
    expect(log.count, CrashLog.maxEntries);
    expect(log.entries.first.message, contains('err-59'));
    expect(log.entries.any((e) => e.message.contains('err-0')), isFalse);

    final long = describeError('a\nb${'x' * 900}');
    expect(long.contains('\n'), isFalse);
    expect(long.length <= 601, isTrue);
  });

  test('dump 带时间、类型与调用栈', () {
    CrashLog.instance.record(StateError('崩了'), kind: 'async',
        stack: StackTrace.fromString('#0 fn (lib/x.dart:1:1)'));
    final text = CrashLog.instance.dump();
    expect(text, contains('[异步]'));
    expect(text, contains('崩了'));
    expect(text, contains('#0 fn'));
  });

  testWidgets('构建失败占位块不需要 Material/MediaQuery 也能渲染', (tester) async {
    await tester.pumpWidget(const CrashFallback(message: '某一个部件炸了'));
    expect(find.text('此区域加载出错'), findsOneWidget);
    expect(find.textContaining('某一个部件炸了'), findsOneWidget);
  });

  testWidgets('诊断页展示错误并在清空后显示空状态', (tester) async {
    CrashLog.instance.record(StateError('网络请求失败'), kind: 'async');
    await tester.pumpWidget(const MaterialApp(home: CrashReportsPage()));
    await tester.pump();
    expect(find.text('最近 1 条错误'), findsOneWidget);
    expect(find.textContaining('网络请求失败'), findsOneWidget);

    CrashLog.instance.clear();
    await tester.pump();
    expect(find.text('最近没有错误'), findsOneWidget);
    expect(find.textContaining('运行正常'), findsOneWidget);
  });
}
