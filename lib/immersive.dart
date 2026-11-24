/// P2 §12/§13：非全屏沉浸与轻震动的纯策略。
///
/// 背景：非全屏要像抖音一样「3 秒不动就让右侧互动栏与左侧信息区淡出」，
/// 进度条必须保留；全屏继续走 M4（UiAutoHidePolicy）的显隐逻辑，两者互不干扰。
/// 把「何时可以进入沉浸」「淡出透明度」和「翻页震动去重」收成纯逻辑，
/// 便于回归测试（不依赖 Widget 树）。
library;

/// 无操作进入沉浸的等待时长。
const Duration kImmersiveIdle = Duration(seconds: 3);

/// 互动栏/信息区淡出（及恢复）的动画时长（§5：200ms easeOut）。
const int kImmersiveFadeMs = 200;

/// 沉浸状态的判定与展示策略。
class ImmersivePolicy {
  const ImmersivePolicy._();

  /// 是否允许进入（或继续保持）沉浸：
  /// 只在非全屏、功能区可见、没有翻页/拖动/面板遮挡时成立。
  static bool eligible({
    required bool fullscreen,
    required bool uiVisible,
    required bool pageSwiping,
    required bool overlayOpen,
    required bool dragging,
    required bool seeking,
  }) =>
      !fullscreen &&
      uiVisible &&
      !pageSwiping &&
      !overlayOpen &&
      !dragging &&
      !seeking;

  /// 互动栏/信息区的不透明度：功能区已隐藏时 0；沉浸时淡出为 0。
  static double opacity({
    required bool uiVisible,
    required bool immersive,
  }) {
    if (!uiVisible) return 0;
    if (immersive) return 0;
    return 1;
  }

  /// 沉浸淡入淡出固定 200ms；其他情况沿用调用方给的时长。
  static int durationMs({required bool immersive, required int fallbackMs}) =>
      immersive ? kImmersiveFadeMs : fallbackMs;
}

/// 沉浸计时器状态机（纯逻辑，不持有 Timer）。
///
/// - [schedule] 记录「从 nowMs 起过 idle 就到点」；
/// - [touch] 表示有一次用户操作：立即退出沉浸并清掉到点时间；
/// - [tick] 由计时器回调调用，只有到点且 [eligible] 时才真正进入。
class ImmersiveCycle {
  ImmersiveCycle({this.idle = kImmersiveIdle});

  final Duration idle;

  bool _immersive = false;
  int? _deadlineMs;

  bool get immersive => _immersive;
  bool get scheduled => _deadlineMs != null;

  /// 任何点击/滑动/按键：退出沉浸，等待调用方重新排定。
  void touch() {
    _immersive = false;
    _deadlineMs = null;
  }

  /// 平静状态下开始计时。
  void schedule(int nowMs) {
    _deadlineMs = nowMs + idle.inMilliseconds;
  }

  /// 完全不排定（如全屏、面板打开）；顺带退出沉浸。
  void cancel() {
    _immersive = false;
    _deadlineMs = null;
  }

  /// 计时器到期：返回 true 表示「本次真的从非沉浸切到沉浸」，需重建。
  bool tick(int nowMs, {required bool eligible}) {
    final deadline = _deadlineMs;
    if (deadline == null || nowMs < deadline) return false;
    _deadlineMs = null;
    if (!eligible || _immersive) return false;
    _immersive = true;
    return true;
  }
}
