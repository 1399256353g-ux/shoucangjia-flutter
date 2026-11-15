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
