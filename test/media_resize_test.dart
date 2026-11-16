import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/media_resize.dart';

void main() {
  group('withImageWidth', () {
    test('静态图片地址追加 w=', () {
      expect(
        withImageWidth('/media/lib-001/a/cover.jpg', 480),
        '/media/lib-001/a/cover.jpg?w=480',
      );
      expect(
        withImageWidth('http://192.168.2.4:8090/media/x/1.JPEG', 200),
        'http://192.168.2.4:8090/media/x/1.JPEG?w=200',
      );
    });

    test('带 query 时用 & 续接，已有 w= 不重复', () {
      expect(
        withImageWidth('/media/a/b.jpg?v=3', 440),
        '/media/a/b.jpg?v=3&w=440',
      );
      expect(
        withImageWidth('/media/a/b.jpg?w=300', 440),
        '/media/a/b.jpg?w=300',
      );
      expect(
        withImageWidth('/media/a/b.jpg?v=3&w=300', 440),
        '/media/a/b.jpg?v=3&w=300',
      );
    });

    test('fragment 保持在末尾', () {
      expect(
        withImageWidth('/media/a/b.jpg#frag', 480),
        '/media/a/b.jpg?w=480#frag',
      );
      expect(
        withImageWidth('/media/a/b.jpg?v=1#f', 480),
        '/media/a/b.jpg?v=1&w=480#f',
      );
    });

    test('非图片/非静态资源原样返回', () {
      for (final u in <String>[
        '',
        'asset:avatars/x.jpg',
        'data:image/png;base64,AAAA',
        '/media/a/clip.mp4',
        '/api/thumb/lib-001/7300000000000000000',
        'relative/path.jpg',
      ]) {
        expect(withImageWidth(u, 480), u, reason: u);
      }
    });

    test('pkg/webp 也生效，扩展名大小写不敏感', () {
      expect(withImageWidth('/media/a/b.png', 64), '/media/a/b.png?w=64');
      expect(withImageWidth('/media/a/b.WebP', 64), '/media/a/b.WebP?w=64');
    });

    test('宽度非法时原样返回；空白串按空处理', () {
      expect(withImageWidth('/media/a/b.jpg', 0), '/media/a/b.jpg');
      expect(withImageWidth('/media/a/b.jpg', -1), '/media/a/b.jpg');
      expect(withImageWidth('   ', 480), '   ');
    });

    test('常量用于卡片/头像且互不相同', () {
      expect(kCardImageWidth, greaterThanOrEqualTo(360));
      expect(kWorkImageWidth, greaterThanOrEqualTo(360));
      expect(kAvatarImageWidth, greaterThanOrEqualTo(128));
      // 卡片比头像大，避免头像取到过小图糊掉。
      expect(kCardImageWidth, greaterThan(kAvatarImageWidth));
    });
  });
}
