/// 播放页连播/循环的纯逻辑判定，便于单元测试。
///
/// 规则：
/// - 单条循环（loopOne）优先级最高：视频播完重播本条，图文放完一轮回到第一张，
///   不会切到下一条（无音频的图文同样循环）。
/// - 未开循环时，视频播完按自动连播决定是否下一条。
/// - 未开循环的图文：有背景音乐时图片循环到歌曲结束，否则一轮放完切下一条。
enum SlideshowAction { nextImage, restartImages, nextWork, stop }

enum VideoEndAction { replay, nextWork, stop }

/// 图文定时器每次触发时的动作。
/// [index] 为当前图片下标，[count] 为图片张数。
SlideshowAction slideshowAction({
  required int index,
  required int count,
  required bool loopOne,
  required bool hasAudio,
  bool autoplay = true,
}) {
  if (index < count - 1) return SlideshowAction.nextImage;
  if (loopOne || hasAudio) return SlideshowAction.restartImages;
  // 自动连播关闭时，一轮放完就停，不再自动切下一条。
  return autoplay ? SlideshowAction.nextWork : SlideshowAction.stop;
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

/// H1：图文进度条拖动时，按横向比例换算目标图片下标。
///
/// [fraction] 为 0–1 的进度比例（越界会被夹紧），[count] 为图片张数。
/// 按下/拖动时使用（floor），松手直接采用该下标，实现「拖动快速选图」。
int picIndexAtFraction(double fraction, int count) {
  if (count <= 1) return 0;
  final f = fraction.clamp(0.0, 1.0);
  return (f * count).floor().clamp(0, count - 1);
}

/// 暂停后的自救动作。
enum StallRecoveryAction { none, retryPlay, reopen }

/// 播放器「不在播放」时，是否应该把界面状态改成暂停。
///
/// 只有用户暂停、切后台暂停、已判失败时才采信播放器的停止事件；
/// 其余情况（弱网卡顿、解码器被系统回收、音频设备切换）属于**非用户暂停**，
/// 不能直接把 `paused` 置真，否则会静默停在暂停态、连播链路断掉。
bool shouldAdoptPlayerPause({
  required bool userPaused,
  required bool backgroundPaused,
  required bool failed,
  required bool opening,
}) =>
    opening || failed || userPaused || backgroundPaused;

/// 非用户暂停的自救策略（纯函数，便于单测/防循环）。
///
/// - 用户/后台/失败/切条中/不在前台 → 不动作；
/// - 播放器仍在播或没有媒体 → 不动作；
/// - 前两次尝试 `play()` 续播（卡顿、管线掉线）；
/// - 之后按 `reopen` 重开当前媒体（解码器被系统回收的兜底）；
/// - 达到 [maxAttempts] 次仍失败 → 不再循环，交给故障提示/用户操作。
StallRecoveryAction stallRecoveryAction({
  required bool userPaused,
  required bool backgroundPaused,
  required bool failed,
  required bool opening,
  required bool appForeground,
  required bool playerPlaying,
  required bool hasMedia,
  required int attempts,
  int maxAttempts = 3,
}) {
  if (userPaused ||
      backgroundPaused ||
      failed ||
      opening ||
      !appForeground ||
      playerPlaying ||
      !hasMedia ||
      attempts >= maxAttempts) {
    return StallRecoveryAction.none;
  }
  return attempts < 2
      ? StallRecoveryAction.retryPlay
      : StallRecoveryAction.reopen;
}

/// O3：iOS 启动 1.5 秒内仍未播放时是否应重开一次。
///
/// 只在「媒体已就绪（duration > 0）、位置仍停在开头、用户没有暂停、
/// 不在后台、未判失败、且本轮还没重开过」时触发；重开只做一次，
/// 失败后交给故障提示，避免无限重开。
bool shouldStartupReopen({
  required bool playing,
  required int positionMs,
  required int durationMs,
  required bool opening,
  required bool userPaused,
  required bool backgroundPaused,
  required bool failed,
  required bool retried,
  int startupWindowMs = 3000,
}) =>
    !retried &&
    !playing &&
    !opening &&
    !userPaused &&
    !backgroundPaused &&
    !failed &&
    durationMs > 0 &&
    positionMs <= startupWindowMs;
