/// G16：切后台自动暂停并记忆位置。
///
/// 生命周期判定抽成纯函数，避免把平台差异散落在播放页里：
/// - 移动端：仅 `paused`（真正进入后台）暂停。iOS 的 `inactive` 会被
///   控制中心、通知横幅、系统权限弹窗（如首次访问 NAS 的本地网络授权）
///   瞬时触发，按它暂停会造成「播放 1 秒即暂停」，因此不再采信；
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
      return false;
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
