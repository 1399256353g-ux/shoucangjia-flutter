import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_error.dart';

void main() {
  // 回归：播放器错误消息几乎一定带媒体 URL，而 URL 里的 `http` 会让旧的
  // 「整条消息子串匹配」把每一条错误都判成网络失败——解码失败被显示成
  // 「网络连接失败」，用户按提示去查网络等于白查。
  group('错误分类必须先剥掉 URL 再匹配关键词', () {
    const url = 'http://192.168.2.4:8090/media/lib-001/VID/a.mp4';

    test('解码器初始化失败 → decode（不被 URL 里的 http 带偏）', () {
      final f = classifyPlaybackError(
          'MediaCodecRenderer: Failed to initialize decoder for $url');
      expect(f.kind, PlaybackFailureKind.decode);
      expect(f.title, '播放失败');
    });

    test('格式不支持 → decode', () {
      final f = classifyPlaybackError(
          'Unsupported format video/hevc while opening $url');
      expect(f.kind, PlaybackFailureKind.decode);
    });

    test('明确的连接失败 → network', () {
      final f = classifyPlaybackError(
          'Failed to connect to $url: Connection refused');
      expect(f.kind, PlaybackFailureKind.network);
    });

    test('HTTP 状态码错误 → network', () {
      final f = classifyPlaybackError('HttpDataSource error 404 for $url');
      expect(f.kind, PlaybackFailureKind.network);
    });

    test('裸 /media/ 路径同样被剥掉，不污染关键词', () {
      final f = classifyPlaybackError(
          'decoder init failed /media/lib-001/VID/b.mp4');
      expect(f.kind, PlaybackFailureKind.decode);
    });

    test('既无网络词也无解码词 → unknown', () {
      final f = classifyPlaybackError('something odd happened at $url');
      expect(f.kind, PlaybackFailureKind.unknown);
    });

    test('空消息仍回 unknown', () {
      expect(classifyPlaybackError(null).kind, PlaybackFailureKind.unknown);
      expect(classifyPlaybackError('').kind, PlaybackFailureKind.unknown);
    });
  });
}
