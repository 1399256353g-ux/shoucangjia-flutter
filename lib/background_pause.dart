/// G16：切后台自动暂停并记忆位置。
///
/// 生命周期判定抽成纯函数，避免把平台差异散落在播放页里：
/// - 移动端：`inactive`（来电/下拉通知/多任务预览）就要暂停，避免声音外泄；
/// - 桌面端：只有窗口最小化/隐藏（`hidden`/`paused`）才暂停，
///   单纯失去焦点（点别的窗口）不打断播放。
library;

/// 需要暂停的生命周期状态名（Flutter `AppLifecycleState.name`）。
bool shouldPauseInBackground({
  required String state,
  required bool isMobile,
}) {
  switch (state) {
    case 'hidden':
    case 'paused':
    case 'detached':
      return true;
    case 'inactive':
      return isMobile;
    default:
      return false;
  }
}

/// 回到前台后是否自动恢复播放：只有「因切后台才暂停」且用户此前没手动暂停时才恢复。
bool shouldResumeFromBackground({
  required bool pausedByBackground,
  required bool userPaused,
}) =>
    pausedByBackground && !userPaused;
