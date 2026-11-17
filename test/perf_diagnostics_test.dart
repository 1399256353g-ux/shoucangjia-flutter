import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/perf_diagnostics.dart';

void main() {
  group('perfLogLine', () {
    final at = DateTime(2026, 11, 17, 23, 14, 5, 123);

    test('时间戳带毫秒，字段保持顺序', () {
      final line = perfLogLine(at, 'span', <String, Object?>{
        'name': 'page:player',
        'ms': 42,
      });
      expect(line, startsWith('2026-11-17T23:14:05.123 span'));
      expect(line, contains('name=page:player'));
      expect(line, contains('ms=42'));
      expect(line.indexOf('name='), lessThan(line.indexOf('ms=')));
    });

    test('值里的换行替换成空格，空值省略', () {
      final line = perfLogLine(at, 'x', <String, Object?>{
        'a': 'line1\nline2',
        'b': '   ',
        'c': null,
      });
      expect(line.contains('\n'), isFalse);
      expect(line, contains('a=line1 line2'));
      expect(line.contains('b='), isFalse);
      expect(line.contains('c='), isFalse);
    });

    test('本地时间各段补零', () {
      final line = perfLogLine(DateTime(2026, 1, 2, 3, 4, 5, 6), 't');
      expect(line, startsWith('2026-01-02T03:04:05.006 t'));
    });
  });

  group('perfLogNeedsTruncate', () {
    test('超过上限才截断', () {
      expect(perfLogNeedsTruncate(100, maxBytes: 100), isFalse);
      expect(perfLogNeedsTruncate(101, maxBytes: 100), isTrue);
      expect(perfLogNeedsTruncate(101, maxBytes: 0), isFalse);
    });
  });

  group('perfLogDirDefault', () {
    test('Windows 固定 E 盘，其它平台临时目录', () {
      expect(perfLogDirDefault(isWindows: true), r'E:\Dizi\logs');
      expect(
          perfLogDirDefault(isWindows: false, tempDir: '/tmp/x'),
          '/tmp/x/dizi_logs');
    });
  });

  group('PerfDiagnostics', () {
    late Directory tmp;
    late DateTime now;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('perf-diag-test');
      now = DateTime(2026, 11, 17, 23, 0, 0);
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    PerfDiagnostics make({String? dir, bool writeFile = false}) =>
        PerfDiagnostics(
          logDir: dir ?? tmp.path,
          clock: () => now,
          writeFile: writeFile,
        );

    test('首帧耗时与启动阶段打点', () {
      final p = make();
      p.markAppStart();
      now = now.add(const Duration(milliseconds: 850));
      p.step('cache');
      now = now.add(const Duration(milliseconds: 150));
      p.markFirstFrame();
      expect(p.firstFrameMs, const Duration(milliseconds: 1000));
      expect(p.timeline.any((l) => l.contains('startup step=cache ms=850')),
          isTrue);
      expect(p.timeline.any((l) => l.contains('first_frame ms=1000')), isTrue);
      p.stopHeartbeat();
    });

    test('槽位创建/释放计数与峰值；不会出现负数存活', () {
      final p = make();
      p.slotCreated();
      p.slotCreated();
      p.slotCreated();
      p.slotsReleased(2);
      expect(p.slotsAlive, 1);
      expect(p.slotsPeak, 3);
      expect(p.slotsCreated, 3);
      expect(p.slotsDisposed, 2);
      p.slotsReleased(5);
      expect(p.slotsAlive, 0);
    });

    test('解码并发记录峰值与等待', () {
      final p = make();
      p.recordDecode(active: 2, waiting: 1, limit: 4);
      p.recordDecode(active: 4, waiting: 6, limit: 4);
      p.recordDecode(active: 1, waiting: 0, limit: 2);
      expect(p.decodePeakActive, 4);
      expect(p.decodePeakWaiting, 6);
      expect(p.decodeSamples, 3);
      expect(p.snapshot()['decode_peak_active'], 4);
    });

    test('span 记录毫秒，未 begin 记 -1', () {
      final p = make();
      p.beginSpan('page:x');
      now = now.add(const Duration(milliseconds: 33));
      p.endSpan('page:x', <String, Object?>{'works': 12});
      p.endSpan('page:missing');
      expect(p.timeline.any((l) => l.contains('name=page:x ms=33')), isTrue);
      expect(p.timeline.any((l) => l.contains('name=page:missing ms=-1')), isTrue);
    });

    test('落盘：追加、超过上限时先清空、失败静默', () async {
      final p = make(dir: '${tmp.path}/logs', writeFile: true);
      p.log('a', <String, Object?>{'v': 1});
      await p.flush();
      final f = File(p.logPath);
      expect(await f.exists(), isTrue);
      expect(await f.readAsString(), contains('a v=1'));

      // 超限（1 MB）时先清空再写，不无限增长。
      await f.writeAsString('x' * (kPerfLogMaxBytes + 10));
      p.log('b');
      await p.flush();
      final text = await f.readAsString();
      expect(text.contains('b'), isTrue);
      expect(text.length, lessThan(kPerfLogMaxBytes));

      // 目录不可写（父路径是文件）时静默，不抛异常。
      final bad = make(dir: '${tmp.path}/not-a-dir/x', writeFile: true);
      bad.log('boom');
      await bad.flush();
    });

    test('时间线只保留最近 200 条', () {
      final p = make();
      for (var i = 0; i < kPerfTimelineLimit + 20; i++) {
        p.log('n', <String, Object?>{'i': i});
      }
      expect(p.timeline.length, kPerfTimelineLimit);
      expect(p.timeline.last, contains('i=${kPerfTimelineLimit + 19}'));
    });
  });
}
