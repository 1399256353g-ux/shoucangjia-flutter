import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/mpv_log_digest.dart';

void main() {
  group('mpvLogDigest 只收可行动的级别', () {
    test('error/warn/fatal 收，info/v/debug 一律丢弃', () {
      for (final lv in ['error', 'warn', 'fatal', 'ERROR', ' Warn ']) {
        expect(
          mpvLogDigest(prefix: 'ffmpeg', level: lv, text: 'Failed to open'),
          isNotNull,
          reason: 'level=$lv 应当记录',
        );
      }
      for (final lv in ['info', 'v', 'debug', 'trace', '']) {
        expect(
          mpvLogDigest(prefix: 'ffmpeg', level: lv, text: 'Failed to open'),
          isNull,
          reason: 'level=$lv 不应记录（每帧时钟会淹掉日志）',
        );
      }
    });

    test('纯地址的日志被丢弃，不把地址形状带进日志', () {
      expect(
        mpvLogDigest(
            prefix: 'stream',
            level: 'error',
            text: 'http://192.168.2.4:8090/media/lib-001/a.mp4'),
        isNull,
      );
      expect(mpvLogDigest(prefix: 'stream', level: 'error', text: '   '),
          isNull);
      expect(mpvLogDigest(prefix: 'stream', level: 'error', text: null), isNull);
    });
  });

  group('mpvLogDigest 的隐私与截断', () {
    test('地址与媒体路径不进日志正文', () {
      final d = mpvLogDigest(
        prefix: 'ffmpeg',
        level: 'error',
        text: 'tcp: Failed to open http://192.168.2.4:8090/media/lib-001/a.mp4',
      )!;
      expect(d.contains('192.168'), isFalse);
      expect(d.contains('8090'), isFalse);
      expect(d.contains('lib-001'), isFalse);
      expect(d.contains('a.mp4'), isFalse);
      // 可行动的措辞必须留下
      expect(d.toLowerCase().contains('failed to open'), isTrue);
    });

    test('正文截断到上限，且带 prefix/level 前缀', () {
      final long = 'E' * 400;
      final d = mpvLogDigest(prefix: 'vd', level: 'error', text: long)!;
      expect(d.startsWith('vd/error'), isTrue);
      // 'vd/error: ' 前缀 + 正文上限
      expect(d.length, lessThanOrEqualTo('vd/error: '.length + 120));
    });

    test('没有 prefix 时用 mpv 兜底，不留空标签', () {
      final d = mpvLogDigest(prefix: '  ', level: 'error', text: 'boom')!;
      expect(d.startsWith('mpv/error'), isTrue);
    });
  });

  group('mpvLogTag 分类顺序', () {
    test('鉴权优先于 notfound（403 不是路径写错）', () {
      expect(mpvLogTag('HTTP error 403 Forbidden'), 'auth');
      expect(mpvLogTag('HTTP error 401 Unauthorized'), 'auth');
      expect(mpvLogTag('authentication required'), 'auth');
    });

    test('404 / not found → notfound', () {
      expect(mpvLogTag('HTTP error 404 Not Found'), 'notfound');
      expect(mpvLogTag('no such file or directory'), 'notfound');
    });

    test('超时、协议、解码、打不开各自可辨', () {
      expect(mpvLogTag('Connection timed out'), 'timeout');
      expect(mpvLogTag('Protocol not supported'), 'protocol');
      expect(mpvLogTag('Failed to initialize decoder'), 'decoder');
      expect(mpvLogTag('unsupported format'), 'decoder');
      expect(mpvLogTag('Failed to open'), 'open');
    });

    test('无关键词返回空串（照常写正文，只是没标签）', () {
      expect(mpvLogTag('something odd happened'), '');
    });
  });

  group('pushMpvDigest 环形尾部', () {
    test('相邻重复丢弃，不刷屏', () {
      var tail = <String>[];
      tail = pushMpvDigest(tail, 'a');
      tail = pushMpvDigest(tail, 'a');
      tail = pushMpvDigest(tail, 'a');
      expect(tail, ['a']);
      tail = pushMpvDigest(tail, 'b');
      expect(tail, ['a', 'b']);
    });

    test('超出上限丢最旧的，保留最近', () {
      var tail = <String>[];
      for (final s in ['1', '2', '3', '4', '5', '6', '7', '8']) {
        tail = pushMpvDigest(tail, s, max: 3);
      }
      expect(tail, ['6', '7', '8']);
    });

    test('空行/none 不改变尾部；不修改传入列表', () {
      final orig = ['x'];
      expect(pushMpvDigest(orig, null), orig);
      expect(pushMpvDigest(orig, ''), orig);
      pushMpvDigest(orig, 'y');
      expect(orig, ['x'], reason: '必须返回新列表，不能就地改');
    });
  });

  group('urlShapeOf 只输出形状指标', () {
    test('长度/非 ASCII/空格/百分号/协议/端口计数正确', () {
      final url = 'http://192.168.2.4:8090/media/lib-001/a%20b c.mp4';
      final s = urlShapeOf(url);
      expect(s.length, url.length);
      expect(s.port, 8090);
      expect(s.scheme, 'http');
      expect(s.spaces, 1);
      expect(s.escapes, 1);
      expect(s.nonAscii, 0);
    });

    test('非 ASCII 与 https 分别计数', () {
      final s = urlShapeOf('https://nas:8443/media/中文.mp4');
      expect(s.scheme, 'https');
      expect(s.port, 8443);
      expect(s.nonAscii, 2);
    });

    test('无法解析时 scheme=none、port=0，但长度仍真实', () {
      final s = urlShapeOf('not a url');
      expect(s.scheme, 'none');
      expect(s.port, 0);
      expect(s.length, 'not a url'.length);
    });

    test('describeUrlShape 不含地址内容', () {
      final url = 'http://192.168.2.4:8090/media/lib-001/a.mp4';
      final line = describeUrlShape(urlShapeOf(url));
      expect(line.contains('192.168'), isFalse);
      expect(line.contains('lib-001'), isFalse);
      expect(line.contains('a.mp4'), isFalse);
      expect(line.contains('len='), isTrue);
      expect(line.contains('port=8090'), isTrue);
    });
  });
  group('httpStatusFromMpvTail', () {
    test('从 ffmpeg 前缀的日志里取出真实状态码', () {
      expect(
          httpStatusFromMpvTail(
              ['ffmpeg/warn<notfound>: http: HTTP error 404 Not Found']),
          404);
      expect(
          httpStatusFromMpvTail(
              ['ffmpeg/error<auth>: http: HTTP error 401 Unauthorized']),
          401);
      expect(
          httpStatusFromMpvTail(['ffmpeg/error<auth>: HTTP error 403']), 403);
    });

    test('只认可行动的四类码，其它归网络', () {
      expect(httpStatusFromMpvTail(['http: HTTP error 500']), isNull);
      expect(httpStatusFromMpvTail(['http: HTTP error 503']), isNull);
      expect(httpStatusFromMpvTail(['ffmpeg/warn<notfound>: 404']), isNull,
          reason: '没有 http error 前缀的零散数字不算传输层证据');
    });

    test('尾部无状态码时返回 null，不猜', () {
      expect(httpStatusFromMpvTail(const []), isNull);
      expect(httpStatusFromMpvTail(['stream/error<open>: Failed to open']),
          isNull);
    });

    test('环尾多条时命中任意一条即可（相邻重复已去重）', () {
      expect(
          httpStatusFromMpvTail([
            'cplayer/warn: something',
            'ffmpeg/warn<notfound>: http: HTTP error 404 Not Found',
            'stream/error<open>: Failed to open',
          ]),
          404);
    });
  });
}

