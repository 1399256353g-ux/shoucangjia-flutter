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

  /// 播放页每条真实路径都要把用户意图喂进相位机。漏喂时相位机只是在
  /// 「自说自话」，自检告警会被假冲突淹没（0.9.185 前的实际状态）。
  /// 这里用与 main.dart 相同的序列钉住四条路径的落点。
  group('各条路径喂事件后的落点（漏喂回归）', () {
    PlaybackPhase run(List<PlaybackEvent> events) {
      var p = PlaybackPhase.idle;
      for (final e in events) {
        p = nextPhase(p, e);
      }
      return p;
    }

    test('预载命中：直接 mediaReady → play，跳过 opening 的转圈', () {
      final afterHit = run(<PlaybackEvent>[
        PlaybackEvent.mediaReady,
        PlaybackEvent.play,
      ]);
      expect(afterHit, PlaybackPhase.playing);
      // 预载命中时界面 loading=false，相位也不能是 opening。
      expect(afterHit.showsLoading, isFalse);
    });

    test('非预载：open → mediaReady → play 才离开转圈', () {
      final p = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.mediaReady,
        PlaybackEvent.play,
      ]);
      expect(p, PlaybackPhase.playing);
    });

    test('用户点暂停必须被相位采信（togglePause 喂 pause）', () {
      final p = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.mediaReady,
        PlaybackEvent.play,
        PlaybackEvent.pause,
      ]);
      expect(p.showsPaused, isTrue);
      expect(p.isActivelyPlaying, isFalse);
    });

    test('用户点恢复必须被相位采信（togglePause 喂 play）', () {
      final p = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.mediaReady,
        PlaybackEvent.play,
        PlaybackEvent.pause,
        PlaybackEvent.play,
      ]);
      expect(p.isActivelyPlaying, isTrue);
      expect(p.showsPaused, isFalse);
    });

    test('后台打开的视频保持暂停：喂 pause 而不是 play', () {
      final p = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.mediaReady,
        PlaybackEvent.pause,
      ]);
      expect(p.showsPaused, isTrue);
      expect(p.showsLoading, isFalse);
    });

    test('不可播放条目：open → pause，明确停在暂停而非空白转圈', () {
      final p = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.pause,
      ]);
      expect(p.showsPaused, isTrue);
      expect(p.showsLoading, isFalse);
    });

    test('软解重试/失败重试都从 open 重新开始', () {
      final playing = run(<PlaybackEvent>[
        PlaybackEvent.open,
        PlaybackEvent.mediaReady,
        PlaybackEvent.play,
      ]);
      expect(nextPhase(playing, PlaybackEvent.open), PlaybackPhase.opening);
    });
  });
}
