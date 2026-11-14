import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_error.dart';

void main() {
  group('classifyPlaybackError', () {
    test('网络/HTTP 错误归为网络失败', () {
      expect(classifyPlaybackError('Connection refused').kind,
          PlaybackFailureKind.network);
      expect(classifyPlaybackError('HTTP 404 Not Found').kind,
          PlaybackFailureKind.network);
      expect(classifyPlaybackError('SocketException: reset by peer').kind,
          PlaybackFailureKind.network);
      expect(classifyPlaybackError('request timed out').kind,
          PlaybackFailureKind.network);
    });

    test('解码/格式错误归为播放失败', () {
      expect(classifyPlaybackError('Failed to decode frame').kind,
          PlaybackFailureKind.decode);
      expect(classifyPlaybackError('unsupported codec h265').kind,
          PlaybackFailureKind.decode);
      expect(classifyPlaybackError('invalid data found').kind,
          PlaybackFailureKind.decode);
    });

    test('空错误/未知错误回落通用提示', () {
      expect(classifyPlaybackError(null).kind, PlaybackFailureKind.unknown);
      expect(classifyPlaybackError('').kind, PlaybackFailureKind.unknown);
      expect(classifyPlaybackError('weird thing').kind,
          PlaybackFailureKind.unknown);
    });

    test('每种失败都有标题、说明且可重试', () {
      for (final f in [
        networkFailure,
        decodeFailure,
        timeoutFailure,
        unknownFailure
      ]) {
        expect(f.title, isNotEmpty);
        expect(f.detail, isNotEmpty);
        expect(f.retryable, isTrue);
      }
    });

    test('网络失败优先于 failed to open 类文案', () {
      expect(classifyPlaybackError('failed to open http://x: 503').kind,
          PlaybackFailureKind.network);
    });
  });

  group('playbackLoadTimedOut', () {
    test('未到时长的超时判定', () {
      expect(
          playbackLoadTimedOut(playbackLoadTimeout.inMilliseconds - 1,
              hasDuration: false),
          isFalse);
      expect(
          playbackLoadTimedOut(playbackLoadTimeout.inMilliseconds,
              hasDuration: false),
          isTrue);
    });

    test('已拿到时长则永不判超时', () {
      expect(
          playbackLoadTimedOut(playbackLoadTimeout.inMilliseconds * 3,
              hasDuration: true),
          isFalse);
    });
  });
}
