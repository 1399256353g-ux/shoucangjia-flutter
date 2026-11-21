import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/work_author.dart';

void main() {
  group('authorNameFromWork', () {
    test('优先使用 a / author 字段', () {
      expect(authorNameFromWork({'a': '作者A', 'm': ['/x/@路径作者/v.mp4']}),
          '作者A');
      expect(authorNameFromWork({'author': '作者B'}), '作者B');
    });

    test('缺 a 时从 URL 编码的媒体路径回退（%40作者）', () {
      final w = {
        'm': [
          '/media/lib-008/%40%E5%AE%85%E3%80%90%E6%94%BB%E3%80%91/VID/x/y.mp4'
        ],
      };
      expect(authorNameFromWork(w), '宅【攻】');
    });

    test('兼容 m 为字符串 / media 字段 / 未编码 @作者', () {
      expect(authorNameFromWork({'m': '/a/@张三/v.mp4'}), '张三');
      expect(authorNameFromWork({'media': '/a/@李四/p.jpg'}), '李四');
      expect(authorNameFromWork({'path': '/a/plain.jpg'}), '');
    });

    test('展示名去掉前导 @', () {
      expect(authorDisplayNameFromWork({'a': '@王五'}), '王五');
      expect(authorDisplayNameFromWork({'a': '赵六'}), '赵六');
    });
  });

  group('authorInfoFromIndex', () {
    test('作者索引存在 作者 / @作者 两种键', () {
      final idx = {
        '甲': {'i': 1},
        '@乙': {'i': 2},
      };
      expect(authorInfoFromIndex(idx, '甲')?['i'], 1);
      expect(authorInfoFromIndex(idx, '@甲')?['i'], 1);
      expect(authorInfoFromIndex(idx, '乙')?['i'], 2);
      expect(authorInfoFromIndex(idx, '@乙')?['i'], 2);
      expect(authorInfoFromIndex(idx, '丙'), isNull);
    });
  });
}
