import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_filter.dart';
import 'package:shoucangjia/author_filter_bar.dart';

void main() {
  test('pickOnlyIn 只收敛目标维度，其他维度不动', () {
    final f = AuthorFilterState(
      bigs: {'big-01', 'big-02'},
      grades: {'S'},
      types: {'video'},
    );
    pickOnlyIn(f.bigs, 'big-03');
    expect(f.bigs, {'big-03'});
    expect(f.grades, {'S'});
    expect(f.types, {'video'});
    pickOnlyIn(f.bigs, '');
    expect(f.bigs, isEmpty);
    expect(f.isActive, isTrue); // 等级/类型仍在
  });

  test('pickOnlyIn 幂等，空 id 等效清空', () {
    final f = AuthorFilterState(units: {'u1'});
    pickOnlyIn(f.units, '');
    pickOnlyIn(f.units, '');
    expect(f.units, isEmpty);
    pickOnlyIn(f.units, 'u9');
    pickOnlyIn(f.units, 'u9');
    expect(f.units, {'u9'});
  });

  testWidgets('快捷条：全部/单项选中态与单选回调', (tester) async {
    final picked = <String>[];
    var selected = <String>{};

    Widget build() => MaterialApp(
          home: Scaffold(
            body: AuthorQuickChips(
              allLabel: '全部单元库',
              items: const [
                AuthorLibNode(id: 'u1', name: '单元一'),
                AuthorLibNode(id: 'u2', name: '单元二'),
              ],
              selected: selected,
              onPick: (id) {
                picked.add(id);
                selected = id.isEmpty ? <String>{} : {id};
              },
            ),
          ),
        );

    await tester.pumpWidget(build());
    // 未选中任何库 → 「全部」处于选中态
    expect(
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('quick-chip-all'))).selected,
        isTrue);

    await tester.tap(find.byKey(const ValueKey('quick-chip-u2')));
    await tester.pumpWidget(build());
    await tester.pump();
    expect(picked, ['u2']);
    expect(
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('quick-chip-u2'))).selected,
        isTrue);
    expect(
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('quick-chip-all'))).selected,
        isFalse);

    // 重复点同一项不再回调
    await tester.tap(find.byKey(const ValueKey('quick-chip-u2')));
    await tester.pump();
    expect(picked, ['u2']);

    // 点「全部」清空
    await tester.tap(find.byKey(const ValueKey('quick-chip-all')));
    await tester.pumpWidget(build());
    await tester.pump();
    expect(picked, ['u2', '']);
  });

  testWidgets('快捷条：多选时各项都不点亮，全部也不点亮', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AuthorQuickChips(
          allLabel: '全部基础库',
          items: const [
            AuthorLibNode(id: 'b1', name: '库一'),
            AuthorLibNode(id: 'b2', name: '库二'),
          ],
          selected: const {'b1', 'b2'},
          onPick: (_) {},
        ),
      ),
    ));
    for (final k in ['all', 'b1', 'b2']) {
      expect(
          tester.widget<ChoiceChip>(find.byKey(ValueKey('quick-chip-$k'))).selected,
          isFalse,
          reason: '多选时 $k 不应伪造单选态');
    }
  });
}
