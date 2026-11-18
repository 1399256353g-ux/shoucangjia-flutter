import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/main.dart';
import 'package:shoucangjia/watch_progress.dart';
import 'package:shoucangjia/work_card.dart';

/// 基准：一次播放进度 tick 引起多少张 Works 卡片重建。
///
/// 通过 `debugOnRebuildDirtyWidget` 统计「被标脏并重建」的 Element；
/// 同时用 widget 实例 identity 守恒证明卡片子树没有被重建。
void main() {
  final rebuilt = <String, int>{};
  final rebuiltElements = <Element>{};

  setUp(() {
    rebuilt.clear();
    rebuiltElements.clear();
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      final name = e.widget.runtimeType.toString();
      rebuilt[name] = (rebuilt[name] ?? 0) + 1;
      rebuiltElements.add(e);
    };
  });

  tearDown(() {
    debugOnRebuildDirtyWidget = null;
  });

  List<Map<String, dynamic>> works(int n) => List<Map<String, dynamic>>.generate(
      n,
      (i) => <String, dynamic>{
            'id': 'w$i',
            't': 'v',
            'th': '',
            'ti': '作品 $i',
            'a': '作者',
          });

  Future<void> pumpGrid(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    WatchProgressStore.resetForTest();
    await WatchProgressStore.ensureLoaded();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
            width: 400,
            height: 800,
            child: WorkGrid(works: works(80), lib: 'douyin')),
      ),
    ));
    await tester.pump();
    // 清掉首帧构建的统计，只量「进度 tick」这一帧。
    rebuilt.clear();
    rebuiltElements.clear();
  }

  testWidgets('进度 tick 不重建整张卡片（只重建局部角标/进度条）', (tester) async {
    await pumpGrid(tester);

    final cardsBefore = tester.elementList(find.byType(WorkCard)).toList();
    expect(cardsBefore, isNotEmpty);
    final widgetsBefore = cardsBefore.map((e) => e.widget).toList();

    // 模拟播放器上报一次进度（w0 对应作品）。
    WatchProgressStore.record(
      lib: 'douyin',
      id: 'w0',
      positionMs: 30000,
      durationMs: 100000,
      force: true,
    );
    await tester.pump();

    final stats = Map<String, int>.from(rebuilt);
    final cardRebuilds = stats['WorkCard'] ?? 0;
    // ignore: avoid_print
    print('[bench] tick 重建统计: $stats');

    // 进度变化不应导致任何整卡重建。
    expect(cardRebuilds, 0,
        reason: '一张卡片的进度变化重建了 $cardRebuilds 张 WorkCard：$stats');

    // 卡片 widget 实例 identity 守恒（子树没有被重新构建）。
    final cardsAfter = tester.elementList(find.byType(WorkCard)).toList();
    for (var i = 0; i < widgetsBefore.length; i++) {
      expect(identical(widgetsBefore[i], cardsAfter[i].widget), isTrue,
          reason: '第 $i 张卡片被重建');
    }

    // 局部进度层有刷新；进度条出现（w0 可见）。
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    // 让落盘 timer 结束，避免 pending timer 报错。
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('卡片带 RepaintBoundary 隔离重绘', (tester) async {
    await pumpGrid(tester);

    final cards = find.byType(WorkCard);
    expect(cards, findsWidgets);
    // 0.9.87：根节点不再套 RepaintBoundary。
    // 原因：卡片被顶部栏部分遮挡时，悬停触发的局部重绘只覆盖可见区域，
    // 露出的那一段没有像素缓存，会出现「整卡重新出现、被遮住部分空白」。
    for (final e in tester.elementList(cards)) {
      Element? first;
      e.visitChildren((c) {
        first ??= c;
      });
      expect(first, isNotNull, reason: 'WorkCard 没有子节点');
      expect(first!.widget is RepaintBoundary, isFalse,
          reason: '卡片根节点不应再包 RepaintBoundary');
    }

    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('滚动一屏不触发整卡全量重建的进度监听', (tester) async {
    await pumpGrid(tester);
    final before = tester.elementList(find.byType(WorkCard)).length;
    expect(before, greaterThan(0));
    await tester.drag(find.byType(GridView), const Offset(0, -400));
    await tester.pumpAndSettle();
    // 滚动本身只应创建新进入视口的卡片，不应引发 tick 式全量重建。
    final stats = Map<String, int>.from(rebuilt);
    // ignore: avoid_print
    print('[bench] 滚动一屏重建统计: $stats');
    await tester.pump(const Duration(milliseconds: 700));
  });
}
