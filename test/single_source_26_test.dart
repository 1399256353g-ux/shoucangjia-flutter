// 第四十二批契约：**脱敏漏文件名 + 字节档位跨档 + 负数计数污染排行 + 播放量自增回绕**。
//
// 主类不是「数值算错」，而是四件各自的「看起来对、其实错」：
//
//   1. 播放失败日志的脱敏只剥到**第一个空格**：媒体文件名带空格是常态
//      （`/media/库/我的 作品.mp4`），剩下的 `作品.mp4` 原样写进 pause.log。
//      AGENTS.md 明令「文件名不上传云端、不进模型」，而截断后的日志看起来
//      已经脱敏 —— 这是本批最重要的一条。
//   2. 字节文案四个档位各有一个 1 字节宽的跨档窗口：1048575 B（1 MB − 1）
//      先判 `kb < 1024` 成立，再 `toStringAsFixed(1)` **四舍五入**成
//      `1024.0 KB`。1024 KB 就是 1 MB，这行字是一个不可能存在的读数。
//   3. 库排行总播放量用裸加：服务端下发一个 `p: -100` 的条目就能把整库
//      拉成 `-50 播放`（计数器重置/占位值），看起来像「播放量被扣掉了」。
//   4. 本地播放量自增 `count + 1`：prefs 是普通 JSON，一条写成 int 上限的
//      记录再播一次就回绕成 **-9223372036854775808**，`topPlayed` 永远选不到
//      它，自动封面静默退回默认图。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/byte_size.dart';
import 'package:shoucangjia/library_rank.dart';
import 'package:shoucangjia/playback_error.dart';
import 'package:shoucangjia/work_plays.dart';

const int _maxInt = 9223372036854775807;

List<File> _libFiles() {
  return [
    for (final f in Directory('lib').listSync())
      if (f is File && f.path.replaceAll('\\', '/').endsWith('.dart')) f
  ];
}

