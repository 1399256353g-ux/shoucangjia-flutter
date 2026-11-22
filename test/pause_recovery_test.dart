import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/pause_trace.dart';
import 'package:shoucangjia/playback_flow.dart';

void main() {
  group('shouldAdoptPlayerPause（非用户暂停判定）', () {
    test('播放器自己停下（无用户/后台/失败意图）不采信为暂停', () {
      expect(
        shouldAdoptPlayerPause(
            userPaused: false,
            backgroundPaused: false,
            failed: false,
            opening: false),
        isFalse,
      );
    });

    test('用户手动暂停采信', () {
      expect(
        shouldAdoptPlayerPause(
            userPaused: true,
            backgroundPaused: false,
            failed: false,
            opening: false),
        isTrue,
      );
    });

    test('切后台暂停采信', () {
      expect(
        shouldAdoptPlayerPause(
            userPaused: false,
            backgroundPaused: true,
            failed: false,
            opening: false),
        isTrue,
      );
    });

    test('失败态与切条中不覆盖', () {
      expect(
        shouldAdoptPlayerPause(
            userPaused: false,
            backgroundPaused: false,
            failed: true,
            opening: false),
        isTrue,
      );
      expect(
        shouldAdoptPlayerPause(
            userPaused: false,
            backgroundPaused: false,
            failed: false,
            opening: true),
        isTrue,
      );
    });
  });

  group('stallRecoveryAction（卡顿自救策略）', () {
    StallRecoveryAction act({
      bool userPaused = false,
      bool backgroundPaused = false,
      bool failed = false,
      bool opening = false,
      bool appForeground = true,
      bool playerPlaying = false,
      bool hasMedia = true,
      int attempts = 0,
    }) =>
        stallRecoveryAction(
          userPaused: userPaused,
          backgroundPaused: backgroundPaused,
          failed: failed,
          opening: opening,
          appForeground: appForeground,
          playerPlaying: playerPlaying,
          hasMedia: hasMedia,
          attempts: attempts,
        );

    test('用户暂停/后台/失败/切条中都不动作', () {
      expect(act(userPaused: true), StallRecoveryAction.none);
      expect(act(backgroundPaused: true), StallRecoveryAction.none);
      expect(act(failed: true), StallRecoveryAction.none);
      expect(act(opening: true), StallRecoveryAction.none);
    });

    test('不在前台或播放器仍在播不动作', () {
      expect(act(appForeground: false), StallRecoveryAction.none);
      expect(act(playerPlaying: true), StallRecoveryAction.none);
    });

    test('没有媒体（还在加载）不动作', () {
      expect(act(hasMedia: false), StallRecoveryAction.none);
    });

    test('前两次补 play，之后重开，满 3 次停手（防循环）', () {
      expect(act(), StallRecoveryAction.retryPlay);
      expect(act(attempts: 1), StallRecoveryAction.retryPlay);
      expect(act(attempts: 2), StallRecoveryAction.reopen);
      expect(act(attempts: 3), StallRecoveryAction.none);
    });
  });

  group('PauseTrace（本地暂停轨迹）', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('pause_trace_test');
      PauseTrace.logDirOverride = dir.path;
      PauseTrace.clear();
    });

    tearDown(() {
      PauseTrace.clear();
      PauseTrace.logDirOverride = null;
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('记录原因、栈与时间，保留顺序', () {
      PauseTrace.mark('user:toggle');
      PauseTrace.mark('lifecycle:hidden');
      final list = PauseTrace.pauseTraces();
      expect(list.length, 2);
      expect(list.first.reason, 'user:toggle');
      expect(list.last.reason, 'lifecycle:hidden');
      expect(list.first.line, contains('user:toggle'));
      expect(PauseTrace.dump(), contains('lifecycle:hidden'));
    });

    test('limit 取最近若干条', () {
      for (var i = 0; i < 5; i++) {
        PauseTrace.mark('r$i');
      }
      final last = PauseTrace.pauseTraces(limit: 2);
      expect(last.map((e) => e.reason), <String>['r3', 'r4']);
    });

    test('落盘到本地 pause.log（不联网）', () {
      PauseTrace.mark('stall:retryPlay#1');
      final f = File(PauseTrace.logPath);
      expect(f.existsSync(), isTrue);
      final text = f.readAsStringSync();
      expect(text, contains('stall:retryPlay#1'));
    });
  });

  group('startupSignal（起播窗口判定）', () {
    test('缓存已覆盖当前位置 → warming（慢在解码，不是 I/O）', () {
      // 0.9.159 的真实场景：3.3 GB 条目整段已缓存，增量 0，
      // buffer 596s 而位置还在 0 → 旧判据直接判卡死。
      expect(
        startupSignal(
          positionMs: 0,
          basePositionMs: 0,
          bufferMs: 596000,
          baseBufferMs: 596000,
        ),
        StartupSignal.warming,
      );
    });

    test('缓存未覆盖、但仍在增长 → filling（还在灌首帧）', () {
      expect(
        startupSignal(
          positionMs: 0,
          basePositionMs: 0,
          bufferMs: 900,
          baseBufferMs: 0,
        ),
        StartupSignal.filling,
      );
    });

    test('位置已前进 ≥300ms → advancing', () {
      expect(
        startupSignal(
          positionMs: 400,
          basePositionMs: 0,
          bufferMs: 4000,
          baseBufferMs: 0,
        ),
        StartupSignal.advancing,
      );
    });

    test('数据侧完全无进展 → stalled（真卡死）', () {
      expect(
        startupSignal(
          positionMs: 0,
          basePositionMs: 0,
          bufferMs: 500,
          baseBufferMs: 500,
        ),
        StartupSignal.stalled,
      );
    });

    test('warming 顺延到上限 → stalled，不再无限等待', () {
      expect(
        startupSignal(
          positionMs: 0,
          basePositionMs: 0,
          bufferMs: 596000,
          baseBufferMs: 596000,
          warmWaits: 2,
        ),
        StartupSignal.stalled,
      );
    });

    test('filling 顺延到上限 → stalled', () {
      // 位置 10s、缓存只到 11s（未覆盖），增量 500ms 但额度已用完。
      expect(
        startupSignal(
          positionMs: 10000,
          basePositionMs: 10000,
          bufferMs: 11000,
          baseBufferMs: 10500,
          fillWaits: 2,
        ),
        StartupSignal.stalled,
      );
    });

    test('warming 与 filling 额度互不占用', () {
      // filling 额度用完，但数据已覆盖 → 仍按 warming 处理。
      expect(
        startupSignal(
          positionMs: 0,
          basePositionMs: 0,
          bufferMs: 596000,
          baseBufferMs: 596000,
          fillWaits: 2,
        ),
        StartupSignal.warming,
      );
    });
  });
}
