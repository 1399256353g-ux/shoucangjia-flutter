/// M2/M3：播放页底部任务栏的通用控件。
///
/// M2 要求「全屏且功能区呼出时」任务栏出现播放/暂停与横竖屏切换；
/// M3 要求 Windows 保持原交互——有播放/暂停（状态双向同步），但不得
/// 出现横竖屏按钮。这里把纯逻辑与两个按钮拆出来，便于单元/组件测试。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 屏幕方向（只区分竖屏/横屏，横屏两向都接受）。
enum ScreenMode { portrait, landscape }

/// 由窗口尺寸判定当前方向；正方形按竖屏处理。
ScreenMode screenModeOf(Size size) =>
    size.width > size.height ? ScreenMode.landscape : ScreenMode.portrait;

/// 切换目标：竖屏 ↔ 横屏。
ScreenMode toggledMode(ScreenMode mode) =>
    mode == ScreenMode.portrait ? ScreenMode.landscape : ScreenMode.portrait;

/// 目标方向对应的系统方向白名单。
List<DeviceOrientation> orientationsFor(ScreenMode mode) =>
    mode == ScreenMode.portrait
        ? const [DeviceOrientation.portraitUp]
        : const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ];

/// 任务栏播放/暂停按钮：图标与提示随 [paused] 实时变化（M2/M3）。
class TaskbarPlayButton extends StatelessWidget {
  const TaskbarPlayButton({
    super.key,
    required this.paused,
    required this.onPressed,
  });

  final bool paused;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('taskbar-play'),
      onPressed: onPressed,
      tooltip: paused ? '播放' : '暂停',
      icon:
          Icon(paused ? Icons.play_arrow : Icons.pause, color: Colors.white70),
    );
  }
}

/// 任务栏横竖屏切换按钮：只能在移动端出现（M2），桌面端不渲染。
class TaskbarRotateButton extends StatelessWidget {
  const TaskbarRotateButton({
    super.key,
    required this.mode,
    required this.onPressed,
  });

  final ScreenMode mode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final toLandscape = mode == ScreenMode.portrait;
    return IconButton(
      key: const Key('taskbar-rotate'),
      onPressed: onPressed,
      tooltip: toLandscape ? '横屏' : '竖屏',
      icon: Icon(
        toLandscape ? Icons.screen_lock_landscape : Icons.screen_lock_portrait,
        color: Colors.white70,
      ),
    );
  }
}

/// 组件渲染条件：仅 Android/iOS 显示横竖屏按钮；桌面端（含 Windows）不显示。
bool showRotateButton({required bool isAndroid, required bool isIOS}) =>
    isAndroid || isIOS;

/// M3：任务栏平台策略。
///
/// Windows/桌面端保持原交互：播放/暂停按钮必须常驻任务栏，横竖屏按钮
/// 一律不渲染；Android/iOS 只显示横竖屏按钮（O2：手机端播放/暂停改由
/// 画面中央大圆钮承担，任务栏不再重复放置）。把规则集中在这里，避免
/// 调用点各自判断导致桌面端误出横屏按钮。
class TaskbarPolicy {
  const TaskbarPolicy({required this.isAndroid, required this.isIOS});

  final bool isAndroid;
  final bool isIOS;

  bool get showPlayPause => !(isAndroid || isIOS);

  bool get showRotate => showRotateButton(isAndroid: isAndroid, isIOS: isIOS);
}

/// 按当前平台生成任务栏策略。
TaskbarPolicy taskbarPolicyFor({
  required bool isAndroid,
  required bool isIOS,
}) =>
    TaskbarPolicy(isAndroid: isAndroid, isIOS: isIOS);

// ---------------------------------------------------------------------------
// P0：抖音式非全屏播放页手感（数值严格取自 DOUYIN_VISUAL_SPEC.md §3/§5）。
// 只服务非全屏；全屏分支沿用旧值，不调用以下任何一项。
// ---------------------------------------------------------------------------

/// §5 单击延迟：首次 tap 延迟 250ms 判定单击，期间收到第二次 tap 即取消单击。
const int kStageSingleTapDelayMs = 250;

/// §5 双击窗口与位移上限（与 likes.dart 的 320ms/80px 独立，P0 用 250ms）。
const int kStageDoubleTapWindowMs = 250;
const double kStageDoubleTapMaxDistance = 80;

/// §5 暂停提示：暂停时只显示播放图标，0.8s / Curves.easeOut 淡出。
const int kPlayHintFadeMs = 800;

/// §5 双击爱心：700ms，scale 0.6→1.15→1.0，上浮 60dp，opacity 1→0。
const Duration kHeartAnimDuration = Duration(milliseconds: 700);
const double kHeartSize = 58;
const Color kHeartColor = Color(0xFFFF3B5C);
const double kHeartRiseDistance = 60;

/// §3 进度条：常态 2dp / 白 60%（#99FFFFFF）/ 圆角 1dp；
/// 按住或拖动 4dp / 全白 / 圆角 2dp。
const double kProgressIdleHeight = 2;
const double kProgressActiveHeight = 4;
const double kProgressIdleRadius = 1;
const double kProgressActiveRadius = 2;
const Color kProgressTrackColor = Color(0x99FFFFFF);
const Color kProgressPlayedColor = Color(0xFFFFFFFF);

