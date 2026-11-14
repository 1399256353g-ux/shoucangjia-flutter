import 'package:shoucangjia/watch_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('watchProgressKey prefixes library and skips empty id', () {
    expect(watchProgressKey(lib: 'douyin', id: '123'), 'douyin/123');
    expect(watchProgressKey(lib: '', id: '123'), '123');
    expect(watchProgressKey(lib: 'douyin', id: '  '), '');
    expect(watchProgressKey(lib: 'douyin', id: ' 9 '), 'douyin/9');
  });

  test('watchedDone uses tail margin and fraction', () {
    expect(watchedDone(positionMs: 0, durationMs: 100000), isFalse);
    expect(watchedDone(positionMs: 50000, durationMs: 100000), isFalse);
    // 剩余正好 4s
    expect(watchedDone(positionMs: 96000, durationMs: 100000), isTrue);
    // 95% 以上
    expect(watchedDone(positionMs: 95000, durationMs: 100000), isTrue);
    // 时长为 0 时不算看完
    expect(watchedDone(positionMs: 5000, durationMs: 0), isFalse);
  });

  test('resumeMs skips done/short/absent records', () {
    expect(resumeMs(null), 0);
    expect(
        resumeMs(const WatchProgress(
            positionMs: 2000, durationMs: 100000, done: false, updatedAt: 1)),
        0);
    expect(
        resumeMs(const WatchProgress(
            positionMs: 60000, durationMs: 100000, done: true, updatedAt: 1)),
        0);
    expect(
        resumeMs(const WatchProgress(
            positionMs: 60000, durationMs: 100000, done: false, updatedAt: 1)),
        59000);
    // 记录位置超出时长（文件被替换）时不续播
    expect(
        resumeMs(const WatchProgress(
            positionMs: 120000, durationMs: 100000, done: false, updatedAt: 1)),
        0);
  });

  test('parse/encode round trip and tolerate bad data', () {
    final items = {
      'douyin/1': const WatchProgress(
          positionMs: 1000, durationMs: 2000, done: false, updatedAt: 5),
      'douyin/2': const WatchProgress(
          positionMs: 2000, durationMs: 2000, done: true, updatedAt: 6),
    };
    final raw = encodeWatchProgress(items);
    final back = parseWatchProgress(raw);
    expect(back.keys.toList(), ['douyin/1', 'douyin/2']);
    expect(back['douyin/2']!.done, isTrue);
    expect(back['douyin/1']!.positionMs, 1000);

    expect(parseWatchProgress(null), isEmpty);
    expect(parseWatchProgress('not json'), isEmpty);
    expect(parseWatchProgress('[1,2,3]'), isEmpty);
    final mixed = parseWatchProgress(
        '{"ok":{"p":10,"d":100,"f":0,"t":1},"bad":"x","empty":{"p":0,"d":0}}');
    expect(mixed.keys, ['ok']);
    expect(mixed['ok']!.fraction, closeTo(0.1, 1e-9));
  });

  test('pruneWatchProgress keeps newest entries up to limit', () {
    final items = {
      for (var i = 0; i < 10; i++)
        'k$i': WatchProgress(
            positionMs: i, durationMs: 100, done: false, updatedAt: i),
    };
    final pruned = pruneWatchProgress(items, limit: 3);
    expect(pruned.length, 3);
    expect(pruned.keys.toSet(), {'k7', 'k8', 'k9'});
    // 不超限时原样返回
    expect(pruneWatchProgress(items, limit: 20).length, 10);
  });
}
