import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/scroll_decode.dart';
import 'package:shoucangjia/thumb_prefetch.dart';

void main() {
  testWidgets('滚动开始收紧预算，结束立刻恢复', (tester) async {
    final p = ThumbPrefetch(maxConcurrent: 4, scrollMaxConcurrent: 2);
    expect(p.scrolling, isFalse);
    expect(p.effectiveLimit, 4);

    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: ScrollDecodeScope(
        prefetch: p,
        child: ListView.builder(
          controller: controller,
          itemCount: 100,
          itemExtent: 40,
          itemBuilder: (_, i) => Text('$i'),
        ),
      ),
    ));

    // 模拟一次拖拽滚动（有 ScrollStart / ScrollEnd 生命周期）。
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    // 拖拽结束时 ScrollEnd 已上报，预算恢复常规值。
    expect(p.scrolling, isFalse);
    expect(p.effectiveLimit, 4);

    // 直接验证上报逻辑：手动开始滚动状态，下一次列表拖动结束会恢复。
    p.setScrolling(true);
    expect(p.effectiveLimit, 2);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(p.scrolling, isFalse);
  });

  testWidgets('内层滚动（depth != 0）不影响预算', (tester) async {
    final p = ThumbPrefetch(maxConcurrent: 4, scrollMaxConcurrent: 2);
    await tester.pumpWidget(MaterialApp(
      home: ScrollDecodeScope(
        prefetch: p,
        child: ListView(
          children: [
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: const [
                  SizedBox(width: 200, height: 40),
                  SizedBox(width: 200, height: 40),
                ],
              ),
            ),
            for (var i = 0; i < 30; i++)
              SizedBox(height: 40, child: Text('$i')),
          ],
        ),
      ),
    ));
    await tester.drag(find.byType(ListView).last, const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(p.scrolling, isFalse);
    expect(p.effectiveLimit, 4);
  });
}
