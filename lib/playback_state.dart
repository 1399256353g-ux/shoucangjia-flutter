/// 播放页显式状态机（阶段1 状态层）。
///
/// 设计原则（owner 2026-11-20）：
/// - **相位是唯一事实源**，界面只根据 [PlaybackPhase] 决定显示 loading /
///   paused / buffering，不再用散落的布尔量互相猜。
/// - 纯 Dart、无 Flutter 依赖、无定时器：定时器只负责「喂事件」，
///   不允许自己改状态。任何兜底都必须表现为一个明确事件。
/// - 一个事件对应一次转移；未知事件保持原相位（幂等），避免抖动。
library;

/// 播放页相位。
///
/// - [idle]：还没有打开任何媒体（首帧前）。
/// - [opening]：已发起 open，等待媒体就绪（首帧/时长）。
/// - [ready]：媒体已就绪，用户意图是「可以播但还没真正走起来」。
/// - [playing]：位置在前进。
/// - [buffering]：播放中短暂等数据（弱网/寻道）。
/// - [paused]：用户/后台/失败之外，明确处于暂停（画面保留）。
/// - [failed]：打开或解码失败，等待用户重试。
enum PlaybackPhase { idle, opening, ready, playing, buffering, paused, failed }

/// 喂给状态机的事件。
///
/// 与播放器回调一一对应，不允许「定时器拍脑袋」产生事件：
/// - [open]：调用 open() 打开一条新媒体。
/// - [mediaReady]：媒体已就绪（拿到时长/首帧）。
/// - [play]：真正开始播放（用户点播放、恢复前台、补 play 成功）。
/// - [pause]：用户暂停或切后台暂停。
/// - [bufferStart]：播放器报开始缓冲。
/// - [bufferEnd]：播放器报缓冲结束。
/// - [progress]：位置前进（首帧真的出来了）。
/// - [error]：播放器报错或加载超时。
/// - [userSeek]：用户拖动进度条。
/// - [completed]：一条媒体播放完成。
enum PlaybackEvent {
  open,
  mediaReady,
  play,
  pause,
  bufferStart,
  bufferEnd,
  progress,
  error,
  userSeek,
  completed,
}

