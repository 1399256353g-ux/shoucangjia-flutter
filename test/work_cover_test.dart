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

  group('posterLayerVisible（播放页海报是否建层）', () {
    test('视频无 th 但能抽帧时海报必须建（有声黑屏的回归点）', () {
      final w = {
        'id': 'w9',
        't': 'v',
        'th': '',
        'm': ['A/VID/9.mp4'],
      };
      // 旧口径：按 `it['th']` 判定 → 空串 → 整层海报不建 → 首帧前全黑。
      expect(posterLayerVisible('${w['th']}'), isFalse);
      // 现口径：按解析后的封面地址判定 → 有地址就建层。
      expect(
        posterLayerVisible(workCoverUrl(w, lib: 'lib-027', urls: urls)),
        isTrue,
      );
    });

    test('真的没有封面时不建层，也不留空白填充', () {
      expect(posterLayerVisible(''), isFalse);
      expect(posterLayerVisible('   '), isFalse);
    });
  });
}
