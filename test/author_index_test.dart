import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_index.dart';

void main() {
  group('作者首字母索引（owner 2026-11-22）', () {
    test('拉丁字母取大写，其余归 #', () {
      expect(authorIndexLetter('alice'), 'A');
      expect(authorIndexLetter('  @Bob '), 'B');
      expect(authorIndexLetter('海安幼儿园'), '#');
      expect(authorIndexLetter('123'), '#');
      expect(authorIndexLetter(''), '#');
    });

    test('排序键：A–Z 在前，# 在最后，同组按名称', () {
      final names = ['海安幼儿园', 'bob', 'Alice', '#tag', 'carol', '1号'];
      names.sort(compareAuthorNames);
      expect(names, ['Alice', 'bob', 'carol', '#tag', '1号', '海安幼儿园']);
      // 同组内名称递增
      expect(compareAuthorNames('bob', 'carol') < 0, isTrue);
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
          ['A', 'B', '#']);
      expect(authorIndexLetters(['海安']), ['#']);
      expect(authorIndexLetters([]), isEmpty);
    });

    test('分组首位下标', () {
      final starts = authorGroupStarts(['Alice', 'Ann', 'Bob', '海安']);
      expect(starts['A'], 0);
      expect(starts['B'], 2);
      expect(starts['#'], 3);
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
