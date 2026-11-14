import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/work_safety.dart';

void main() {
  group('workMediaPaths', () {
    test('正常视频/图文返回路径', () {
      expect(workMediaPaths({'t': 'v', 'm': ['a.mp4']}), ['a.mp4']);
      expect(workMediaPaths({'t': 'p', 'm': ['1.jpg', '2.jpg']}),
          ['1.jpg', '2.jpg']);
    });

    test('缺失或类型错误返回空列表且不抛异常', () {
      expect(workMediaPaths(null), isEmpty);
      expect(workMediaPaths('oops'), isEmpty);
      expect(workMediaPaths(<String, dynamic>{}), isEmpty);
      expect(workMediaPaths({'t': 'v', 'm': null}), isEmpty);
      expect(workMediaPaths({'t': 'v', 'm': 'a.mp4'}), isEmpty);
    });

    test('过滤空项并容忍非字符串元素', () {
      expect(workMediaPaths({'t': 'p', 'm': ['', null, 123, ' x.jpg ']}),
          ['123', 'x.jpg']);
    });
  });

  group('workPlayable / workIssueText', () {
    test('有媒体的视频与图文可播放', () {
      expect(workPlayable({'t': 'v', 'm': ['a.mp4']}), isTrue);
      expect(workPlayable({'t': 'p', 'm': ['a.jpg']}), isTrue);
    });

    test('空媒体、未知类型、非 Map 判为异常', () {
      expect(workPlayable({'t': 'v', 'm': <String>[]}), isFalse);
      expect(workPlayable({'t': 'p', 'm': []}), isFalse);
      expect(workPlayable({'t': 'x', 'm': ['a']}), isFalse);
      expect(workPlayable(null), isFalse);
      expect(workPlayable({'t': 'v'}), isFalse);
    });

    test('异常说明按类型区分', () {
      expect(workIssueText(null), '作品数据损坏');
      expect(workIssueText({'t': 'v'}), '视频文件缺失');
      expect(workIssueText({'t': 'p'}), '图片列表为空');
      expect(workIssueText({'t': 'z'}), '未知作品类型');
    });
  });

  test('workField 对非 Map 与缺失字段返回回退值', () {
    expect(workField(null, 'ti', 'x'), 'x');
    expect(workField({'a': '作者'}, 'a', ''), '作者');
    expect(workField({'a': '作者'}, 'ti', '无'), '无');
  });

  test('nextPlayableIndex 跳过异常条目，找不到返回 -1', () {
    final broken = {2, 4};
    bool ok(int i) => !broken.contains(i);
    expect(
        nextPlayableIndex(current: 1, count: 6, playable: ok), 3);
    expect(
        nextPlayableIndex(current: 3, count: 6, playable: ok), 5);
    expect(
        nextPlayableIndex(current: 3, count: 5, playable: ok), -1);
    expect(
        nextPlayableIndex(current: 5, count: 6, playable: ok, step: -1), 3);
    expect(nextPlayableIndex(current: 0, count: 0, playable: ok), -1);
  });
}
