/// I3：新视频起播时的「静音淡入」纯逻辑。
///
/// 起播瞬间解码器要填缓冲、建立音频输出，直接用目标音量容易先爆一声
/// （喇叭破音），同时首帧尚未就绪就开始推进会表现为抽搐。这里把音量
/// 从 0 分几步抬到目标值，播放侧则先等首帧/时长就绪。
library;

/// 生成淡入音量序列，最后一步等于目标音量（0–100）。
///
/// 目标为 0 或步数非法时返回空列表，调用方直接设为 0/目标即可。
List<double> fadeInSteps(double target, {int steps = 6}) {
  if (steps <= 0) return const <double>[];
  final t = target.clamp(0.0, 100.0).toDouble();
  if (t <= 0) return const <double>[];
  return List<double>.generate(steps, (i) => t * (i + 1) / steps);
}

/// 本次打开是否需要静音淡入：只有视频、用户没暂停、音量大于 0 才需要。
bool shouldFadeIn({
  required bool isVideo,
  required bool paused,
  required double volume,
}) =>
    isVideo && !paused && volume > 0;

/// 首帧等待预算：每 [intervalMs] 检查一次，最多 [attempts] 次。
/// 时长未知时按此上限等待，避免弱网下迟迟不起播。
const int firstFrameAttempts = 8;
const int firstFrameIntervalMs = 60;

/// 是否还应继续等首帧：拿到时长（>0）或 token 失效/已暂停就停止。
bool shouldWaitFirstFrame({
  required int attempt,
  required Duration knownDuration,
  required bool tokenAlive,
  required bool paused,
}) {
  if (!tokenAlive || paused) return false;
  if (knownDuration.inMilliseconds > 0) return false;
  return attempt < firstFrameAttempts;
}
