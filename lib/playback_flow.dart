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

/// F32：切条结束后是否应主动起播。
///
/// `open()` 期间的 `player.stop()/open()` 会让 `playing` 流发出 `false`，
/// 若此时按播放器事件回写暂停状态，会把用户「要播放」的意图覆盖成暂停，
/// 下一条视频就会停在首帧。切条期间以用户意图为准，不采信播放器事件。
bool shouldAutoPlay({required bool paused, required bool opening}) =>
    !paused && !opening;

/// F32：连播兜底。视频已就绪但播放器仍未在播放、且用户没有暂停时，
/// 应主动补一次 `play()`，避免偶发停在片尾/首帧。
bool shouldForcePlay({
  required bool paused,
  required bool opening,
  required bool playerPlaying,
  required bool hasMedia,
}) =>
    hasMedia && !paused && !opening && !playerPlaying;
