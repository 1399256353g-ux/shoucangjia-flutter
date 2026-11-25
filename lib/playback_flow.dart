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

/// H1：图文进度条拖动时，按横向比例换算目标图片下标。
///
/// [fraction] 为 0–1 的进度比例（越界会被夹紧），[count] 为图片张数。
/// 按下/拖动时使用（floor），松手直接采用该下标，实现「拖动快速选图」。
int picIndexAtFraction(double fraction, int count) {
  if (count <= 1) return 0;
  // `NaN.clamp(0, 1)` **返回 NaN**（clamp 不消 NaN），随后 `NaN.floor()`
  // 抛 `Unsupported operation: Infinity or NaN toInt`。调用方算的是
  // `dx / width`，宽度来自 `LayoutBuilder`——零约束中间态下就是 NaN，
  // 而这里在 `onHorizontalDragStart` 里，异常会把整页手势链打断。
  if (!fraction.isFinite) return 0;
  final f = fraction.clamp(0.0, 1.0);
  final i = (f * count).floor();
  if (i < 0) return 0;
  return i > count - 1 ? count - 1 : i;
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

/// 起播观察窗口（一个 1.2 s 窗口）的判定结果。
///
/// 起播阶段只有「位置是否前进」是可靠的健康信号（mpv 管线卡死时仍可能报
/// playing=true）。位置没前进时分两种「还没起播」的原因，必须分开看：
///
/// - 数据没到位（缓存还没覆盖当前位置、但仍在增长）→ [filling]
/// - 数据早已到位（缓存已覆盖当前位置，I/O 不是瓶颈）→ [warming]
///
/// 后者是 0.9.159 的误判来源：整段已缓存的 3.3 GB 条目，缓存增量可能是 0，
/// 旧判据只比「缓存增量」→ 文件越完整判得越快，反而比冷文件更早被记成
/// `stuck:startup` 并重复补 play。判据按「是否已被数据卡住」排序，
/// 而不是只看增量。
enum StartupSignal {
  /// 位置已前进 ≥ [minProgressMs]：真的在播。
  advancing,

  /// 位置未动，但缓存已覆盖当前位置（数据不是瓶颈）：解码/渲染预热中。
  warming,

  /// 位置未动，缓存尚未覆盖当前位置但仍在增长：仍在灌首帧。
  filling,

  /// 位置不动且数据侧无进展：真卡死。
  stalled,
}

/// 起播窗口内单个窗口的判定。
///
/// 顺延次数分别计入，防止无限等待掩盖真正的卡死：
/// [maxWarmWaits] 给「数据已就位、解码慢」的预热，[maxFillWaits] 给
/// 「缓存还在灌」的等待。
StartupSignal startupSignal({
  required int positionMs,
  required int basePositionMs,
  required int bufferMs,
  required int baseBufferMs,
  int fillWaits = 0,
  int warmWaits = 0,
  int minProgressMs = 300,
  int coverMarginMs = 1500,
  int maxFillWaits = 2,
  int maxWarmWaits = 2,
}) {
  if (positionMs - basePositionMs >= minProgressMs) {
    return StartupSignal.advancing;
  }
  // 数据已覆盖当前位置：慢在解码/渲染，不在 I/O。
  if (bufferMs - positionMs >= coverMarginMs) {
    return warmWaits < maxWarmWaits
        ? StartupSignal.warming
        : StartupSignal.stalled;
  }
  // 数据还没跟上，但在增长：确实还在灌首帧。
  if (bufferMs - baseBufferMs >= minProgressMs && fillWaits < maxFillWaits) {
    return StartupSignal.filling;
  }
  return StartupSignal.stalled;
}
