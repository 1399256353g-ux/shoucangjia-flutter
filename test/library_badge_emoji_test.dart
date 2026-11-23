import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/unit_library_view.dart';

void main() {
  setUp(() => LibraryBadge.emoji.clear());

  test('emoji 后缀与 id 形式无关（node:rel 与 rel 共用一份）', () {
    LibraryBadge.emoji['node:(1) A/(2) B'] = '🔥';
    expect(LibraryBadge.emojiFor('node:(1) A/(2) B'), '🔥');
    expect(LibraryBadge.emojiFor('(1) A/(2) B'), '🔥');
    LibraryBadge.emoji
      ..clear()
      ..['(3) C'] = '⭐';
    expect(LibraryBadge.emojiFor('node:(3) C'), '⭐');
  });

  test('SECRET 与空 id 不显示后缀，词条折叠项不加后缀', () {
    LibraryBadge.emoji['secret'] = '💧';
    expect(LibraryBadge.emojiFor('secret'), '');
    expect(LibraryBadge.emojiFor(''), '');
    expect(LibraryBadge.labelWithEmoji('+2', 'x'), '+2');
    expect(LibraryBadge.labelWithEmoji('', 'x'), '');
  });

  test('词条文字 = 去序号名称 + 后缀', () {
    LibraryBadge.emoji['k'] = '🎬';
    expect(LibraryBadge.labelWithEmoji('名称', 'k'), '名称🎬');
    expect(LibraryBadge.labelWithEmoji('名称', 'unknown'), '名称');
  });

  test('输入清洗：去空白、限长 8 个 UTF-16 单元', () {
    expect(LibraryBadge.sanitizeEmoji(' 🐾 \n'), '🐾');
    expect(LibraryBadge.sanitizeEmoji('abcdefghij'), 'abcdefgh');
    expect(LibraryBadge.sanitizeEmoji('🔥🔥🔥🔥🔥'), '🔥🔥🔥🔥');
    expect(LibraryBadge.sanitizeEmoji(''), '');
  });

  test('emoji 设置序列化可往返且容错', () {
    final raw = LibraryBadge.encodeEmoji(source: {'a': '🔥', 'b': '⭐'});
    expect(LibraryBadge.parseEmoji(raw), {'a': '🔥', 'b': '⭐'});
    expect(LibraryBadge.parseEmoji('not json'), isEmpty);
    expect(LibraryBadge.parseEmoji('{"a": 3, "b": "  ", "c": "🎯"}'),
        {'c': '🎯'});
  });

  testWidgets('LibBadgeChip 渲染后缀，"+N" 折叠项不受影响', (tester) async {
    expect(LibraryBadge.emojiChoices, contains('🔥'));
    LibraryBadge.emoji['unit-1'] = '💎';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          LibBadgeChip(
              label: '单元库',
              color: LibraryBadge.palette.first,
              unitId: 'unit-1'),
          LibBadgeChip(
              label: '+2', color: LibraryBadge.gray, unitId: 'unit-1'),
        ]),
      ),
    ));
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(texts, contains('单元库💎'));
    expect(texts, contains('+2'));
  });

  testWidgets('库卡片标题追加单元库 emoji 后缀（与词条同一规则）', (tester) async {
    LibraryBadge.emoji['unit-1'] = '💎';

    Future<void> pump({String unitId = 'unit-1'}) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LibCardInfo(
                title: '单元库',
                unitId: unitId,
                stats: '2 作者 · 3 作品',
              ),
            ),
          ),
        );

    await pump();
    expect(find.text('单元库💎'), findsOneWidget);

    // 不属于任何单元库的库卡片标题不加后缀。
    await pump(unitId: '');
    expect(find.text('单元库'), findsOneWidget);
  });
}

