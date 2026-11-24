import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/media_priority.dart';

void main() {
  group('头像/封面优先级：手动 > 爬虫 > 自动', () {
    test('层级优先于时间', () {
      expect(
        pickAvatarPath(
          manual: '/m.jpg',
          crawler: '/c.jpg',
          auto: '/a.jpg',
          manualAt: 1,
          crawlerAt: 999,
          autoAt: 999,
        ),
        '/m.jpg',
      );
      expect(
        pickCoverPath(crawler: '/c.jpg', auto: '/a.jpg', crawlerAt: 1, autoAt: 999),
        '/c.jpg',
      );
    });

    test('同级时新的优先，未知时间视为最旧', () {
      expect(
        pickMediaPath([
          const MediaCandidate('/old.jpg', MediaTier.crawler, at: 10),
          const MediaCandidate('/new.jpg', MediaTier.crawler, at: 20),
          const MediaCandidate('/unknown.jpg', MediaTier.crawler),
        ]),
        '/new.jpg',
      );
      expect(
        pickMediaPath([
          const MediaCandidate('/unknown.jpg', MediaTier.manual),
          const MediaCandidate('/known.jpg', MediaTier.manual, at: 1),
        ]),
        '/known.jpg',
      );
    });

    test('空串候选被忽略，全部为空返回空串', () {
      expect(pickAvatarPath(manual: '  ', crawler: '', auto: ' /a.jpg '), '/a.jpg');
      expect(pickAvatarPath(), '');
      expect(pickMediaCandidate(const []), isNull);
    });

    test('清除手动设置后自动下沉到下一级', () {
      // 手动层不提供候选，等价于「清除手动设置」。
      expect(pickCoverPath(crawler: '/c.jpg', auto: '/a.jpg'), '/c.jpg');
      expect(pickCoverPath(auto: '/a.jpg'), '/a.jpg');
    });
  });
}
