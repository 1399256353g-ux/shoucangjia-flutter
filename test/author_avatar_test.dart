import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_avatar.dart';

void main() {
  group('avatarCandidatesFromWorks', () {
    test('图文作品取原图，视频取封面', () {
      final cs = avatarCandidatesFromWorks([
        {
          't': 'p',
          'm': ['/media/lib/a.jpg', '/media/lib/b.jpg'],
          'th': '/media/lib/thumb.jpg'
        },
        {'t': 'v', 'm': ['/media/lib/v.mp4'], 'th': '/media/lib/v.jpg'},
      ]);
      expect(cs.map((e) => e.path),
          ['/media/lib/a.jpg', '/media/lib/b.jpg', '/media/lib/v.jpg']);
      expect(cs.first.kind, 'pic');
      expect(cs.last.kind, 'video');
      expect(cs.map((e) => e.order), [0, 1, 2]);
    });

    test('没有图的条目跳过，空串忽略', () {
      final cs = avatarCandidatesFromWorks([
        {'t': 'p', 'm': <String>[], 'th': ''},
        {'t': 'v', 'th': ''},
        {'t': 'p', 'm': ['', '  ']},
      ]);
      expect(cs, isEmpty);
    });

    test('图文作品最多取 3 张，避免候选爆炸', () {
      final cs = avatarCandidatesFromWorks([
        {
          't': 'p',
          'm': ['1.jpg', '2.jpg', '3.jpg', '4.jpg', '5.jpg']
        }
      ]);
      expect(cs.length, 3);
      expect(cs.last.path, '3.jpg');
    });

    test('视频无封面但 m 有图时退化为原图', () {
      final cs = avatarCandidatesFromWorks([
        {'t': 'v', 'm': ['/media/lib/frame.jpg'], 'th': ''}
      ]);
      expect(cs.single.path, '/media/lib/frame.jpg');
      expect(cs.single.kind, 'pic');
    });
  });

  group('avatarCandidateScore / pickFallbackAvatar', () {
    test('空候选返回 null', () {
      expect(pickFallbackAvatar(const []), isNull);
      expect(pickFallbackAvatar(const [AvatarCandidate(path: '  ')]), isNull);
    });

    test('已知尺寸时偏好大且接近方形', () {
      final best = pickFallbackAvatarScored(const [
        AvatarCandidate(path: 'small.jpg', width: 150, height: 150),
        AvatarCandidate(path: 'square.jpg', width: 1080, height: 1080),
        AvatarCandidate(path: 'wide.jpg', width: 1920, height: 1080),
      ]);
      expect(best?.path, 'square.jpg');
    });

    test('尺寸未知时图文原图优于视频封面', () {
      final best = pickFallbackAvatarScored(const [
        AvatarCandidate(path: 'pic.jpg', kind: 'pic', order: 3),
        AvatarCandidate(path: 'video.jpg', kind: 'video', order: 0),
      ]);
      expect(best?.path, 'pic.jpg');
    });

    test('gif 在没有其他选择时才用', () {
      expect(
          pickFallbackAvatar(const [
            AvatarCandidate(path: 'a.gif'),
          ]),
          'a.gif');
      expect(
          pickFallbackAvatar(const [
            AvatarCandidate(path: 'a.gif'),
            AvatarCandidate(path: 'b.jpg', kind: 'video'),
          ]),
          'b.jpg');
    });

    test('尺寸过小的图被淘汰', () {
      expect(
          pickFallbackAvatar(const [
            AvatarCandidate(path: 'tiny.jpg', width: 120, height: 120),
            AvatarCandidate(path: 'ok.jpg', width: 500, height: 500),
          ]),
          'ok.jpg');
    });

    test('同清晰度时优先较新的作品', () {
      expect(
          pickFallbackAvatar(const [
            AvatarCandidate(path: 'old.jpg', order: 20),
            AvatarCandidate(path: 'new.jpg', order: 0),
          ]),
          'new.jpg');
    });
  });

  group('AvatarCropBox', () {
    test('默认中心取景在横图与竖图里都居中', () {
      final box = AvatarCropBox.centerFace();
      final (x, y, side) = box.toPixels(1200, 800);
      expect(side, 800);
      expect(x, 200);
      expect(y, 0);
    });

    test('竖图取景略微上移，框不越界', () {
      final box = AvatarCropBox.centerFace();
      final (x, y, side) = box.toPixels(800, 1200);
      expect(side, 800);
      expect(x, 0);
      expect(y, closeTo(152, 0.001));
      expect(y + side <= 1200, isTrue);
    });

    test('缩小取景框并夹在边界内', () {
      const box = AvatarCropBox(left: 1, top: 1, size: 0.5);
      final (x, y, side) = box.toPixels(1000, 600);
      expect(side, 300);
      expect(x, 700);
      expect(y, 300);
    });

    test('size 会被夹到合法区间', () {
      const tiny = AvatarCropBox(size: 0.01);
      expect(tiny.toPixels(500, 500).$3, 100);
      const huge = AvatarCropBox(size: 9);
      expect(huge.toPixels(500, 500).$3, 500);
    });
  });

  group('播放页作者兜底图', () {
    test('th 优先；没有 th 取第一张非视频媒体；全无返回空串', () {
      expect(workAvatarFallbackPath({'th': 't.jpg', 'm': ['a.mp4']}), 't.jpg');
      expect(
          workAvatarFallbackPath({
            'th': '',
            'm': ['a.mp4', 'b.webm', 'c.jpg', 'd.jpg'],
          }),
          'c.jpg');
      expect(workAvatarFallbackPath({'m': ['a.mp4']}), '');
      expect(workAvatarFallbackPath('bad'), '');
      expect(workAvatarFallbackPath(null), '');
    });

    test('按作品顺序取每个作者第一张可用图，空作者跳过', () {
      final idx = authorFallbackThumbs(<dynamic>[
        {'a': 'A', 'th': 'a1.jpg'},
        {'a': 'A', 'th': 'a2.jpg'},
        {'a': '', 'th': 'noname.jpg'},
        {'a': 'B', 'm': ['x.mp4', 'b1.jpg']},
        {'a': 'B', 'th': 'b2.jpg'},
        {'a': 'C', 'm': ['only.mp4']},
      ]);
      expect(idx['A'], 'a1.jpg');
      expect(idx['B'], 'b1.jpg');
      expect(idx.containsKey('C'), isFalse);
      expect(idx.containsKey(''), isFalse);
    });

    test('分页追加只补新作者，已记录的不覆盖', () {
      final target = <String, String>{'A': 'a1.jpg'};
      final added = addFirstThumbPerAuthor(
        target,
        <dynamic>[
          {'a': 'A', 'th': 'a9.jpg'},
          {'a': 'B', 'th': 'b1.jpg'},
        ],
        thumbOf: workAvatarFallbackPath,
      );
      expect(added, 1);
      expect(target['A'], 'a1.jpg');
      expect(target['B'], 'b1.jpg');
    });
  });
}
