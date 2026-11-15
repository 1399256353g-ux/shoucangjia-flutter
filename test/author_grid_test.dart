import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_grid.dart';

void main() {
  group('I7 作者网格几何', () {
    test('手机宽度下按最大卡片宽度分列', () {
      final g = authorGridGeometry(width: 390);
      expect(g.columns, 3);
      expect(g.cellWidth, closeTo((390 - 24 - 20) / 3, 0.001));
      expect(g.rowExtent, closeTo(g.cellWidth / 0.80 + 10, 0.001));
    });

    test('平板/桌面宽度增加列数，卡片不超过上限', () {
      final g = authorGridGeometry(width: 1024);
      expect(g.columns, greaterThan(2));
      expect(g.cellWidth, lessThanOrEqualTo(132));
      expect(g.cellWidth, greaterThan(0));
    });

    test('极窄/极端宽度时至少 1 列且宽度不为负', () {
      final narrow = authorGridGeometry(width: 40);
      expect(narrow.columns, 1);
      expect(narrow.cellWidth, greaterThan(0));
      final zero = authorGridGeometry(width: 0);
      expect(zero.columns, 1);
      expect(zero.cellWidth, greaterThan(0));
      final bad = authorGridGeometry(width: 400, childAspectRatio: 0);
      expect(bad.rowExtent, greaterThan(bad.cellWidth));
    });

    test('rowsFor 向上取整并处理空列表', () {
      final g = authorGridGeometry(width: 390);
      expect(g.rowsFor(0), 0);
      expect(g.rowsFor(-3), 0);
      expect(g.rowsFor(g.columns), 1);
      expect(g.rowsFor(g.columns + 1), 2);
    });
  });

  group('I7 头像解码宽度', () {
    test('按显示尺寸 × 像素比计算', () {
      expect(avatarDecodeWidth(displaySize: 58, devicePixelRatio: 3), 174);
      expect(avatarDecodeWidth(displaySize: 58, devicePixelRatio: 2), 116);
      expect(avatarDecodeWidth(displaySize: 58, devicePixelRatio: 1), 58);
    });

    test('非法输入与上限兜底', () {
      expect(avatarDecodeWidth(displaySize: 0, devicePixelRatio: 3), 0);
      expect(avatarDecodeWidth(displaySize: -1, devicePixelRatio: 3), 0);
      expect(avatarDecodeWidth(displaySize: 58, devicePixelRatio: 0), 58);
      expect(
          avatarDecodeWidth(
              displaySize: 400, devicePixelRatio: 4, maxWidth: 512),
          512);
    });
  });

  group('I7 排序缓存逻辑', () {
    List<Map<String, Object>> items() => [
          {'name': 'b', 'p': 10, 'n': 5},
          {'name': 'a', 'p': 10, 'n': 5},
          {'name': 'c', 'p': 99, 'n': 1},
          {'name': 'd', 'p': 10, 'n': 8},
        ];

    test('按指标降序、同分按作品数、再按名称升序', () {
      final out = sortAuthorEntries(items(),
          metric: (e) => e['p'] as num,
          works: (e) => e['n'] as num,
          name: (e) => e['name'] as String);
      expect(out.map((e) => e['name']).toList(), ['c', 'd', 'a', 'b']);
    });

    test('返回新列表，不修改入参', () {
      final src = items();
      final before = src.map((e) => e['name']).toList();
      final out = sortAuthorEntries(src,
          metric: (e) => e['p'] as num,
          works: (e) => e['n'] as num,
          name: (e) => e['name'] as String);
      expect(identical(out, src), isFalse);
      expect(src.map((e) => e['name']).toList(), before);
    });
  });
}
