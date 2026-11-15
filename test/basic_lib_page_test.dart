import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/basic_lib_page.dart';

void main() {
  group('作者卡片头像选择', () {
    test('有 av 时用 av', () {
      expect(
          pickAuthorAvatar(
              av: '/media/lib-01/av/me.jpg',
              fallback: '/media/lib-01/a/th.jpg'),
          '/media/lib-01/av/me.jpg');
    });

    test('av 为空时用兜底图（该作者作品首图）', () {
      expect(
          pickAuthorAvatar(av: '', fallback: '/media/lib-01/a/th.jpg'),
          '/media/lib-01/a/th.jpg');
      expect(pickAuthorAvatar(av: '   ', fallback: ' /media/x.jpg '),
          '/media/x.jpg');
    });

    test('都没有时为空（调用方回退首字占位）', () {
      expect(pickAuthorAvatar(), '');
      expect(pickAuthorAvatar(av: ' ', fallback: ''), '');
    });
  });
}
