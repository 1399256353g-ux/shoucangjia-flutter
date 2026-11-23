/// M5：非全屏上下滑动切换作品时，功能区整体淡化。
///
/// 背景：滑动切条时任务栏、返回键、作者信息行、图文圆点会一直压在高亮画面上，
/// 观感割裂。做成纯策略便于回归测试：
/// - 全屏继续沿用 M4 的「显示/隐藏」逻辑，不做淡化；
/// - 非全屏且正在拖拽翻页时统一降到 [dimmedOpacity]；
/// - 松手（滚动结束）后恢复为 1；
/// - 功能区本身已隐藏（ui=false）时保持 0，不因滑动被重新点亮。
class ChromeFade {
  const ChromeFade._();

  /// 旧行为：滑动时把功能区压到 0.22 保留轮廓。
  /// owner 2026-11-20：顶部返回/封面设置与底部任务栏在滑动时不要淡化，
  /// 始终清晰可见，因此这个常量只保留给历史调用方引用。
  static const double dimmedOpacity = 0.22;

  /// 淡化/恢复动画时长（毫秒）：按下即淡出要快，松手恢复稍缓。
  static const int fadeOutMs = 90;
  static const int fadeInMs = 160;

  static double opacity({
    required bool uiVisible,
    required bool fullscreen,
    required bool swiping,
  }) {
    if (!uiVisible) return 0;
    // 滑动不再淡化：顶部按钮与底部任务栏保持全不透明。
    return 1;
  }

  static int durationMs({required bool swiping}) =>
      swiping ? fadeOutMs : fadeInMs;

  /// 信息区（头像/作者名/简介）与进度条的透明度。
  ///
  /// owner 2026-11-22：非全屏滑动时恢复「信息淡化」，但只要功能区可见就
  /// 保留轮廓（[dimmedOpacity]）；全屏不淡化（全屏走显示/隐藏）。
  static double infoOpacity({
    required bool uiVisible,
    required bool fullscreen,
    required bool swiping,
  }) {
    if (!uiVisible) return 0;
    if (fullscreen) return 1;
    return swiping ? dimmedOpacity : 1;
  }
}
