import 'package:shoucangjia/work_cover.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final urls = WorkCoverUrls.standard(
    mediaUrl: (p) => 'MEDIA:$p',
    rawUrl: (p) => 'RAW:$p',
  );

  group('workCoverUrl', () {
    test('th 优先，直接走媒体地址', () {
      final w = {
        'id': 'w1',
        't': 'v',
        'th': 'A/B/thumb.jpg',
        'm': ['A/B/x.mp4'],
      };
      expect(workCoverUrl(w, lib: 'lib-001', urls: urls), 'MEDIA:A/B/thumb.jpg');
    });

    test('图文缺 th 时用 m 第一张图片（不再空白）', () {
      final w = {
        'id': 'w2',
        't': 'p',
        'th': '',
        'm': ['A/PIC/1.jpg', 'A/PIC/2.jpg'],
      };
      expect(workCoverUrl(w, lib: 'lib-002', urls: urls), 'MEDIA:A/PIC/1.jpg');
    });

    test('图文 m 首项是视频文件时跳过，不拼抽帧', () {
      final w = {
        'id': 'w3',
        't': 'p',
        'th': '',
        'm': ['A/PIC/clip.mp4'],
      };
      expect(workCoverUrl(w, lib: 'lib-002', urls: urls), '');
      expect(workNeedsFrameThumb(w), isFalse);
    });

    test('视频缺 th 走抽帧接口，并带版本参数避开旧缓存', () {
      final w = {
        'id': 'w4',
        't': 'v',
        'th': '',
        'm': ['A/VID/4.mp4'],
      };
      expect(workNeedsFrameThumb(w), isTrue);
      expect(
        workCoverUrl(w, lib: 'lib-027', urls: urls),
        'RAW:/api/thumb/lib-027/w4?v=$kWorkThumbVersion',
      );
    });

    test('视频 id 为空时不拼必然 404 的地址', () {
      final w = {'t': 'v', 'th': '', 'm': ['A/VID/5.mp4']};
      expect(workCoverUrl(w, lib: 'lib-027', urls: urls), '');
    });

    test('非 Map / 空数据返回空串', () {
      expect(workCoverUrl(null, lib: 'lib-001', urls: urls), '');
      expect(workCoverUrl('x', lib: 'lib-001', urls: urls), '');
      expect(workCoverUrl({}, lib: 'lib-001', urls: urls), '');
    });

    test('isVideoPath 覆盖常见容器', () {
      expect(isVideoPath('a/b.MP4'), isTrue);
      expect(isVideoPath('a/b.mov'), isTrue);
      expect(isVideoPath('a/b.jpg'), isFalse);
    });
  });
}
