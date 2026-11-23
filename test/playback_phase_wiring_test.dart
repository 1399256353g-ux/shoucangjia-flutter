import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_state.dart';

/// 播放相位接线（第 1 步：与旧布尔量并行）的契约测试。
///
/// 播放页 `_feed()` 依赖这两个扩展来判断「相位与旧布尔量是否一致」：
/// 相位说该转圈时，旧的 `loading` 也必须在转圈；说该暂停时，旧的
/// `paused` 也必须是暂停。若这两个映射被人改动，并行期会立刻报大量
/// mismatch，所以用测试钉住。
void main() {
  group('相位 → 显示映射（并行期一致性契约）', () {
    test('idle / opening 显示 loading', () {
      expect(PlaybackPhase.idle.showsLoading, isTrue);
      expect(PlaybackPhase.opening.showsLoading, isTrue);
    });

    test('ready / playing / buffering / paused / failed 不显示 loading', () {
      for (final p in <PlaybackPhase>[
        PlaybackPhase.ready,
        PlaybackPhase.playing,
        PlaybackPhase.buffering,
        PlaybackPhase.paused,
        PlaybackPhase.failed,
      ]) {
        expect(p.showsLoading, isFalse, reason: 'phase=$p');
      }
    });

    test('paused / failed 显示暂停态', () {
      expect(PlaybackPhase.paused.showsPaused, isTrue);
      expect(PlaybackPhase.failed.showsPaused, isTrue);
    });

    test('playing / buffering / ready / opening / idle 不显示暂停态', () {
      for (final p in <PlaybackPhase>[
        PlaybackPhase.idle,
        PlaybackPhase.opening,
        PlaybackPhase.ready,
        PlaybackPhase.playing,
        PlaybackPhase.buffering,
      ]) {
        expect(p.showsPaused, isFalse, reason: 'phase=$p');
      }
    });

    test('loading 与 paused 不会同时为真（显示层互斥）', () {
      for (final p in PlaybackPhase.values) {
        expect(
          p.showsLoading && p.showsPaused,
          isFalse,
          reason: 'phase=$p 同时要求 loading 与暂停，显示会打架',
        );
      }
    });
  });

  group('播放页事件序列：起播 → 播放 → 暂停 → 恢复', () {
    PlaybackPhase run(List<PlaybackEvent> events) {
      var p = PlaybackPhase.idle;
      for (final e in events) {
        p = nextPhase(p, e);
      }
      return p;
    }

    test('open → mediaReady → play 从转圈走到播放', () {
      final p = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.mediaReady,
        PlaybackEvent.play,
      ]);
      expect(p, PlaybackPhase.playing);
      expect(p.showsLoading, isFalse);
      expect(p.showsPaused, isFalse);
    });

    test('opening 期间的 progress 不切走 loading（起播仍显示转圈）', () {
      final p = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.progress,
      ]);
      expect(p, PlaybackPhase.opening);
      expect(p.showsLoading, isTrue);
    });

    test('open → mediaReady → play → pause 显示暂停且不转圈', () {
      final p = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.mediaReady,
        PlaybackEvent.play,
        PlaybackEvent.pause,
      ]);
      expect(p, PlaybackPhase.paused);
      expect(p.showsLoading, isFalse);
      expect(p.showsPaused, isTrue);
    });

    test('暂停后迟到的 progress 不能把界面刷回播放', () {
      final p = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.mediaReady,
        PlaybackEvent.play,
        PlaybackEvent.pause,
        PlaybackEvent.progress,
      ]);
      expect(p, PlaybackPhase.paused);
    });

    test('暂停后 play 恢复播放', () {
      final p = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.mediaReady,
        PlaybackEvent.play,
        PlaybackEvent.pause,
        PlaybackEvent.play,
      ]);
      expect(p, PlaybackPhase.playing);
      expect(p.showsPaused, isFalse);
    });

    test('失败态只能被 open 带出，迟到的 play 救不活', () {
      final failed = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.error,
      ]);
      expect(failed, PlaybackPhase.failed);
      final stillFailed = nextPhase(failed, PlaybackEvent.play);
      expect(stillFailed, PlaybackPhase.failed);
      expect(nextPhase(failed, PlaybackEvent.open), PlaybackPhase.opening);
    });
  });
}
