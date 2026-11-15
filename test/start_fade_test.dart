import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/start_fade.dart';

void main() {
  group('I3 起播淡入', () {
    test('淡入序列从低到高且末步等于目标', () {
      final s = fadeInSteps(100, steps: 6);
      expect(s.length, 6);
      expect(s.first, closeTo(100 / 6, 0.001));
      expect(s.last, 100);
      for (var i = 1; i < s.length; i++) {
        expect(s[i], greaterThan(s[i - 1]));
      }
    });

    test('目标音量夹紧并处理 0 / 步数非法', () {
      expect(fadeInSteps(0), isEmpty);
      expect(fadeInSteps(100, steps: 0), isEmpty);
      expect(fadeInSteps(150, steps: 2), [50.0, 100.0]);
    });

    test('只在视频、未暂停、有音量时淡入', () {
      expect(shouldFadeIn(isVideo: true, paused: false, volume: 80), isTrue);
      expect(shouldFadeIn(isVideo: false, paused: false, volume: 80), isFalse);
      expect(shouldFadeIn(isVideo: true, paused: true, volume: 80), isFalse);
      expect(shouldFadeIn(isVideo: true, paused: false, volume: 0), isFalse);
    });

    test('首帧等待在拿到时长/暂停/token 失效/超预算时停止', () {
      expect(
          shouldWaitFirstFrame(
              attempt: 0,
              knownDuration: Duration.zero,
              tokenAlive: true,
              paused: false),
          isTrue);
      expect(
          shouldWaitFirstFrame(
              attempt: 0,
              knownDuration: const Duration(seconds: 1),
              tokenAlive: true,
              paused: false),
          isFalse);
      expect(
          shouldWaitFirstFrame(
              attempt: 0,
              knownDuration: Duration.zero,
              tokenAlive: true,
              paused: true),
          isFalse);
      expect(
          shouldWaitFirstFrame(
              attempt: firstFrameAttempts,
              knownDuration: Duration.zero,
              tokenAlive: true,
              paused: false),
          isFalse);
    });
  });
}
