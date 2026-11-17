import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/crash_guard.dart';
import 'package:shoucangjia/crash_reports_page.dart';

void main() {
  group('crashTailOf', () {
    test('短日志原样返回，不加截断提示', () {
      const raw = '2026-11-17T09:00:00 [界面] 崩了\n#0 fn';
      final out = crashTailOf(raw);
      expect(out, raw);
      expect(out.contains('已截断'), isFalse);
    });

    test('空内容返回空串（空白也算空）', () {
      expect(crashTailOf(''), isEmpty);
      expect(crashTailOf('   \n\n '), isEmpty);
    });

    test('超过行数上限只留最近的若干行，并标注截断', () {
      final raw = List.generate(50, (i) => 'line-$i').join('\n');
      final out = crashTailOf(raw, maxLines: 10);
      expect(out.startsWith('…（已截断，仅显示最近的日志）'), isTrue);
      expect(out.contains('line-49'), isTrue);
      expect(out.contains('line-40'), isTrue);
      expect(out.contains('line-39'), isFalse);
    });

    test('超过字符上限保留尾部；切到代理对中间时丢掉半个码元', () {
      final raw = '${'a' * 100}😀尾';
      final aligned = crashTailOf(raw, maxChars: 3);
      expect(aligned.endsWith('😀尾'), isTrue, reason: '3 个码元正好是高代理项+低代理项+尾');

      final split = crashTailOf(raw, maxChars: 2);
      expect(split.endsWith('尾'), isTrue);
      expect(split.contains('😀'), isFalse, reason: '半个 emoji 不应显示成方框');
      expect(split.contains('\uFFFD'), isFalse);
      expect(split.startsWith('…（已截断'), isTrue);
    });
  });

  group('落盘日志读写', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('crash-log-test');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('文件不存在时返回空串 / null', () async {
      final p = '${tmp.path}/nope/crash.log';
      expect(await readCrashLogTail(path: p), isEmpty);
      expect(await crashLogFileInfo(path: p), isNull);
    });

    test('读取尾部并给出大小/时间描述', () async {
      final f = File('${tmp.path}/crash.log');
      f.writeAsStringSync('old line\nnew line\n');
      final tail = await readCrashLogTail(path: f.path);
      expect(tail, contains('new line'));
      final info = await crashLogFileInfo(path: f.path);
      expect(info, isNotNull);
      expect(info!, contains('B'));
      expect(info, contains('最近写入'));
    });

    test('文件很大时只读尾部，且从整行开始', () async {
      final f = File('${tmp.path}/big.log');
      final head = '${'x' * 600}' * 100; // 60 KB
      f.writeAsStringSync('$head\n最后一条错误\n');
      final tail = await readCrashLogTail(path: f.path, readBytes: 1024);
      expect(tail, contains('最后一条错误'));
      expect(tail.startsWith('最后一条错误'), isTrue,
          reason: '从文件中段读起时要丢掉那半截行');
      expect(tail.length, lessThan(4000));
    });

    test('中文与 emoji 按 UTF-8 正确解出，不乱码', () async {
      final f = File('${tmp.path}/utf8.log');
      f.writeAsStringSync('封面加载失败 😀🔥\n', encoding: utf8);
      final tail = await readCrashLogTail(path: f.path);
      expect(tail, contains('封面加载失败'));
      expect(tail, contains('😀'));
    });
  });

  testWidgets('诊断页展示崩溃日志文件卡片，并列出路径', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CrashReportsPage()));
    await tester.pump();
    expect(find.textContaining('crash.log'), findsWidgets);
    expect(find.textContaining('崩溃日志文件：'), findsOneWidget);
  });
}
