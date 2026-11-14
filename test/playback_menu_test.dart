import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_menu.dart';
import 'package:shoucangjia/watch_progress.dart';

WatchProgress rec(int p, int d, {bool done = false}) =>
    WatchProgress(positionMs: p, durationMs: d, done: done, updatedAt: 1);

void main() {
  test('no record: only restart entry', () {
    final m = buildPlaybackMenu(isVideo: true, progress: null);
    expect(m.canResume, isFalse);
    expect(m.canMarkDone, isFalse);
    expect(m.canClear, isFalse);
    expect(m.hasRecord, isFalse);
  });

  test('video with mid-position record: resume/mark/clear all available', () {
    final m = buildPlaybackMenu(isVideo: true, progress: rec(60000, 100000));
    expect(m.canResume, isTrue);
    expect(m.resumeAtMs, 59000); // 回退 1s 避开解码边界
    expect(m.canMarkDone, isTrue);
    expect(m.canClear, isTrue);
  });

  test('watched video: no resume, no mark-done, still clearable', () {
    final m = buildPlaybackMenu(
        isVideo: true, progress: rec(99000, 100000, done: true));
    expect(m.canResume, isFalse);
    expect(m.canMarkDone, isFalse);
    expect(m.canClear, isTrue);
  });

  test('picture work: clearing record only, never resume/mark-done', () {
    final m = buildPlaybackMenu(isVideo: false, progress: rec(60000, 100000));
    expect(m.canResume, isFalse);
    expect(m.canMarkDone, isFalse);
    expect(m.canClear, isTrue);
  });

  test('formatMenuPosition pads and supports hours', () {
    expect(formatMenuPosition(0), '00:00');
    expect(formatMenuPosition(59000), '00:59');
    expect(formatMenuPosition(3599000), '59:59');
    expect(formatMenuPosition(3600000), '1:00:00');
    expect(formatMenuPosition(-5), '00:00');
  });
}
