import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_badges.dart';

void main() {
  group('formatBadgeDuration', () {
    test('秒/分钟/小时格式化', () {
      expect(formatBadgeDuration(5), '0:05');
      expect(formatBadgeDuration(65), '1:05');
      expect(formatBadgeDuration(600), '10:00');
      expect(formatBadgeDuration(3725), '1:02:05');
      // 小数秒**截断**，不四舍五入：12.6s 的片子角标写 `0:12`，
      // 与播放页进度行（`formatClockMs(12600)` → `00:12`）同一个读数。
      // 旧写法 round 给 `0:13`，同一部片子两处差一秒。
      expect(formatBadgeDuration(12.6), '0:12');
    });

    test('不四舍五入跨档：59.5s 不是 `1:00`，3599.5s 不是 `1:00:00`', () {
      expect(formatBadgeDuration(59.5), '0:59');
      expect(formatBadgeDuration(59.9), '0:59');
      // 不满 1 小时仍走 `mm:ss`），所以 3599.5s → `59:59`。
      expect(formatBadgeDuration(3599.5), '59:59');
      expect(formatBadgeDuration(3599.9), '59:59');
    });

    test('非法或过短时返回空串', () {
      expect(formatBadgeDuration(null), '');
      expect(formatBadgeDuration(0), '');
      expect(formatBadgeDuration(-3), '');
      expect(formatBadgeDuration(double.nan), '');
      expect(formatBadgeDuration(double.infinity), '');
    });

    test('接受字符串数字', () {
      expect(formatBadgeDuration(num.tryParse('95')), '1:35');
    });
  });

  group('workCoverBadge', () {
    test('视频读 du 秒数', () {
      expect(workCoverBadge({'t': 'v', 'du': 125}), '2:05');
      expect(workCoverBadge({'t': 'v', 'du': '61'}), '1:01');
    });

    test('视频无时长时不显示', () {
      expect(workCoverBadge({'t': 'v'}), isNull);
      expect(workCoverBadge({'t': 'v', 'du': 0}), isNull);
    });

    test('图文显示张数', () {
      expect(workCoverBadge({'t': 'p', 'm': ['a', 'b', 'c']}), '3 图');
      expect(workCoverBadge({'t': 'p', 'm': ['a']}), '1 图');
      expect(workCoverBadge({'t': 'p', 'm': []}), isNull);
    });

    test('未知类型与非法数据', () {
      expect(workCoverBadge({'t': 'x'}), isNull);
      expect(workCoverBadge(null), isNull);
      expect(workCoverBadge('bad'), isNull);
    });
  });
}
