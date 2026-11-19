import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_state.dart';

void main() {
  group('nextPhase：打开与就绪', () {
    test('idle 收到 open 进入 opening', () {
      expect(
        nextPhase(PlaybackPhase.idle, PlaybackEvent.open),
        PlaybackPhase.opening,
      );
    });

    test('opening 收到 mediaReady 进入 ready', () {
      expect(
        nextPhase(PlaybackPhase.opening, PlaybackEvent.mediaReady),
        PlaybackPhase.ready,
      );
    });

    test('open 总能从任意相位重新开始', () {
      for (final p in PlaybackPhase.values) {
        expect(
          nextPhase(p, PlaybackEvent.open),
          PlaybackPhase.opening,
          reason: 'phase=$p',
        );
      }
    });

    test('opening 期间的缓冲/进度事件保持 opening（不切走 loading）', () {
      expect(
        nextPhase(PlaybackPhase.opening, PlaybackEvent.bufferStart),
        PlaybackPhase.opening,
      );
      expect(
        nextPhase(PlaybackPhase.opening, PlaybackEvent.bufferEnd),
        PlaybackPhase.opening,
      );
      expect(
        nextPhase(PlaybackPhase.opening, PlaybackEvent.progress),
        PlaybackPhase.opening,
      );
    });
  });

  group('nextPhase：播放/暂停', () {
    test('ready + play 进入 playing，ready + pause 进入 paused', () {
      expect(
        nextPhase(PlaybackPhase.ready, PlaybackEvent.play),
        PlaybackPhase.playing,
      );
      expect(
        nextPhase(PlaybackPhase.ready, PlaybackEvent.pause),
        PlaybackPhase.paused,
      );
    });

    test('首帧进度把 ready 推到 playing', () {
      expect(
        nextPhase(PlaybackPhase.ready, PlaybackEvent.progress),
        PlaybackPhase.playing,
      );
    });

    test('paused + play 恢复播放', () {
      expect(
        nextPhase(PlaybackPhase.paused, PlaybackEvent.play),
        PlaybackPhase.playing,
      );
    });

    test('paused 下迟到的 progress/buffer 事件不把界面刷成播放', () {
      expect(
        nextPhase(PlaybackPhase.paused, PlaybackEvent.progress),
        PlaybackPhase.paused,
      );
      expect(
        nextPhase(PlaybackPhase.paused, PlaybackEvent.bufferStart),
        PlaybackPhase.paused,
      );
      expect(
        nextPhase(PlaybackPhase.paused, PlaybackEvent.bufferEnd),
        PlaybackPhase.paused,
      );
      expect(
        nextPhase(PlaybackPhase.paused, PlaybackEvent.userSeek),
        PlaybackPhase.paused,
      );
    });

    test('playing + pause 进入 paused', () {
      expect(
        nextPhase(PlaybackPhase.playing, PlaybackEvent.pause),
        PlaybackPhase.paused,
      );
    });
  });

  group('nextPhase：缓冲', () {
    test('playing 遇 bufferStart 进入 buffering，bufferEnd 回 playing', () {
      final b = nextPhase(PlaybackPhase.playing, PlaybackEvent.bufferStart);
      expect(b, PlaybackPhase.buffering);
      expect(nextPhase(b, PlaybackEvent.bufferEnd), PlaybackPhase.playing);
    });

    test('buffering 期间位置前进视为已恢复', () {
      expect(
        nextPhase(PlaybackPhase.buffering, PlaybackEvent.progress),
        PlaybackPhase.playing,
      );
    });

    test('buffering 时用户暂停直接进入 paused', () {
      expect(
        nextPhase(PlaybackPhase.buffering, PlaybackEvent.pause),
        PlaybackPhase.paused,
      );
    });
  });

  group('nextPhase：失败只有 open/mediaReady 能带出', () {
    test('任意相位遇 error 进入 failed', () {
      for (final p in PlaybackPhase.values) {
        expect(
          nextPhase(p, PlaybackEvent.error),
          PlaybackPhase.failed,
          reason: 'phase=$p',
        );
      }
    });

    test('failed 下只认 open（重试）', () {
      expect(
        nextPhase(PlaybackPhase.failed, PlaybackEvent.open),
        PlaybackPhase.opening,
      );
      expect(
        nextPhase(PlaybackPhase.failed, PlaybackEvent.play),
        PlaybackPhase.failed,
      );
      expect(
        nextPhase(PlaybackPhase.failed, PlaybackEvent.bufferEnd),
        PlaybackPhase.failed,
      );
      expect(
        nextPhase(PlaybackPhase.failed, PlaybackEvent.completed),
        PlaybackPhase.failed,
      );
    });
  });

  group('nextPhase：完成与幂等', () {
    test('playing + completed 回到 ready（保留画面）', () {
      expect(
        nextPhase(PlaybackPhase.playing, PlaybackEvent.completed),
        PlaybackPhase.ready,
      );
    });

    test('未知事件保持原相位', () {
      expect(
        nextPhase(PlaybackPhase.ready, PlaybackEvent.mediaReady),
        PlaybackPhase.ready,
      );
      expect(
        nextPhase(PlaybackPhase.playing, PlaybackEvent.play),
        PlaybackPhase.playing,
      );
      expect(
        nextPhase(PlaybackPhase.buffering, PlaybackEvent.bufferStart),
        PlaybackPhase.buffering,
      );
    });
  });

  group('PlaybackPhaseView：显示映射', () {
    test('loading 只在 idle/opening', () {
      expect(PlaybackPhase.idle.showsLoading, isTrue);
      expect(PlaybackPhase.opening.showsLoading, isTrue);
      for (final p in PlaybackPhase.values) {
        if (p == PlaybackPhase.idle || p == PlaybackPhase.opening) continue;
        expect(p.showsLoading, isFalse, reason: 'phase=$p');
      }
    });

    test('pause 图标只在 paused/failed', () {
      expect(PlaybackPhase.paused.showsPaused, isTrue);
      expect(PlaybackPhase.failed.showsPaused, isTrue);
      expect(PlaybackPhase.playing.showsPaused, isFalse);
      expect(PlaybackPhase.buffering.showsPaused, isFalse);
    });

    test('缓冲提示只在 buffering', () {
      expect(PlaybackPhase.buffering.showsBuffering, isTrue);
      for (final p in PlaybackPhase.values) {
        if (p == PlaybackPhase.buffering) continue;
        expect(p.showsBuffering, isFalse, reason: 'phase=$p');
      }
    });

    test('isActivelyPlaying 只在 playing', () {
      expect(PlaybackPhase.playing.isActivelyPlaying, isTrue);
      expect(PlaybackPhase.paused.isActivelyPlaying, isFalse);
      expect(PlaybackPhase.buffering.isActivelyPlaying, isFalse);
    });
  });
}
