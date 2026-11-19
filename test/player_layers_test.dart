import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_layers.dart';

void main() {
  group('播放进度派生（P2 渲染层隔离）', () {
    test('时长未知时为 0，不除零', () {
      expect(playbackFraction(Duration.zero, Duration.zero), 0);
      expect(playbackFraction(const Duration(seconds: 3), Duration.zero), 0);
      expect(
        playbackFraction(const Duration(seconds: 1), const Duration(seconds: -1)),
        0,
      );
    });

    test('正常比例并夹在 0..1', () {
      expect(
        playbackFraction(const Duration(seconds: 30), const Duration(minutes: 2)),
        0.25,
      );
      expect(
        playbackFraction(const Duration(minutes: 5), const Duration(minutes: 2)),
        1.0,
      );
    });

    test('位置变化只通知一次，重复值不通知', () {
      final pos = ValueNotifier<Duration>(Duration.zero);
      final dur = ValueNotifier<Duration>(const Duration(seconds: 100));
      final frac = PlaybackFraction(position: pos, duration: dur);
      addTearDown(() {
        frac.dispose();
        pos.dispose();
        dur.dispose();
      });

      expect(frac.value, 0);
      var ticks = 0;
      frac.addListener(() => ticks++);

      pos.value = const Duration(seconds: 50);
      expect(frac.value, closeTo(0.5, 1e-9));
      expect(ticks, 1);

      // 同一位置重复上报：进度不变，不应触发重绘。
      pos.value = const Duration(seconds: 50);
      expect(ticks, 1);

      dur.value = const Duration(seconds: 200);
      expect(frac.value, closeTo(0.25, 1e-9));
      expect(ticks, 2);
    });

    test('dispose 后不再跟随位置更新', () {
      final pos = ValueNotifier<Duration>(Duration.zero);
      final dur = ValueNotifier<Duration>(const Duration(seconds: 10));
      final frac = PlaybackFraction(position: pos, duration: dur);
      frac.dispose();
      pos.value = const Duration(seconds: 5);
      expect(frac.value, 0);
      pos.dispose();
      dur.dispose();
    });
  });
}
