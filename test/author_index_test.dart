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
      expect(authorIndexLetters(['bob', 'Alice', '海安', 'Bob']),
          ['A', 'B', 'H']);
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

  group('滑动字母条命中（owner 2026-11-22）', () {
    test('落在每格中心时命中对应字母', () {
      expect(authorLetterHitIndex(dy: 0, itemExtent: 20, count: 10), 0);
      expect(authorLetterHitIndex(dy: 10, itemExtent: 20, count: 10), 0);
      expect(authorLetterHitIndex(dy: 25, itemExtent: 20, count: 10), 1);
      expect(authorLetterHitIndex(dy: 199, itemExtent: 20, count: 10), 9);
    });

    test('上下越界夹在两端', () {
      expect(authorLetterHitIndex(dy: -50, itemExtent: 20, count: 5), 0);
      expect(authorLetterHitIndex(dy: 9999, itemExtent: 20, count: 5), 4);
    });

    test('非法输入返回 -1（调用方据此不显示索引条）', () {
      expect(authorLetterHitIndex(dy: 5, itemExtent: 0, count: 5), -1);
      expect(authorLetterHitIndex(dy: 5, itemExtent: 20, count: 0), -1);
    });
  });

  group('作者网格跳转偏移', () {
    test('首项为 0', () {
      expect(
          authorGridOffsetForIndex(
              index: 0, viewportWidth: 400, maxScrollExtent: 999),
          0);
    });

    test('按列数折算行高（宽 400 → 3 列）', () {
      // avail = 400-24 = 376; columns = ceil((376+10)/190) = 3
      // childWidth = (376-20)/3 = 118.667; height ≈ 137.98; row = 3 ~/ 3 = 1
      final off = authorGridOffsetForIndex(
          index: 3, viewportWidth: 400, maxScrollExtent: 9999);
      expect(off, closeTo(159.984, 0.01));
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
}
