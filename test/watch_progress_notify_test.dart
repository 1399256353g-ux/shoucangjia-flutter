import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/watch_progress.dart';
import 'package:shoucangjia/work_card.dart';

/// 0.9.71：卡片进度层只监听自己这条作品的变更。
///
/// 基准：给作品 A 记录播放位置时，只有 A 那张卡的进度层重建；
/// 网格里其它作品（没有观看记录）不能因为别人写入而重绘。
void main() {
  final rebuilt = <String, int>{};

  setUp(() {
    rebuilt.clear();
    WatchProgressStore.resetForTest();
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      final name = e.widget.runtimeType.toString();
      rebuilt[name] = (rebuilt[name] ?? 0) + 1;
    };
  });

  tearDown(() {
    debugOnRebuildDirtyWidget = null;
    WatchProgressStore.resetForTest();
  });

  Future<void> pumpTwoCards(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          for (final id in ['a', 'b'])
            SizedBox(
              width: 120,
              height: 160,
              child: WorkCard(
                title: '作品 $id',
                typeLabel: '视频',
                coverUrl: '',
                watchLib: 'L',
                watchId: id,
                onTap: () {},
              ),
            ),
        ]),
      ),
    ));
    await tester.pump();
    rebuilt.clear();
  }

  testWidgets('写入 A 不重建 B 的进度层', (tester) async {
    await pumpTwoCards(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    WatchProgressStore.record(
        lib: 'L', id: 'a', positionMs: 12000, durationMs: 60000, force: true);
    await tester.pump();

    // A 出现进度条，B 仍然没有。
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // 让 record() 的延迟落盘计时器跑完，避免帧调度残留。
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('播放中周期性上报只重建被写入的那一条', (tester) async {
    await pumpTwoCards(tester);
    WatchProgressStore.record(
        lib: 'L', id: 'a', positionMs: 5000, durationMs: 60000, force: true);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    rebuilt.clear();
    for (var i = 2; i <= 4; i++) {
      WatchProgressStore.record(
          lib: 'L',
          id: 'a',
          positionMs: i * 5000,
          durationMs: 60000,
          force: true);
    }
    await tester.pump();

    // 每次写入只重建 A 自己的进度条；B 的进度层一次也没有被标脏。
    expect(rebuilt['LinearProgressIndicator'] ?? 0, greaterThan(0));
    expect(rebuilt['_WatchProgressLayer'] ?? 0, 0,
        reason: '进度层外壳不应重建，只有内部进度条刷新');
    expect(WatchProgressStore.of('L', 'b'), isNull);
    await tester.pump(const Duration(milliseconds: 700));
  });

  test('listenable 按作品区分，空键退回全局', () {
    final a = WatchProgressStore.listenable('L', 'a');
    final b = WatchProgressStore.listenable('L', 'b');
    final none = WatchProgressStore.listenable('', '');
    expect(identical(a, b), isFalse);
    expect(identical(none, WatchProgressStore.revision), isTrue);
    expect(identical(a, WatchProgressStore.listenable('L', 'a')), isTrue);
  });

  test('写入只通知对应作品的通知器', () {
    var aTicks = 0;
    var bTicks = 0;
    WatchProgressStore.listenable('L', 'a').addListener(() => aTicks++);
    WatchProgressStore.listenable('L', 'b').addListener(() => bTicks++);

    WatchProgressStore.record(
        lib: 'L', id: 'a', positionMs: 9000, durationMs: 30000, force: true);
    expect(aTicks, 1);
    expect(bTicks, 0);

    WatchProgressStore.markDone(lib: 'L', id: 'a');
    expect(aTicks, 2);
    expect(bTicks, 0);

    WatchProgressStore.remove('L', 'b');
    expect(bTicks, 0); // 本来就没有记录，不发通知
  });
}
