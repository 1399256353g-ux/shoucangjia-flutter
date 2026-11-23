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

  group('传输层状态码校正（mpv 实测 404）', () {
    test('404/410 → 文件不存在，且不提示重试', () {
      expect(failureForHttpStatus(404)!.kind, PlaybackFailureKind.missing);
      expect(failureForHttpStatus(410)!.kind, PlaybackFailureKind.missing);
      expect(mediaMissingFailure.retryable, isFalse);
    });

    test('401/403 → 无权访问，与「文件丢失」分开', () {
      expect(failureForHttpStatus(401)!.kind, PlaybackFailureKind.denied);
      expect(failureForHttpStatus(403)!.kind, PlaybackFailureKind.denied);
      expect(mediaDeniedFailure.retryable, isFalse);
    });

    test('其它码/空值不造新分支', () {
      expect(failureForHttpStatus(500), isNull);
      expect(failureForHttpStatus(503), isNull);
      expect(failureForHttpStatus(null), isNull);
    });

    test('纠正「网络」这类模糊归类', () {
      final corrected = withTransportStatus(networkFailure, 404);
      expect(corrected.kind, PlaybackFailureKind.missing);
      expect(withTransportStatus(unknownFailure, 403).kind,
          PlaybackFailureKind.denied);
    });

    test('已确定的解码/数据结论不被状态码覆盖', () {
      expect(withTransportStatus(decodeFailure, 404).kind,
          PlaybackFailureKind.decode);
      expect(withTransportStatus(workDataFailure, 404).kind,
          PlaybackFailureKind.data);
    });

    test('没有状态码时原样返回同一对象', () {
      expect(identical(withTransportStatus(networkFailure, null), networkFailure),
          isTrue);
    });

    test('文件不存在与无权访问都不可重试', () {
      expect(mediaMissingFailure.retryable, isFalse);
      expect(mediaDeniedFailure.retryable, isFalse);
      // 网络/超时仍可重试（弱网会变）。
      expect(networkFailure.retryable, isTrue);
      expect(timeoutFailure.retryable, isTrue);
    });
  });

  group('playbackLoadTimedOut', () {    test('未到时长的超时判定', () {
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

