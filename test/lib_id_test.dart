import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/lib_id.dart';

void main() {
  group('lib_id：node: 前缀归一', () {
    test('剥离一层前缀，裸 rel 原样返回', () {
      expect(relOf('node:A'), 'A');
      expect(relOf('A'), 'A');
      expect(relOf('  node:A/B  '), 'A/B');
    });

    test('空串/纯空白返回空串（不当成库 id）', () {
      expect(relOf(''), '');
      expect(relOf('   '), '');
    });

    test('只剥一层，不自作主张递归', () {
      // `node:node:x` 没有语义；剥一层后剩下 `node:x`，不再继续剥。
      expect(relOf('node:node:x'), 'node:x');
    });
  });

  group('lib_id：等价键顺序', () {
    test('调用方写法最优先，其次裸 rel，最后带前缀', () {
      expect(idFormsOf('node:A'), ['node:A', 'A']);
      expect(idFormsOf('A'), ['A', 'node:A']);
    });

    test('不会重复，也不会给空 id 造键', () {
      expect(idFormsOf('node:A').toSet().length, idFormsOf('node:A').length);
      expect(idFormsOf(''), isEmpty);
    });

    test('多级 rel 只取最后一段之外的原样路径', () {
      expect(idFormsOf('node:A/B'), ['node:A/B', 'A/B']);
    });
  });

  group('lib_id：查表与清除', () {
    test('两种 id 写法的设置在同一个库里都能查到', () {
      final m = <String, int>{'node:A': 0xFF0000FF};
      expect(lookupByLibId(m, 'node:A'), 0xFF0000FF);
      expect(lookupByLibId(m, 'A'), 0xFF0000FF, reason: '裸 rel 必须命中');
      final n = <String, int>{'A': 0xFF00FF00};
      expect(lookupByLibId(n, 'node:A'), 0xFF00FF00);
      expect(lookupByLibId(n, 'A'), 0xFF00FF00);
    });

    test('没设过返回 null，与设成 0 区分开', () {
      expect(lookupByLibId(<String, int>{}, 'A'), isNull);
      expect(lookupByLibId(<String, int>{'A': 0}, 'A'), 0);
    });

    test('调用方写法优先于另一种写法（顺序不可颠倒）', () {
      final m = <String, int>{'node:A': 1, 'A': 2};
      expect(lookupByLibId(m, 'node:A'), 1);
      expect(lookupByLibId(m, 'A'), 2);
    });

    test('清除时把全部等价键一起删掉', () {
      final m = <String, int>{'node:A': 1, 'A': 2, 'B': 3};
      expect(removeByLibId(m, 'node:A'), 2);
      expect(m.keys, ['B']);
      expect(removeByLibId(m, 'A'), 0, reason: '再删一次是幂等的');
    });

    test('不属于同一库的键不会被误删', () {
      final m = <String, int>{'node:AB': 1, 'AB': 2};
      expect(removeByLibId(m, 'node:A'), 0);
      expect(m.length, 2);
    });
  });
}
