/// M4：全屏功能区自动隐藏的判定策略。
///
/// 背景：退出全屏后旧的 hideTimer 仍会到期，把非全屏的功能区也隐藏掉。
/// 把「何时排定隐藏」与「到期时是否真的隐藏」收成纯函数，便于回归测试：
/// - 只有全屏且功能区可见时才需要排定计时器；
/// - 到期时若已退出全屏（或页面销毁、正在拖进度条/悬停）则一律不隐藏。
class UiAutoHidePolicy {
  const UiAutoHidePolicy._();

  /// 是否需要为自动隐藏排定计时器。
  static bool shouldSchedule({
    required bool fullscreen,
    required bool uiVisible,
  }) =>
      fullscreen && uiVisible;

  /// 计时器到期时是否真的把功能区隐藏。
  static bool shouldHide({
    required bool fullscreen,
    required bool mounted,
    required bool dragging,
    required bool barHover,
  }) =>
      mounted && fullscreen && !dragging && !barHover;
}

/// 0.9.72：自动隐藏「截止时刻」的可变状态。
///
/// 桌面端每个 pointer move 都会调用 [showUi]（鼠标划过播放页可达每秒上百
/// 次）。旧实现每次 cancel + 新建 `hideTimer`，同时无条件 `setState` 重建
/// 整页。现在交互只推进截止时刻，计时器到期后再按剩余时间重排，因此
/// [remaining] 与 [extend]/[clear] 的语义单独抽出来做回归测试。
class HideDeadline {
  DateTime? _at;

  /// 当前截止时刻（未排定则为 null）。
  DateTime? get at => _at;

  /// 从 [now] 起顺延 [seconds] 秒作为新的截止时刻。
  void extend(DateTime now, int seconds) {
    _at = now.add(Duration(seconds: seconds));
  }

  /// 取消排定（隐藏已执行或被外部收起）。
  void clear() {
    _at = null;
  }

  /// 距截止还剩多久；未排定或已到期都返回 [Duration.zero]。
  Duration remaining(DateTime now) {
    final at = _at;
    if (at == null) return Duration.zero;
    final left = at.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}
