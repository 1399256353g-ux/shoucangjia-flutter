import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/preload_plan.dart';

void main() {
  group('preloadMediaPath', () {
    test('视频取第一个视频文件', () {
      expect(
        preloadMediaPath({
          't': 'v',
          'm': ['a/1.mp4', 'a/2.mp4'],
        }),
        'a/1.mp4',
      );
    });

    test('图文取背景音频', () {
      expect(preloadMediaPath({'t': 'p', 'm': ['a.jpg'], 'au': 'a.mp3'}), 'a.mp3');
    });

    test('纯图片/空数据没有可缓冲媒体', () {
      expect(preloadMediaPath({'t': 'p', 'm': ['a.jpg']}), isNull);
      expect(preloadMediaPath({'t': 'v', 'm': <String>[]}), isNull);
      expect(preloadMediaPath(null), isNull);
    });
  });

  test('preloadKeyFor 区分库/作品/媒体', () {
    final w = {'id': '42', 't': 'v', 'm': ['x.mp4']};
    expect(preloadKeyFor(w, 'douyin'), 'douyin|42|x.mp4');
    expect(preloadKeyFor(w, 'other'), isNot(preloadKeyFor(w, 'douyin')));
  });

  test('shouldPreloadNext 仅在连播且非单条循环时成立', () {
    expect(
      shouldPreloadNext(
          autoplay: true, loopOne: false, index: 0, count: 3, hasMedia: true),
      isTrue,
    );
    expect(
      shouldPreloadNext(
          autoplay: false, loopOne: false, index: 0, count: 3, hasMedia: true),
      isFalse,
    );
    expect(
      shouldPreloadNext(
          autoplay: true, loopOne: true, index: 0, count: 3, hasMedia: true),
      isFalse,
    );
    expect(
      shouldPreloadNext(
          autoplay: true, loopOne: false, index: 3, count: 3, hasMedia: true),
      isFalse,
    );
    expect(
      shouldPreloadNext(
          autoplay: true, loopOne: false, index: 2, count: 3, hasMedia: false),
      isFalse,
    );
  });

  test('preloadMatches 要求序号与键同时一致', () {
    expect(
      preloadMatches(
          preloadedIndex: 2, preloadedKey: 'a|2|x', index: 2, key: 'a|2|x'),
      isTrue,
    );
    expect(
      preloadMatches(
          preloadedIndex: 1, preloadedKey: 'a|2|x', index: 2, key: 'a|2|x'),
      isFalse,
    );
    expect(
      preloadMatches(
          preloadedIndex: 2, preloadedKey: 'a|1|x', index: 2, key: 'a|2|x'),
      isFalse,
    );
    expect(
      preloadMatches(preloadedIndex: 2, preloadedKey: '', index: 2, key: ''),
      isFalse,
    );
  });
}
