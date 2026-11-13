import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_flow.dart';

void main() {
  group('图文播放（F31）', () {
    test('单条循环：最后一张后回到第一张，不切下一条（无音频）', () {
      expect(
          slideshowAction(
              index: 2, count: 3, loopOne: true, hasAudio: false),
          SlideshowAction.restartImages);
    });

    test('单条循环：有音频图文同样回到第一张', () {
      expect(
          slideshowAction(
              index: 2, count: 3, loopOne: true, hasAudio: true),
          SlideshowAction.restartImages);
    });

    test('单条循环：单图作品每轮都停在当前作品', () {
      expect(
          slideshowAction(
              index: 0, count: 1, loopOne: true, hasAudio: false),
          SlideshowAction.restartImages);
    });

    test('未开循环但仍有背景音乐：图片循环到歌曲结束', () {
      expect(
          slideshowAction(
              index: 4, count: 5, loopOne: false, hasAudio: true),
          SlideshowAction.restartImages);
    });

    test('未开循环且无音频：一轮放完切下一条', () {
      expect(
          slideshowAction(
              index: 4, count: 5, loopOne: false, hasAudio: false),
          SlideshowAction.nextWork);
    });

    test('未到最后一张：前进一张', () {
      expect(
          slideshowAction(
              index: 0, count: 5, loopOne: true, hasAudio: true),
          SlideshowAction.nextImage);
    });
  });

  group('视频播放完成（F31/F32）', () {
    test('单条循环优先：即使连播开启也重播本条', () {
      expect(videoEndAction(loopOne: true, autoplay: true),
          VideoEndAction.replay);
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
}
