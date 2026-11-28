import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/unit_author_groups.dart';

/// owner 2026-11-28：
/// > 「不要用文件目录的方式进行设置了，列出直属单元库下所有基础库，让用户
/// >   自己选作者作品存在于直接上级单元库下哪些基础库……作品不可跨过直接上级
/// >   单元库分布，只能分布在直属单元库下的基础库内。」
void main() {
  group('挂载范围 = 直接上级单元库下的基础库', () {
    test('只包含传入范围内的基础库，不跨库', () {
      final got = basicsOfUnitScope(<String>['lib-a', 'lib-b']);
      expect(got, ['lib-a', 'lib-b']);
    });

    test('空范围就是空（不猜默认库）', () {
      expect(basicsOfUnitScope(<String>[]), isEmpty);
    });
  });

  group('勾选基础库 → 建目录请求体', () {
    test('每个基础库一条，name 用作者目录名', () {
      final bodies = createAuthorBodies(
        authorDir: '@张三',
        libs: ['lib-a', 'lib-b'],
      );
      expect(bodies, hasLength(2));
      expect(bodies[0], {'lib': 'lib-a', 'name': '@张三'});
      expect(bodies[1], {'lib': 'lib-b', 'name': '@张三'});
    });

    test('重复与空白基础库被去掉（同一库只能建一次）', () {
      final bodies = createAuthorBodies(
        authorDir: '@李四',
        libs: ['lib-a', ' lib-a ', '', '  ', 'lib-b'],
      );
      expect(bodies.map((e) => e['lib']), ['lib-a', 'lib-b']);
    });

    test('一个都不选 → 不发请求', () {
      expect(createAuthorBodies(authorDir: '@王五', libs: []), isEmpty);
    });
  });
}
