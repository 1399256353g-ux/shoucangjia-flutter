import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_index.dart';

void main() {
  group('作者首字母索引（owner 2026-11-22 / 中文拼音 2026-11-23）', () {
    test('拉丁字母取大写，无法识别归 #', () {
      expect(authorIndexLetter('alice'), 'A');
      expect(authorIndexLetter('  @Bob '), 'B');
      expect(authorIndexLetter('123'), '#');
      expect(authorIndexLetter(''), '#');
    });

    test('汉字取拼音首字母', () {
      expect(authorIndexLetter('海安幼儿园'), 'H');
      expect(authorIndexLetter('银子'), 'Y');
      expect(authorIndexLetter('@阿狸'), 'A');
      expect(authorIndexLetter('沈星'), 'S');
    });

    test('姓氏多音字按姓氏读音（不是词典首读音）', () {
      expect(authorIndexLetter('曾小贤'), 'Z');
      expect(authorIndexLetter('解雨臣'), 'X');
      expect(authorIndexLetter('单田芳'), 'S');
      expect(authorIndexLetter('仇英'), 'Q');
      expect(authorIndexLetter('查良镛'), 'Z');
      // 词典型读音与姓氏读音一致的字仍走词典
      expect(authorIndexLetter('任正非'), 'R');
    });

    test('汉字识别覆盖基本区/扩展A/兼容区', () {
      expect(isHanChar('海'), isTrue);
      expect(isHanChar('A'), isFalse);
      expect(isHanChar('1'), isFalse);
      expect(isHanChar(''), isFalse);
    });

    test('排序键：A–Z 在前，# 在最后，同组按名称', () {
      final names = ['海安幼儿园', 'bob', 'Alice', '#tag', 'carol', '1号'];
      names.sort(compareAuthorNames);
      expect(names, ['Alice', 'bob', 'carol', '海安幼儿园', '#tag', '1号']);
      expect(compareAuthorNames('bob', 'carol') < 0, isTrue);
    });

    test('中文与同字母拉丁名落进同一组', () {
      expect(authorIndexLetter('海安'), authorIndexLetter('hello'));
      expect(authorIndexLetters(['海安', 'Hello']), ['H']);
    });

    test('本地过滤：大小写不敏感、忽略 @、空词返回全部', () {
      expect(authorMatchesQuery('Alice', 'ali'), isTrue);
      expect(authorMatchesQuery('@Alice', 'ALI'), isTrue);
      expect(authorMatchesQuery('Alice', 'bob'), isFalse);
      expect(authorMatchesQuery('海安幼儿园', '海安'), isTrue);
      expect(authorMatchesQuery('Alice', '   '), isTrue);
    });

    test('索引条只含存在的分组，顺序固定', () {
      expect(
          authorIndexLetters(['bob', 'Alice', '海安', 'Bob']), ['A', 'B', 'H']);
      expect(authorIndexLetters(['海安']), ['H']);
      expect(authorIndexLetters([]), isEmpty);
    });

    test('分组首位下标', () {
      final starts = authorGroupStarts(['Alice', 'Ann', 'Bob', '海安']);
      expect(starts['A'], 0);
      expect(starts['B'], 2);
      expect(starts['H'], 3);
    });
  });

  // 原有一组「均分命中」用例，测的是已删除的 `authorLetterHitIndex`
  // （零调用、规则与真实字母条不同）。真实命中规则在
  // `AuthorLetterBar.hitIndex`，用例在 `author_letter_bar_test.dart`。
  // 这里改为钉住「作者索引模块不再自己造一套命中规则」。
  test('字母条命中规则不属于本模块（避免第二套规则复活）', () {
    final src = File('lib/author_index.dart')
        .readAsStringSync().replaceAll('\r\n', '\n')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(src.contains('authorLetterHitIndex'), isFalse,
        reason: '均分实现又回来了：与 AuthorLetterBar.hitIndex 会分叉');
    expect(src.contains('.floor()'), isFalse,
        reason: '索引模块里不该再有「按高度算格子」的取整逻辑');
  });

  group('作者网格跳转偏移', () {
    test('首项为 0', () {
      expect(
          authorGridOffsetForIndex(
              index: 0, viewportWidth: 400, maxScrollExtent: 999),
          0);
    });

    test('按列数折算行高（宽 400 → 2 列，与 Flutter delegate 一致）', () {
      // avail = 400-24 = 376; columns = ceil(376/190) = 2（旧写法
      // ceil((376+10)/190) = 3 多算一列，真机上整行错位）
      // childWidth = (376-10)/2 = 183; height = 183/0.86 ≈ 212.79
      // index 3 → row 1 → offset = 12 + (212.79 + 10) = 234.79
      final off = authorGridOffsetForIndex(
          index: 3, viewportWidth: 400, maxScrollExtent: 9999);
      expect(off, closeTo(234.791, 0.01));
    });

    test('夹在 maxScrollExtent 内', () {
      final off = authorGridOffsetForIndex(
          index: 100, viewportWidth: 400, maxScrollExtent: 300);
      expect(off, 300);
    });

    test('异常宽度不抛异常', () {
      expect(
          authorGridOffsetForIndex(
              index: 5, viewportWidth: 0, maxScrollExtent: 0),
          0);
    });
  });

  group('作者网格偏移：左右内边距分别计入（索引条让位）', () {
    test('索引条可见时右侧 34、左侧 12 → 宽 400 只排 2 列', () {
      // avail = 400 - 12 - 34 = 354；columns = ceil((354+10)/190) = 2
      // childWidth = (354-10)/2 = 172；height = 172/0.86 = 200
      // index 2 → row 1 → offset = 12 + (200 + 10) = 222
      final off = authorGridOffsetForIndex(
        index: 2,
        viewportWidth: 400,
        maxScrollExtent: 9999,
        paddingRight: authorGridPadRight(hasIndexBar: true),
      );
      expect(off, closeTo(222, 0.01));
    });

    test('没有索引条时两侧 12 → 宽 400 排 2 列', () {
      final off = authorGridOffsetForIndex(
        index: 3,
        viewportWidth: 400,
        maxScrollExtent: 9999,
      );
      expect(off, closeTo(234.791, 0.01));
    });

    test('两侧不同内边距会改变列数：宽 600 时 4 列 vs 3 列', () {
      // 可用宽 600-12-12=576 → ceil(576/190)=4 列（第 3 项在第 0 行）；
      // 让出索引条 600-12-34=554 → ceil(554/190)=3 列（第 3 项落到第 1 行）。
      // 这条钉的是「列数按实际可用宽算」，不再用「右侧让位必更靠下」的
      // 旧假设——宽 400 时两者都是 2 列，行号相同，只有行高不同。
      final noBar = authorGridOffsetForIndex(
        index: 3,
        viewportWidth: 600,
        maxScrollExtent: 99999,
      );
      final withBar = authorGridOffsetForIndex(
        index: 3,
        viewportWidth: 600,
        maxScrollExtent: 99999,
        paddingRight: authorGridPadRight(hasIndexBar: true),
      );
      expect(noBar, 12); // 4 列：第 3 项仍在首行
      expect(withBar, greaterThan(noBar)); // 3 列：第 3 项在第 1 行
    });

    test('authorGridPadRight：索引条 28 + 间隙 6，否则 12', () {
      expect(authorGridPadRight(hasIndexBar: true), 34);
      expect(authorGridPadRight(hasIndexBar: false), 12);
    });
  });
}
