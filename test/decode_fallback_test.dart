import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/decode_fallback.dart';
import 'package:shoucangjia/playback_error.dart';

void main() {
  group('hwdecFor', () {
    test('默认走安全硬件解码', () {
      expect(hwdecFor(DecodeMode.hardware), 'auto-safe');
    });
    test('软件解码强制关闭 hwdec', () {
      expect(hwdecFor(DecodeMode.software), 'no');
    });
  });

  group('shouldRetryWithSoftwareDecode', () {
    bool retry(PlaybackFailureKind? kind,
            {DecodeMode mode = DecodeMode.hardware,
            bool alreadyRetried = false,
            bool isVideo = true,
            bool tokenAlive = true}) =>
        shouldRetryWithSoftwareDecode(
          kind: kind,
          mode: mode,
          alreadyRetried: alreadyRetried,
          isVideo: isVideo,
          tokenAlive: tokenAlive,
        );

    test('视频解码错误在硬件模式下重试一次', () {
      expect(retry(PlaybackFailureKind.decode), isTrue);
      expect(retry(PlaybackFailureKind.unknown), isTrue);
    });

    test('网络/超时/数据问题不重试', () {
      expect(retry(PlaybackFailureKind.network), isFalse);
      expect(retry(PlaybackFailureKind.timeout), isFalse);
      expect(retry(PlaybackFailureKind.data), isFalse);
      expect(retry(null), isFalse);
    });

    test('已重试过不再重试（防坏文件死循环）', () {
      expect(retry(PlaybackFailureKind.decode, alreadyRetried: true), isFalse);
    });

    test('已经是软件解码 / 非视频 / 页面已销毁都不重试', () {
      expect(
          retry(PlaybackFailureKind.decode, mode: DecodeMode.software), isFalse);
      expect(retry(PlaybackFailureKind.decode, isVideo: false), isFalse);
      expect(retry(PlaybackFailureKind.decode, tokenAlive: false), isFalse);
    });
  });

}
