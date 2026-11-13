/// 播放页连播/循环的纯逻辑判定，便于单元测试。
///
/// 规则：
/// - 单条循环（loopOne）优先级最高：视频播完重播本条，图文放完一轮回到第一张，
///   不会切到下一条（无音频的图文同样循环）。
/// - 未开循环时，视频播完按自动连播决定是否下一条。
/// - 未开循环的图文：有背景音乐时图片循环到歌曲结束，否则一轮放完切下一条。
enum SlideshowAction { nextImage, restartImages, nextWork }

enum VideoEndAction { replay, nextWork, stop }

/// 图文定时器每次触发时的动作。
/// [index] 为当前图片下标，[count] 为图片张数。
SlideshowAction slideshowAction({
  required int index,
  required int count,
  required bool loopOne,
  required bool hasAudio,
}) {
  if (index < count - 1) return SlideshowAction.nextImage;
  if (loopOne || hasAudio) return SlideshowAction.restartImages;
  return SlideshowAction.nextWork;
}

/// 视频播放完成时的动作。
VideoEndAction videoEndAction({
  required bool loopOne,
  required bool autoplay,
}) {
  if (loopOne) return VideoEndAction.replay;
  return autoplay ? VideoEndAction.nextWork : VideoEndAction.stop;
}
