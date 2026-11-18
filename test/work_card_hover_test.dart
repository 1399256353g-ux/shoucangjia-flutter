import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/work_card.dart';

/// 0.9.70：桌面端悬停描边改成 ValueNotifier 局部驱动。
///
/// 基准：鼠标 enter/exit 只应新增/移除一层描边，**不能**重建卡片本身
/// （`WorkCard` 元素被标脏重建＝封面子树白重绘，滚动时会掉帧）。
void main() {
  final rebuilt = <String, int>{};

  setUp(() {
    rebuilt.clear();
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      final name = e.widget.runtimeType.toString();
      rebuilt[name] = (rebuilt[name] ?? 0) + 1;
    };
  });

  tearDown(() {
    debugOnRebuildDirtyWidget = null;
  });

  Future<void> pumpCard(WidgetTester tester, List<int> builds) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 120,
            height: 160,
            child: WorkCard(
              title: '测试作品',
              typeLabel: '视频',
              coverUrl: '',
              onTap: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    // 只统计悬停引起的重建。
    rebuilt.clear();
  }

  Future<TestGesture> hoverAt(WidgetTester tester, Offset at) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: at);
    addTearDown(g.removePointer);
    return g;
  }

  testWidgets('悬停显示描边、移出移除描边', (tester) async {
    await pumpCard(tester, const []);
    expect(find.byKey(const ValueKey('work-card-hover')), findsNothing);

    final center = tester.getCenter(find.byType(WorkCard));
    final g = await hoverAt(tester, center);
    await tester.pump();
    expect(find.byKey(const ValueKey('work-card-hover')), findsOneWidget);

    await g.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(find.byKey(const ValueKey('work-card-hover')), findsNothing);
  });

  testWidgets('悬停切换不重建整张卡片', (tester) async {
    final builds = <int>[];
    await pumpCard(tester, builds);

    final center = tester.getCenter(find.byType(WorkCard));
    final g = await hoverAt(tester, center);
    await tester.pump();

    final stats = Map<String, int>.from(rebuilt);
    // ignore: avoid_print
    print('[bench] 悬停重建统计: $stats');
    expect(stats['WorkCard'] ?? 0, 0,
        reason: '悬停 enter 重建了整张 WorkCard：$stats');

    rebuilt.clear();
    await g.moveTo(const Offset(5, 5));
    await tester.pump();
    final stats2 = Map<String, int>.from(rebuilt);
    // ignore: avoid_print
    print('[bench] 移出重建统计: $stats2');
    expect(stats2['WorkCard'] ?? 0, 0,
        reason: '悬停 exit 重建了整张 WorkCard：$stats2');
  });
}
