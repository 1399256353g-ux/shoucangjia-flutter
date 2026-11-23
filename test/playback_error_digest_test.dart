import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_error.dart';

/// 诊断摘要的脱敏规则：媒体地址与文件名属于隐私，绝不能写进日志；
/// 但 `decoder` / `unsupported` / `timeout` 这类**非内容**措辞必须留下，
/// 否则失败原因无从定位（本轮就卡在只有 `failure:network` 三个字）。
void main() {
  group('播放失败诊断摘要脱敏', () {
    test('剥掉 http(s) 地址，保留错误措辞', () {
      final d = sanitizePlaybackErrorForLog(
          'MediaCodecRenderer: Failed to initialize decoder for '
          'http://192.168.2.4:8090/media/lib-001/VID/abc.mp4');
      expect(d.contains('http'), isFalse);
      expect(d.contains('192.168.2.4'), isFalse);
      expect(d.contains('abc.mp4'), isFalse);
      expect(d.contains('decoder'), isTrue);
    });

    test('剥掉裸 /media/ 路径与文件名', () {
      final d = sanitizePlaybackErrorForLog(
          'unsupported format /media/lib-001/VID/xyz.mp4');
      expect(d.contains('xyz.mp4'), isFalse);
      expect(d.contains('lib-001'), isFalse);
      expect(d.contains('unsupported'), isTrue);
    });

    test('剥掉查询串，不留鉴权/参数', () {
      final d = sanitizePlaybackErrorForLog(
          'timeout while opening /media/lib-002/a.mp4?t=abcdef&sig=secret');
      expect(d.contains('abcdef'), isFalse);
      expect(d.contains('secret'), isFalse);
      expect(d.contains('timeout'), isTrue);
    });

    test('空白折叠、长度截断到 160', () {
      final long = 'decoder   failed\n\n${'x' * 400}';
      final d = sanitizePlaybackErrorForLog(long);
      expect(d.contains('\n'), isFalse);
      expect(d.contains('  '), isFalse);
      expect(d.length, lessThanOrEqualTo(160));
    });

    test('空输入给占位而不是空串', () {
      expect(sanitizePlaybackErrorForLog(''), 'no-detail');
      expect(sanitizePlaybackErrorForLog(null), 'no-detail');
    });
  });
}
