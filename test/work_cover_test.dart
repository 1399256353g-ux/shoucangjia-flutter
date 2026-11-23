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

    group('服务端接口形态的 th（2026-11-23 comics/AI 单图无封面根因）', () {
      test('th 是 /api/thumb/<lib>/<id> 时走 rawUrl，不再二次套 /media', () {
        // 实测：libidx 里 2288 条图文作品的 th 已是这种接口地址
        // （lib-005 / lib-019 / lib-021 等）；旧解析拼成
        // /media/<lib>/api/thumb/... → 服务端把 api 当子目录 → 永远 404。
        final w = {
          'id': 'w10',
          't': 'p',
          'th': '/api/thumb/lib-021/w10',
          'm': ['A/PIC/1.jpg'],
        };
        expect(isApiThumbPath('/api/thumb/lib-021/w10'), isTrue);
        expect(
          workCoverUrl(w, lib: 'lib-021', urls: urls),
          'RAW:/api/thumb/lib-021/w10',
        );
      });

      test('接口形态的 th 优先于图文首图（不因路径形态而被跳过）', () {
        final w = {
          'id': 'w11',
          't': 'p',
          'th': '/api/thumb/lib-005/w11',
          'm': ['A/PIC/later.jpg'],
        };
        expect(workCoverUrl(w, lib: 'lib-005', urls: urls),
            'RAW:/api/thumb/lib-005/w11');
        // 有接口封面就不需要服务端再抽帧
        expect(workNeedsFrameThumb(w), isFalse);
      });

      test('媒体文件形态的 th 仍然走 mediaUrl（不误判成接口）', () {
        final w = {
          'id': 'w12',
          't': 'p',
          'th': '/media/lib-001/A/thumb.webp',
          'm': const <String>[],
        };
        expect(isApiThumbPath('/media/lib-001/A/thumb.webp'), isFalse);
        expect(workCoverUrl(w, lib: 'lib-001', urls: urls),
            'MEDIA:/media/lib-001/A/thumb.webp');
      });

      test('isApiThumbPath 只认 /api/ 前缀', () {
        expect(isApiThumbPath(''), isFalse);
        expect(isApiThumbPath('  '), isFalse);
        expect(isApiThumbPath('/apix/thumb'), isFalse);
        expect(isApiThumbPath('api/thumb'), isFalse);
        expect(isApiThumbPath('/api/thumb/x/y'), isTrue);
      });
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
