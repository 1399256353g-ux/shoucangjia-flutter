import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/category_tree.dart';

CategoryNode tree() => CategoryNode(
      name: '库根',
      rel: '',
      children: [
        CategoryNode(
          name: 'A',
          rel: 'A',
          children: [
            CategoryNode(
              name: 'B',
              rel: 'A/B',
              authors: const ['张三', '李四'],
              children: [
                CategoryNode(name: 'C', rel: 'A/B/C', authors: const ['王五']),
              ],
            ),
          ],
        ),
        CategoryNode(name: 'D', rel: 'D', authors: const ['赵六']),
      ],
      authors: const ['根作者'],
    );

void main() {
  group('splitCatRel / rewriteRel', () {
    test('统一分隔符并去掉空段', () {
      expect(splitCatRel('a//b/'), ['a', 'b']);
      expect(splitCatRel('a\\b'), ['a', 'b']);
      expect(splitCatRel(''), isEmpty);
    });

    test('前缀替换只作用于子树', () {
      expect(rewriteRel('A/B/C', 'A/B', 'A/X'), 'A/X/C');
      expect(rewriteRel('A/B', 'A/B', 'A/X'), 'A/X');
      expect(rewriteRel('A/BC', 'A/B', 'A/X'), 'A/BC');
      expect(rewriteRel('D', 'A/B', 'A/X'), 'D');
    });
  });

  group('parseCategoryTree', () {
    test('递归解析 dirs/authors，并按名称排序', () {
      final t = parseCategoryTree({
        'name': '基础库',
        'authors': ['@库里作者'],
        'dirs': [
          {
            'name': 'Z',
            'rel': 'Z',
            'authors': <String>[],
            'dirs': <dynamic>[],
          },
          {
            'name': 'A',
            'rel': 'A',
            'authors': ['@张三'],
            'dirs': [
              {'name': 'B', 'rel': 'A/B', 'authors': ['@李四']},
            ],
          },
        ],
      })!;
      expect(t.name, '基础库');
      expect(t.authors, ['库里作者']);
      expect(t.children.map((c) => c.name), ['A', 'Z']);
      expect(t.children.first.authors, ['张三']);
      expect(t.children.first.children.single.rel, 'A/B');
    });

    test('结构不合法返回 null', () {
      expect(parseCategoryTree({'name': 'x'}), isNull);
    });
  });

  group('treeFromPaths', () {
    test('普通目录是分类，@ 目录是作者叶子', () {
      final t = treeFromPaths([
        'A/B/@张三',
        'A/B/@李四',
        'A/C/@王五',
        'D/@赵六',
      ])!;
      expect(t.children.map((c) => c.name), ['A', 'D']);
      final a = t.children.first;
      expect(a.children.map((c) => c.name), ['B', 'C']);
      expect(a.children.first.authors, ['张三', '李四']);
      expect(a.authorCount, 3);
      expect(t.childCategoryCount, 4);
      expect(t.allAuthors.first, '@张三');
      expect(t.childCategoryCount, 4);
      expect(a.children.first.isLeaf, isTrue);
    });

    test('无路径时返回空树', () {
      final t = treeFromPaths(const [])!;
      expect(t.children, isEmpty);
      expect(t.authorCount, 0);
    });
  });

  group('validateCategoryName', () {
    test('合法名称', () {
      expect(validateCategoryName('旅行'), isNull);
      expect(validateCategoryName('2026 夏天'), isNull);
    });

    test('非法名称给出原因', () {
      expect(validateCategoryName('  '), '名称不能为空');
      expect(validateCategoryName('..'), isNotNull);
      expect(validateCategoryName('a/b'), contains('/'));
      expect(validateCategoryName('.hidden'), isNotNull);
      expect(validateCategoryName('_cover'), isNotNull);
      expect(validateCategoryName('@张三'), isNotNull);
      expect(validateCategoryName('a' * 81), isNotNull);
      // 首尾空格会被自动 trim，不算非法
      expect(validateCategoryName('abc '), isNull);
    });

    test('作者目录名允许 @，仍禁用路径分隔符', () {
      expect(validateAuthorDirName('@张三'), isNull);
      expect(validateAuthorDirName('a/b'), isNotNull);
      expect(validateAuthorDirName(''), isNotNull);
    });
  });

  group('renameNodeInTree', () {
    test('改名节点并递归改写子树路径', () {
      final t = renameNodeInTree(tree(), 'A/B', '新B')!;
      final b = t.findByRel('A/新B')!;
      expect(b.name, '新B');
      expect(b.authors, ['张三', '李四']);
      expect(b.children.single.rel, 'A/新B/C');
      expect(t.findByRel('A/B'), isNull);
      expect(t.findByRel('D')!.authors, ['赵六']);
    });

    test('库根不可改名，找不到目标返回 null', () {
      expect(renameNodeInTree(tree(), '', 'X'), isNull);
      expect(renameNodeInTree(tree(), 'NOPE', 'X'), isNull);
      expect(renameNodeInTree(tree(), 'A', '  '), isNull);
    });

    test('改名只影响目标子树，兄弟不受影响', () {
      final t = renameNodeInTree(tree(), 'D', 'E')!;
      expect(t.children.map((c) => c.name), ['A', 'E']);
      expect(t.findByRel('A/B/C'), isNotNull);
    });
  });

  group('filterCategoryTree', () {
    test('空查询原样返回', () {
      final t = tree();
      expect(filterCategoryTree(t, '  ').children.length, t.children.length);
    });

    test('命中子节点保留祖先', () {
      final f = filterCategoryTree(tree(), '王五');
      expect(f.children.single.name, 'A');
      expect(f.children.single.children.single.name, 'B');
      expect(f.children.single.children.single.children.single.name, 'C');
    });

    test('命中分类名保留整棵子树', () {
      final f = filterCategoryTree(tree(), 'b');
      expect(f.children.single.name, 'A');
      final b = f.children.single.children.single;
      expect(b.name, 'B');
      expect(b.children.single.name, 'C');
      expect(b.authors.length, 2);
    });

    test('无命中时为空树', () {
      final f = filterCategoryTree(tree(), '不存在');
      expect(f.children, isEmpty);
      expect(f.authors, isEmpty);
    });
  });

  group('expandedForQuery', () {
    test('返回命中节点的祖先路径', () {
      expect(expandedForQuery(tree(), '王五'), {'A', 'A/B', 'A/B/C'});
      expect(expandedForQuery(tree(), '赵六'), {'D'});
      expect(expandedForQuery(tree(), ''), isEmpty);
      expect(expandedForQuery(tree(), '无'), isEmpty);
    });
  });

  group('subtitle / counts', () {
    test('摘要文案', () {
      expect(tree().findByRel('D')!.subtitle, '1 位作者');
      expect(tree().findByRel('A')!.subtitle, '2 个分类 · 3 位作者');
    });
  });
}
