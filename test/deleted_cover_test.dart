import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/deleted_cover.dart';

void main() {
  test('优先使用作品自带封面', () {
    final cov = deletedCoverPath(
        {'th': '/media/th.jpg', 'cv': '/media/cv.jpg', 'a': '作者'}, {
      '作者': {'av': '/media/av.jpg'}
    });
    expect(cov, '/media/th.jpg');
  });

  test('没有作品封面时退回作者头像', () {
    final cov = deletedCoverPath({'th': '', 'ti': '标题', 'a': '作者'}, {
      '作者': {'av': '/media/av.jpg'}
    });
    expect(cov, '/media/av.jpg');
  });

  test('作者不存在或头像为空时返回空串', () {
    expect(deletedCoverPath({'a': '查无此人'}, {}), '');
    expect(deletedCoverPath({'a': '作者'}, {
      '作者': {'av': '  '}
    }), '');
    expect(deletedCoverPath({}, {}), '');
  });
}