/// §3 时间与气泡：时间 11px tabular / 白 90%；气泡 12px / #CC000000 / 圆角 6dp。
const double kProgressTimeFontSize = 11;
const Color kProgressTimeColor = Color(0xE6FFFFFF);
const double kSeekBubbleFontSize = 12;
const Color kSeekBubbleColor = Color(0xCC000000);
const double kSeekBubbleRadius = 6;

/// §3 布局：左右边距 12dp，距任务栏 8dp。
const double kProgressSideMargin = 12;
const double kProgressBottomGap = 8;

/// §3 进度条某一状态的视觉参数。
class StageProgressMetrics {
  const StageProgressMetrics({
    required this.height,
    required this.radius,
    required this.trackColor,
    required this.playedColor,
  });

  final double height;
  final double radius;
  final Color trackColor;
  final Color playedColor;
}

/// 常态（未按住）与按住/拖动两套进度条参数。
const StageProgressMetrics kProgressIdleMetrics = StageProgressMetrics(
  height: kProgressIdleHeight,
  radius: kProgressIdleRadius,
  trackColor: kProgressTrackColor,
  playedColor: kProgressPlayedColor,
);

const StageProgressMetrics kProgressActiveMetrics = StageProgressMetrics(
  height: kProgressActiveHeight,
  radius: kProgressActiveRadius,
  trackColor: kProgressPlayedColor,
  playedColor: kProgressPlayedColor,
);

StageProgressMetrics stageProgressMetrics({required bool pressed}) =>
    pressed ? kProgressActiveMetrics : kProgressIdleMetrics;

/// §3 时间文字：11px、tabular figures、白 90%。
const TextStyle kProgressTimeStyle = TextStyle(
  fontSize: kProgressTimeFontSize,
  color: kProgressTimeColor,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// §3 拖动气泡：12px、#CC000000、圆角 6dp。
const TextStyle kSeekBubbleTextStyle = TextStyle(
  fontSize: kSeekBubbleFontSize,
  color: Colors.white,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// P0 单击/双击仲裁（纯逻辑，便于单测）。
///
/// 第一次 tap 记为 pending，等待 [windowMs]；窗口内出现第二次 tap 且位移
/// 不超过 [maxDistance] 则判定双击并清空 pending（单击被取消）。
class StageTapArbiter {
  StageTapArbiter({
    this.windowMs = kStageDoubleTapWindowMs,
    this.maxDistance = kStageDoubleTapMaxDistance,
  });

  final int windowMs;
  final double maxDistance;

  int? _pendingMs;
  Offset? _pendingPos;

  bool get hasPending => _pendingMs != null;

  /// 记录一次 tap；返回 true 表示构成双击（调用方必须取消已排队的单击）。
  bool registerTap({required int nowMs, required Offset pos}) {
    final last = _pendingMs;
    final lastPos = _pendingPos;
    if (last != null &&
        lastPos != null &&
        nowMs - last < windowMs &&
        (pos - lastPos).distance < maxDistance) {
      clear();
      return true;
    }
    _pendingMs = nowMs;
    _pendingPos = pos;
    return false;
  }

  void clear() {
    _pendingMs = null;
    _pendingPos = null;
  }
}

/// §5 爱心缩放：前 40% easeOut 0.6→1.15，后 60% elasticOut 1.15→1.0。
double heartScaleAt(double t) {
  final x = t.clamp(0.0, 1.0);
  if (x < 0.4) {
    return 0.6 + (1.15 - 0.6) * Curves.easeOut.transform(x / 0.4);
  }
  return 1.15 - (1.15 - 1.0) * Curves.elasticOut.transform((x - 0.4) / 0.6);
}

/// §5 爱心不透明度：1→0 线性。
double heartOpacityAt(double t) => 1 - t.clamp(0.0, 1.0);

/// §5 爱心上浮位移（向上为负，共 60dp）。
double heartRiseOffsetAt(double t) => -kHeartRiseDistance * t.clamp(0.0, 1.0);

/// §5 暂停提示不透明度：1→0，0.8s，Curves.easeOut。
double playHintOpacityAt(double t) =>
    1 - Curves.easeOut.transform(t.clamp(0.0, 1.0));

/// §6 左上角图标：24dp、间距 12dp、无背景圆、按压 white24 + scale 0.92/120ms。
const double kStageIconSize = 24;
const double kStageIconSpacing = 12;
const double kPressScaleTo = 0.92;
const int kPressScaleMs = 120;
const Color kPressOverlayColor = Color(0x24FFFFFF);

/// §6 左上角操作按钮：常态透明，仅按压时出现 40dp white24 圆底并轻微缩放。
class StageIconButton extends StatefulWidget {
  const StageIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color iconColor;

  @override
  State<StageIconButton> createState() => _StageIconButtonState();
}

class _StageIconButtonState extends State<StageIconButton> {
  bool _down = false;

  void _setDown(bool value) {
    if (_down == value || !mounted) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setDown(true),
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      onTap: widget.onPressed,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: AnimatedScale(
            scale: _down ? kPressScaleTo : 1.0,
            duration: const Duration(milliseconds: kPressScaleMs),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: kPressScaleMs),
              curve: Curves.easeOut,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _down ? kPressOverlayColor : Colors.transparent,
              ),
              child: Icon(widget.icon,
                  size: kStageIconSize, color: widget.iconColor),
            ),
          ),
        ),
      ),
    );
    final tip = widget.tooltip;
    if (tip == null || tip.isEmpty) return button;
    return Tooltip(message: tip, child: button);
  }
}
