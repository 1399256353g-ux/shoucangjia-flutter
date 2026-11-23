/// M1：播放页舞台单击语义。
///
/// 抖音式全屏：功能区隐藏时单击只呼出功能区；功能区显示时单击只收起
/// 功能区，不改变播放状态。非全屏仍保留「单击暂停/继续」。
/// 图片放大后单击复位（G14）优先于上述规则。
///
/// 2026-11-23：双击点赞已移除，`doubleTap` 参数保留为兼容位，任何调用方
/// 都应传 false；`like` 分支因此不可达，只作为穷尽枚举保留。
library;

enum StageTapAction {
  /// 功能区隐藏时单击：呼出功能区。
  showUi,

  /// 全屏且功能区显示时单击：收起功能区（不暂停）。
  hideUi,

  /// 非全屏且功能区显示时单击：暂停/继续。
  togglePause,

  /// 历史分支：超喜欢（点赞）。点赞功能已移除，正常路径不会再返回它。
  like,

  /// 图片放大时单击：恢复原始大小。
  resetZoom,
}

/// 决策顺序：
/// 1. 图片放大 → 只复位缩放（保持 G14，且不误触点赞/暂停）；
/// 2. 功能区隐藏且非双击 → 呼出（保持原「第一次单击只呼出」）；
/// 3. 双击 → 点赞（功能区隐藏时也允许，避免全屏首次单击收起后双击失效）；
/// 4. 全屏 → 收起（M1 核心，不再暂停）；
/// 5. 其余（非全屏）→ 暂停/继续。
StageTapAction stageTapAction({
  required bool uiVisible,
  required bool fullscreen,
  required bool zoomed,
  // 双击点赞移除后此参数不再参与判定；保留签名只为不改老调用点，
  // 新代码请一律传 false（传 true 也不会再返回 like）。
  bool doubleTap = false,
}) {
  if (zoomed) return StageTapAction.resetZoom;
  if (!uiVisible) return StageTapAction.showUi;
  if (fullscreen) return StageTapAction.hideUi;
  return StageTapAction.togglePause;
}
