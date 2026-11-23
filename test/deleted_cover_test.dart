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

  /// 删除监测列表把 `DeletedEntry.cover` 当 `th`、`author` 当 `a` 传进来。
  /// 钉住「记录无封面时退回作者头像」——0.9.185 前 deleted_cover.dart
  /// 只有测试调用，列表里无封面的行永远停在占位图标。
  group('删除监测列表的取图口径', () {
    test('记录有封面就用封面，不查作者索引', () {
      expect(
        deletedCoverPath({'th': '/media/x.jpg', 'a': '作者'}, {
          '作者': {'av': '/media/av.jpg'}
        }),
        '/media/x.jpg',
      );
    });

    test('记录无封面时退回作者头像', () {
      expect(
        deletedCoverPath({'th': '', 'a': '作者'}, {
          '作者': {'av': '/media/av.jpg'}
        }),
        '/media/av.jpg',
      );
    });

    test('索引里没有该作者时给空串，列表显示占位图标', () {
      expect(deletedCoverPath({'th': '', 'a': '查无此人'}, {}), '');
    });
  });
}
