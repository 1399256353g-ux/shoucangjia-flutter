import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_flow.dart';

void main() {
  group('图文播放（F31）', () {
    test('单条循环：最后一张后回到第一张，不切下一条（无音频）', () {
      expect(
          slideshowAction(index: 2, count: 3, loopOne: true, hasAudio: false),
          SlideshowAction.restartImages);
    });

    test('单条循环：有音频图文同样回到第一张', () {
      expect(slideshowAction(index: 2, count: 3, loopOne: true, hasAudio: true),
          SlideshowAction.restartImages);
    });

    test('单条循环：单图作品每轮都停在当前作品', () {
      expect(
          slideshowAction(index: 0, count: 1, loopOne: true, hasAudio: false),
          SlideshowAction.restartImages);
    });

    test('未开循环但仍有背景音乐：图片循环到歌曲结束', () {
      expect(
          slideshowAction(index: 4, count: 5, loopOne: false, hasAudio: true),
          SlideshowAction.restartImages);
    });

    test('未开循环且无音频：一轮放完切下一条', () {
      expect(
          slideshowAction(index: 4, count: 5, loopOne: false, hasAudio: false),
          SlideshowAction.nextWork);
    });

    test('未到最后一张：前进一张', () {
      expect(slideshowAction(index: 0, count: 5, loopOne: true, hasAudio: true),
          SlideshowAction.nextImage);
    });
  });

  group('视频播放完成（F31/F32）', () {
    test('单条循环优先：即使连播开启也重播本条', () {
      expect(
          videoEndAction(loopOne: true, autoplay: true), VideoEndAction.replay);
    });

    test('单条循环且连播关闭：重播本条', () {
      expect(videoEndAction(loopOne: true, autoplay: false),
          VideoEndAction.replay);
    });

    test('未循环 + 连播：下一条', () {
      expect(videoEndAction(loopOne: false, autoplay: true),
          VideoEndAction.nextWork);
    });

    test('未循环 + 不连播：停在当前视频', () {
      expect(
          videoEndAction(loopOne: false, autoplay: false), VideoEndAction.stop);
    });
  });

  group('切条起播与兜底（F32）', () {
    test('切条过程忽略播放器事件，但结束后按用户意图起播', () {
      expect(shouldAutoPlay(paused: false, opening: true), isFalse);
      expect(shouldAutoPlay(paused: false, opening: false), isTrue);
    });

    test('用户在切条中暂停后不再自动起播', () {
      expect(shouldAutoPlay(paused: true, opening: false), isFalse);
    });

    test('媒体就绪但未播放且用户未暂停：需要补 play', () {
      expect(
          shouldForcePlay(
              paused: false,
              opening: false,
              playerPlaying: false,
              hasMedia: true),
          isTrue);
    });

    test('播放器已在播放/用户暂停/无媒体时不干预', () {
      expect(
          shouldForcePlay(
              paused: false,
              opening: false,
              playerPlaying: true,
              hasMedia: true),
          isFalse);
      expect(
          shouldForcePlay(
              paused: true,
              opening: false,
              playerPlaying: false,
              hasMedia: true),
          isFalse);
      expect(
          shouldForcePlay(
              paused: false,
              opening: false,
              playerPlaying: false,
              hasMedia: false),
          isFalse);
    });

    test('连播与单条循环独立：四种组合判定稳定', () {
      expect(videoEndAction(loopOne: false, autoplay: true),
          VideoEndAction.nextWork);
      expect(
          videoEndAction(loopOne: true, autoplay: true), VideoEndAction.replay);
      expect(videoEndAction(loopOne: true, autoplay: false),
          VideoEndAction.replay);
      expect(
          videoEndAction(loopOne: false, autoplay: false), VideoEndAction.stop);
    });

    test('图文进度条拖动换算目标图片下标', () {
      expect(picIndexAtFraction(0.0, 4), 0);
      expect(picIndexAtFraction(0.24, 4), 0);
      expect(picIndexAtFraction(0.25, 4), 1);
      expect(picIndexAtFraction(0.74, 4), 2);
      expect(picIndexAtFraction(0.99, 4), 3);
      expect(picIndexAtFraction(1.0, 4), 3);
      // 越界夹紧
      expect(picIndexAtFraction(-0.5, 4), 0);
      expect(picIndexAtFraction(1.5, 4), 3);
      // 单张/空列表不越界
      expect(picIndexAtFraction(0.7, 1), 0);
      expect(picIndexAtFraction(0.7, 0), 0);
    });
  });
}
