import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_letter_bar.dart';

void main() {
  Widget host({
    required List<String> letters,
    required ValueChanged<String> onLetter,
    Duration hide = const Duration(milliseconds: 400),
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: Row(children: [
            const Expanded(child: SizedBox()),
            SizedBox(
              height: 400,
              child: AuthorLetterBar(
                letters: letters,
                onLetter: onLetter,
                hudHideDelay: hide,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  testWidgets('点字母：回调一次，并出现放大浮层', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(host(
        letters: const ['A', 'B', 'C', 'D'], onLetter: picked.add));
    await tester.tap(find.text('B'));
    await tester.pump();
    expect(picked, ['B']);
    // 浮层里的同一字母是大字号；文本控件数量从 4 变 5
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts.length, 5);
    expect(texts.any((t) => t.style?.fontSize == 44), isTrue);
  });

  testWidgets('浮层在松手后隐藏', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(host(
        letters: const ['A', 'B'], onLetter: picked.add));
    await tester.tap(find.text('A'));
    await tester.pump();
    expect(tester.widgetList<Text>(find.byType(Text)).length, 3);
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.widgetList<Text>(find.byType(Text)).length, 2);
  });

  testWidgets('按住下滑：穿过多个字母，每个新字母只回调一次', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(host(
        letters: const ['A', 'B', 'C', 'D', 'E'], onLetter: picked.add));
    final bar = find.byType(AuthorLetterBar);
    final rect = tester.getRect(bar);
    final gesture = await tester.startGesture(
        Offset(rect.center.dx, rect.top + rect.height / 10));
    await tester.pump();
    // 从 A 滑到 E：拖到最底
    await gesture.moveTo(Offset(rect.center.dx, rect.bottom - 2));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    // 只保留首次出现的字母顺序，不重复
    expect(picked.first, 'A');
    expect(picked.last, 'E');
    expect(picked.toSet().length, picked.length);
  });

  testWidgets('同一字母内滑动不重复回调', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(host(
        letters: const ['A', 'B'], onLetter: picked.add));
    final rect = tester.getRect(find.byType(AuthorLetterBar));
    final gesture = await tester.startGesture(
        Offset(rect.center.dx, rect.top + 10));
    await tester.pump();
    await gesture.moveTo(Offset(rect.center.dx, rect.top + 30));
    await tester.pump();
    await gesture.moveTo(Offset(rect.center.dx, rect.top + 50));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(picked, ['A']);
  });

  testWidgets('空字母表不渲染索引条', (tester) async {
    await tester.pumpWidget(host(letters: const [], onLetter: (_) {}));
    expect(find.byType(AuthorLetterBar), findsOneWidget);
    expect(tester.widgetList<Text>(find.byType(Text)).length, 0);
  });

  // owner 2026-11-25：字母改成「固定行高 + 整体居中」后，不再按 height/count
  // 均分。整列占 count * kAuthorLetterRowHeight，上下各有对称留白。
  test('命中测试：固定行高 + 居中留白', () {
    const h = kAuthorLetterRowHeight;
    // 4 个字母 = 52dp 整列，200dp 高度上下各留 74dp。
    final top = (200 - 4 * h) / 2;
    expect(AuthorLetterBar.hitIndex(dy: 0, height: 200, count: 4), 0,
        reason: '顶部留白区夹到第 0 个');
    expect(AuthorLetterBar.hitIndex(dy: top, height: 200, count: 4), 0);
    expect(AuthorLetterBar.hitIndex(dy: top + h + 1, height: 200, count: 4), 1);
    expect(AuthorLetterBar.hitIndex(dy: top + 3 * h + 1, height: 200, count: 4), 3);
    expect(AuthorLetterBar.hitIndex(dy: 900, height: 200, count: 4), 3,
        reason: '超出底部夹到末字母');
    expect(AuthorLetterBar.hitIndex(dy: -5, height: 200, count: 4), 0);
    // 非法输入
    expect(AuthorLetterBar.hitIndex(dy: 5, height: 0, count: 4), 0,
        reason: '高度为 0 时不越界即可');
    expect(AuthorLetterBar.hitIndex(dy: 5, height: 200, count: 0), -1);
  });

  test('字母少时整列紧凑，不从整高均分', () {
    const h = kAuthorLetterRowHeight;
    // 只有 3 个字母时，整列高 39dp，远小于可用高度。
    expect(3 * h, lessThan(60));
    // 相邻字母的判定边界只差一个行高，而不是 200/3。
    final top = (200 - 3 * h) / 2;
    final i0 = AuthorLetterBar.hitIndex(dy: top + 1, height: 200, count: 3);
    final i1 = AuthorLetterBar.hitIndex(dy: top + h + 1, height: 200, count: 3);
    expect(i1 - i0, 1);
  });
}