/// 纯函数转移：`nextPhase(当前相位, 事件) -> 新相位`。
///
/// 规则要点：
/// - [PlaybackEvent.open] 总是进入 [PlaybackPhase.opening]（重试/重开也走它）。
/// - [PlaybackPhase.failed] 只能被 [PlaybackEvent.open] / [PlaybackEvent.mediaReady]
///   带出来，其它事件一律保持失败态，避免失败后又被播放器事件「救活」。
/// - [PlaybackPhase.paused] 下位置/缓冲事件不改变相位：暂停时迟到的
///   progress 不能把界面刷成「正在播放」。
/// - 打开阶段的 bufferStart 不切到 [PlaybackPhase.buffering]：起播时的
///   正常缓冲仍显示 loading，避免转圈样式来回跳。
PlaybackPhase nextPhase(PlaybackPhase phase, PlaybackEvent event) {
  switch (phase) {
    case PlaybackPhase.idle:
      switch (event) {
        case PlaybackEvent.open:
          return PlaybackPhase.opening;
        case PlaybackEvent.mediaReady:
          return PlaybackPhase.ready;
        case PlaybackEvent.play:
          return PlaybackPhase.playing;
        case PlaybackEvent.pause:
          return PlaybackPhase.paused;
        case PlaybackEvent.bufferStart:
          return PlaybackPhase.buffering;
        case PlaybackEvent.bufferEnd:
          return PlaybackPhase.idle;
        case PlaybackEvent.progress:
          return PlaybackPhase.idle;
        case PlaybackEvent.error:
          return PlaybackPhase.failed;
        case PlaybackEvent.userSeek:
          return PlaybackPhase.idle;
        case PlaybackEvent.completed:
          return PlaybackPhase.idle;
      }
    case PlaybackPhase.opening:
      switch (event) {
        case PlaybackEvent.open:
          return PlaybackPhase.opening;
        case PlaybackEvent.mediaReady:
          return PlaybackPhase.ready;
        case PlaybackEvent.play:
          return PlaybackPhase.playing;
        case PlaybackEvent.pause:
          return PlaybackPhase.paused;
        case PlaybackEvent.bufferStart:
          return PlaybackPhase.opening;
        case PlaybackEvent.bufferEnd:
          return PlaybackPhase.opening;
        case PlaybackEvent.progress:
          return PlaybackPhase.opening;
        case PlaybackEvent.error:
          return PlaybackPhase.failed;
        case PlaybackEvent.userSeek:
          return PlaybackPhase.opening;
        case PlaybackEvent.completed:
          return PlaybackPhase.idle;
      }
    case PlaybackPhase.ready:
      switch (event) {
        case PlaybackEvent.open:
          return PlaybackPhase.opening;
        case PlaybackEvent.mediaReady:
          return PlaybackPhase.ready;
        case PlaybackEvent.play:
          return PlaybackPhase.playing;
        case PlaybackEvent.pause:
          return PlaybackPhase.paused;
        case PlaybackEvent.bufferStart:
          return PlaybackPhase.buffering;
        case PlaybackEvent.bufferEnd:
          return PlaybackPhase.ready;
        case PlaybackEvent.progress:
          return PlaybackPhase.playing;
        case PlaybackEvent.error:
          return PlaybackPhase.failed;
        case PlaybackEvent.userSeek:
          return PlaybackPhase.ready;
        case PlaybackEvent.completed:
          return PlaybackPhase.ready;
      }
    case PlaybackPhase.playing:
      switch (event) {
        case PlaybackEvent.open:
          return PlaybackPhase.opening;
        case PlaybackEvent.mediaReady:
          return PlaybackPhase.playing;
        case PlaybackEvent.play:
          return PlaybackPhase.playing;
        case PlaybackEvent.pause:
          return PlaybackPhase.paused;
        case PlaybackEvent.bufferStart:
          return PlaybackPhase.buffering;
        case PlaybackEvent.bufferEnd:
          return PlaybackPhase.playing;
        case PlaybackEvent.progress:
          return PlaybackPhase.playing;
        case PlaybackEvent.error:
          return PlaybackPhase.failed;
        case PlaybackEvent.userSeek:
          return PlaybackPhase.playing;
        case PlaybackEvent.completed:
          return PlaybackPhase.ready;
      }
    case PlaybackPhase.buffering:
      switch (event) {
        case PlaybackEvent.open:
          return PlaybackPhase.opening;
        case PlaybackEvent.mediaReady:
          return PlaybackPhase.buffering;
        case PlaybackEvent.play:
          return PlaybackPhase.playing;
        case PlaybackEvent.pause:
          return PlaybackPhase.paused;
        case PlaybackEvent.bufferStart:
          return PlaybackPhase.buffering;
        case PlaybackEvent.bufferEnd:
          return PlaybackPhase.playing;
        case PlaybackEvent.progress:
          return PlaybackPhase.playing;
        case PlaybackEvent.error:
          return PlaybackPhase.failed;
        case PlaybackEvent.userSeek:
          return PlaybackPhase.buffering;
        case PlaybackEvent.completed:
          return PlaybackPhase.ready;
      }
    case PlaybackPhase.paused:
      switch (event) {
        case PlaybackEvent.open:
          return PlaybackPhase.opening;
        case PlaybackEvent.mediaReady:
          return PlaybackPhase.ready;
        case PlaybackEvent.play:
          return PlaybackPhase.playing;
        case PlaybackEvent.pause:
          return PlaybackPhase.paused;
        case PlaybackEvent.bufferStart:
          return PlaybackPhase.paused;
        case PlaybackEvent.bufferEnd:
          return PlaybackPhase.paused;
        case PlaybackEvent.progress:
          return PlaybackPhase.paused;
        case PlaybackEvent.error:
          return PlaybackPhase.failed;
        case PlaybackEvent.userSeek:
          return PlaybackPhase.paused;
        case PlaybackEvent.completed:
          return PlaybackPhase.ready;
      }
    case PlaybackPhase.failed:
      switch (event) {
        case PlaybackEvent.open:
          return PlaybackPhase.opening;
        case PlaybackEvent.mediaReady:
          return PlaybackPhase.ready;
        case PlaybackEvent.play:
          return PlaybackPhase.failed;
        case PlaybackEvent.pause:
          return PlaybackPhase.failed;
        case PlaybackEvent.bufferStart:
          return PlaybackPhase.failed;
        case PlaybackEvent.bufferEnd:
          return PlaybackPhase.failed;
        case PlaybackEvent.progress:
          return PlaybackPhase.failed;
        case PlaybackEvent.error:
          return PlaybackPhase.failed;
        case PlaybackEvent.userSeek:
          return PlaybackPhase.failed;
        case PlaybackEvent.completed:
          return PlaybackPhase.failed;
      }
  }
}

/// 相位 → 界面显示，集中在这里，避免再出现「各自 if 一套」。
extension PlaybackPhaseView on PlaybackPhase {
  /// 是否显示起播 loading 圈。
  bool get showsLoading =>
      this == PlaybackPhase.idle || this == PlaybackPhase.opening;

  /// 是否显示暂停图标/暂停态浮层。
  bool get showsPaused =>
      this == PlaybackPhase.paused || this == PlaybackPhase.failed;

  /// 是否处于缓冲（配合慢缓冲阈值决定是否显示提示）。
  bool get showsBuffering => this == PlaybackPhase.buffering;

  /// 是否正在播放。
  bool get isActivelyPlaying => this == PlaybackPhase.playing;
}