void main() {
  group('播放失败日志脱敏：带空格的文件名必须整段消失', () {
    test('引号包裹的路径吃掉整个文件名', () {
      final d = sanitizePlaybackErrorForLog(
          'cannot open "/media/lib/我的 作品.mp4"');
      expect(d.contains('作品'), isFalse, reason: '实际：$d');
      expect(d.contains('mp4'), isFalse);
      expect(d.contains('<path>'), isTrue);
    });

    test('裸路径带空格：只留错误措辞，不留文件名碎片', () {
      // 旧实现（`/(?:media|api)/\S*`）会输出
      // `open <path> 作品库/文件名 带空格.jpg failed`。
      final d = sanitizePlaybackErrorForLog(
          'open /media/我的 作品库/文件名 带空格.jpg failed');
      expect(d.contains('作品'), isFalse, reason: '实际：$d');
      expect(d.contains('.jpg'), isFalse);
      expect(d.contains('failed'), isTrue);
    });

    test('路径中间带空格（目录名本身含空格）同样整段消失', () {
      final d = sanitizePlaybackErrorForLog(
          'stream error at /media/lib-1/a b c.webm');
      expect(d.contains(' b '), isFalse, reason: '实际：$d');
      expect(d.contains('.webm'), isFalse);
    });

    test('URL 里的文件名带空格也不外泄', () {
      final d = sanitizePlaybackErrorForLog(
          'decoder failed for http://nas:8090/media/lib/a b.mp4');
      expect(d.contains('b.mp4'), isFalse, reason: '实际：$d');
      expect(d.contains('http'), isFalse);
    });

    test('冒号后的错误措辞要保留（不能为了脱敏把原因吃掉）', () {
      final d = sanitizePlaybackErrorForLog(
          'Failed to open /media/lib-001/VID/abc.mp4: Protocol not supported');
      expect(d.contains('abc.mp4'), isFalse);
      expect(d.contains('Protocol not supported'), isTrue, reason: '实际：$d');
    });

    test('普通无空格路径与既有四类措辞行为不变', () {
      expect(
          sanitizePlaybackErrorForLog(
              'unsupported format /media/lib-001/VID/xyz.mp4'),
          'unsupported format <path>');
      expect(
          sanitizePlaybackErrorForLog(
              'MediaCodecRenderer: Failed to initialize decoder for '
              'http://192.168.2.4:8090/media/lib-001/VID/abc.mp4'),
          contains('decoder'));
      expect(
          sanitizePlaybackErrorForLog('cannot open /media/lib/x.mp4 failed'),
          'cannot open <path> failed');
    });

    test('粘在词里的 `/media/` 不是路径起点，不误删内容', () {
      expect(sanitizePlaybackErrorForLog('x/media/not-a-path'),
          'x/media/not-a-path');
    });

    test('契约扫描：脱敏里不再用「第一个空白为止」的朴素正则', () {
      final src = File('lib/playback_error.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(src.contains(r"RegExp(r'/(?:media|api)/\S*')"), isFalse,
          reason: '回到 `\\S*` 就会在空格处截断，文件名后半段落进日志');
    });
  });

  group('字节文案：每一档的末尾都不许显示成 1024（跨档）', () {
    test('1 MB − 1 字节不再显示 `1024.0 KB`', () {
      final s = formatBytes(1024 * 1024 - 1);
      expect(s.contains('1024.0 KB'), isFalse, reason: '实际：$s');
      expect(s.endsWith('KB'), isTrue);
    });

    test('1 GB − 1 字节不再显示 `1024.0 MB`', () {
      expect(formatBytes(1024 * 1024 * 1024 - 1).contains('1024.0 MB'), isFalse);
    });

    test('1 TB − 1 字节不再显示 `1024.00 GB`', () {
      expect(
          formatBytes(1024 * 1024 * 1024 * 1024 - 1).contains('1024.00 GB'),
          isFalse);
    });

    test('每一档恰好整除时仍进下一档（既有四档行为不变）', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1536 * 1024), '1.5 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
      expect(formatBytes(1024 * 1024 * 1024 * 1024), '1.00 TB');
    });

    test('计数一律截断：宁少报也不虚假跨档（与 formatCount 同口径）', () {
      // 显示精度 0.1 KB 时，说 `1024.0 KB` 就是多报了 0.05 KB。
      expect(formatBytes(1024 * 1024 - 1), '1023.9 KB');
    });
  });

  group('库排行总数：负计数不参与累加', () {
    test('一个负条目不再把整库拉成负数', () {
      final t = libraryTotals({
        'a': {'p': -100},
        'b': {'p': 50},
      });
      expect(t.plays, 50, reason: '旧写法得到 -50，界面读作「-50 播放」');
    });

    test('全部为负时是 0，不是负数', () {
      expect(libraryTotals({'a': {'p': -5}}).plays, 0);
      expect(libraryTotals({'a': {'dr': -5}}).drops, 0);
    });

    test('正常值照常累加', () {
      final t = libraryTotals({
        'a': {'p': 10, 'dr': 2},
        'b': {'p': 5, 'dr': 1},
      });
      expect(t.plays, 15);
      expect(t.drops, 3);
    });

    test('int 上限仍然饱和（不回绕成负数）', () {
      final t = libraryTotals({
        'a': {'p': _maxInt},
        'b': {'p': _maxInt},
      });
      expect(t.plays, _maxInt);
    });

    test('排行行不再出现负播放量', () {
      final rows = buildLibraryRank(
        libs: [
          {'id': 'x', 'name': 'X'}
        ],
        stats: {
          'x': {
            'a': {'p': -100},
            'b': {'p': 50},
          }
        },
        metric: 'play',
      );
      expect(rows.single.plays, 50);
    });
  });

  group('本地播放量自增：int 上限不再回绕', () {
    test('上限 + 1 停在上限，不是 -9223372036854775808', () {
      final bumped = WorkPlay(count: _maxInt).bump();
      expect(bumped.count, _maxInt, reason: '旧写法 `count + 1` 在 int64 上回绕');
      expect(bumped.count > 0, isTrue);
    });

    test('负数计数按 0 起算（prefs 可被手改坏）', () {
      expect(WorkPlay(count: -7).bump().count, 1);
    });

    test('正常记录照常 +1', () {
      expect(WorkPlay(count: 3).bump().count, 4);
    });

    test('契约扫描：bump 不得回到裸 `count + 1`', () {
      final src = File('lib/work_plays.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(src.contains('count: count + 1,'), isFalse,
          reason: '回绕会让一条被写坏上限的记录沉到最后，自动封面静默退回默认图');
      expect(src.contains('count: addSat('), isTrue);
    });
  });

  group('契约扫描：同一件事只有一处实现', () {
    test('字节分级只在 byte_size.dart 里写（含截断辅助函数）', () {
      final offenders = _libFiles()
          .where((f) => !f.path.endsWith('byte_size.dart'))
          .where((f) =>
              f.readAsStringSync().replaceAll('\r\n', '\n').contains('String formatBytes(int n)'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty);
    });

    test('库排行总数只有 libraryTotals 一处', () {
      final offenders = _libFiles()
          .where((f) => !f.path.endsWith('library_rank.dart'))
          .where((f) => f.readAsStringSync().replaceAll('\r\n', '\n').contains('libraryTotals('))
          .map((f) => f.path)
          .toList();
      // 只允许 main.dart 之类的调用点，不允许再定义第二份同名函数。
      for (final p in offenders) {
        final src = File(p).readAsStringSync().replaceAll('\r\n', '\n');
        expect(src.contains('({int plays, int drops}) libraryTotals('), isFalse,
            reason: '$p 又写了一份 libraryTotals');
      }
    });
  });
}
