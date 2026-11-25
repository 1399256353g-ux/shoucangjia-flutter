/// M2/M3：播放页底部任务栏的通用控件。
///
/// M2 要求「全屏且功能区呼出时」任务栏出现播放/暂停与横竖屏切换；
/// M3 要求 Windows 保持原交互——有播放/暂停（状态双向同步），但不得
/// 出现横竖屏按钮。这里把纯逻辑与两个按钮拆出来，便于单元/组件测试。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'volume_control.dart';

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
///
/// owner 2026-11-23：作为任务栏主按钮，触达区不小于 44dp、图标用白色。
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
      iconSize: 28,
      constraints: const BoxConstraints(
          minWidth: kTaskbarTouchTarget, minHeight: kTaskbarTouchTarget),
      icon: Icon(paused ? Icons.play_arrow : Icons.pause, color: Colors.white),
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

/// owner 2026-11-23：任务栏所有按钮的最小触达区（dp）。
const double kTaskbarTouchTarget = 44;

/// 倍速文案：`1.0x` / `1.25x` / `2.0x`（保留一位或两位小数，不显示末尾 0）。
String speedLabel(double speed) {
  var s = speed.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return '${s}x';
}

/// 任务栏剧集入口：`1/12`，点击弹出集数列表。
///
/// owner 2026-11-23：合并为单入口，替代独立的上一集/下一集按钮。
class TaskbarEpisodeButton extends StatelessWidget {
  const TaskbarEpisodeButton({
    super.key,
    required this.current,
    required this.total,
    required this.onPressed,
    this.width = kTaskbarTouchTarget,
  });

  final int current;
  final int total;
  final VoidCallback onPressed;
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = width < kTaskbarTouchTarget ? kTaskbarTouchTarget : width;
    final cur = current < 1 ? 1 : (current > total ? total : current);
    return Tooltip(
      message: '选集',
      child: Semantics(
        button: true,
        label: '选集 $cur/$total',
        child: GestureDetector(
          key: const Key('taskbar-episodes'),
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: w,
            height: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.video_library_outlined,
                    size: kTaskbarIconSize - 4, color: Colors.white70),
                const SizedBox(height: 1),
                Text('$cur/$total',
                    style: const TextStyle(
                        fontSize: 9, height: 1.0, color: Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 任务栏「播放设置」入口：齿轮图标，点击弹出倍速/循环/连播/乱序菜单。
///
/// owner 2026-11-24：这里原来显示「1.25x」文字，但点进去是整套播放设置——
/// 图标暗示的和实际做的事不符，而且自动连播/循环/乱序已经直接摆在任务栏上，
/// 再拿倍速文字当入口就是重复。改为设置样式的齿轮图标，倍速只在菜单里调。
/// 当前倍速仍保留在 tooltip / 无障碍标签里，不丢信息。
class TaskbarSettingsButton extends StatelessWidget {
  const TaskbarSettingsButton({
    super.key,
    required this.speed,
    required this.onPressed,
    this.width = kTaskbarTouchTarget,
  });

  final double speed;
  final VoidCallback onPressed;
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = width < kTaskbarTouchTarget ? kTaskbarTouchTarget : width;
    return Tooltip(
      message: '播放设置（当前 ${speedLabel(speed)}）',
      child: Semantics(
        button: true,
        label: '播放设置 ${speedLabel(speed)}',
        child: GestureDetector(
          key: const Key('taskbar-settings'),
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: w,
            height: 48,
            child: const Center(
              child: Icon(Icons.tune_rounded,
                  size: 20, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

/// 任务栏声音按钮：点击静音；长按/左右拖动调音量（桌面端）。
/// 移动端不渲染（音量交给系统音量键）。
/// 档位 → 图标。三处音量读数共用，避免各自写一份三元表达式。
IconData volumeIconData(VolumeIcon level) => switch (level) {
      VolumeIcon.mute => Icons.volume_off,
      VolumeIcon.down => Icons.volume_down,
      VolumeIcon.up => Icons.volume_up,
    };

class TaskbarSoundButton extends StatelessWidget {
  const TaskbarSoundButton({
    super.key,
    required this.muted,
    required this.volume,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.width = kTaskbarTouchTarget,
  });

  final bool muted;
  final double volume;
  final VoidCallback onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = width < kTaskbarTouchTarget ? kTaskbarTouchTarget : width;
    final icon = volumeIconData(volumeIconFor(volume, muted: muted));
    // Tooltip 必须在 GestureDetector 外层：放在内层时它的长按识别器会
    // 抢在音量长按之前赢得手势仲裁（实测长按调音量失效）。
    return Tooltip(
      message: '点击静音 / 长按拖动调音量',
      child: GestureDetector(
        key: const Key('taskbar-sound'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        onHorizontalDragStart: onHorizontalDragStart,
        onHorizontalDragUpdate: onHorizontalDragUpdate,
        onHorizontalDragEnd: onHorizontalDragEnd,
        child: SizedBox(
          width: w,
          height: 48,
          child: Icon(icon, size: kTaskbarIconSize, color: Colors.white70),
        ),
      ),
    );
  }
}

/// 任务栏「显示」按钮。
///
/// - 移动端：点按=全屏开关，长按=横竖屏切换（合并原来两个按钮）；
/// - 桌面端：保留独立的全屏按钮（M3 交互不变）。
class TaskbarDisplayButton extends StatelessWidget {
  const TaskbarDisplayButton({
    super.key,
    required this.fullscreen,
    required this.mobile,
    required this.onPressed,
    this.onLongPress,
    this.width = kTaskbarTouchTarget,
  });

  final bool fullscreen;
  final bool mobile;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final double width;

  @override
  Widget build(BuildContext context) {
    final icon = fullscreen ? Icons.fullscreen_exit : Icons.fullscreen;
    if (!mobile) {
      return IconButton(
        key: const Key('taskbar-fullscreen'),
        tooltip: fullscreen ? '退出全屏' : '全屏',
        onPressed: onPressed,
        constraints: const BoxConstraints(
            minWidth: kTaskbarTouchTarget, minHeight: kTaskbarTouchTarget),
        icon: Icon(icon, size: kTaskbarIconSize, color: Colors.white70),
      );
    }
    final w = width < kTaskbarTouchTarget ? kTaskbarTouchTarget : width;
    return Tooltip(
      message: '全屏（长按切换横竖屏）',
      child: GestureDetector(
        key: const Key('taskbar-display'),
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        onLongPress: onLongPress,
        child: SizedBox(
          width: w,
          height: 48,
          child: Icon(icon, size: kTaskbarIconSize, color: Colors.white70),
        ),
      ),
    );
  }
}

/// M3：任务栏平台策略。
///
/// Windows/桌面端保持原交互：播放/暂停按钮必须常驻任务栏，横竖屏按钮
/// 一律不渲染；Android/iOS 只显示横竖屏按钮（O2：手机端播放/暂停由
/// **点击屏幕**承担，任务栏不再重复放置）。把规则集中在这里，避免
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

// ---------------------------------------------------------------------------
// P1：抖音式非全屏播放页——右侧互动栏 / 左侧信息区 / 底部任务栏。
// 数值严格取自 DOUYIN_VISUAL_SPEC.md §1/§2/§4；只服务非全屏，全屏不调用。
// ---------------------------------------------------------------------------

/// §2 文案最大宽度的预留：右侧互动栏约 84dp（44 头像 + 10 右边距 + 余量）。
const double kRailReservedWidth = 84;

/// §4 底部任务栏。
///
/// 高度只有一个来源：内容行 + 顶部 1dp 分割线。任务栏的 `SizedBox`、
/// 舞台 inset 回退值 [`taskbarReservedHeight`] 都从这里推导，
/// 任何一处改常量而另一处没跟上，`test/taskbar_layout_test.dart` 会红。
const double kTaskbarDividerWidth = 1;
const double kTaskbarContentHeight = 55;
const double kTaskbarHeight = kTaskbarContentHeight + kTaskbarDividerWidth;
const Color kTaskbarColor = Color(0xFF000000);
const Color kTaskbarDividerColor = Color(0x1AFFFFFF);
const double kTaskbarIconSize = 24;
const double kTaskbarSpacing = 28;
const double kTaskbarNarrowSpacing = 20;
const double kTaskbarMinSpacing = 16;
const Color kTaskbarInactiveColor = Color(0xB3FFFFFF);
const double kTaskbarSidePadding = 16;

/// §4 任务栏控件间距：默认 28dp；320dp 窄屏压到 20dp，最低 16dp。
double taskbarSpacingFor(double screenWidth) {
  final w = screenWidth.isFinite && screenWidth > 0 ? screenWidth : 375.0;
  if (w >= 360) return kTaskbarSpacing;
  if (w <= 320) return kTaskbarNarrowSpacing;
  final t = (w - 320) / 40;
  final v =
      kTaskbarNarrowSpacing + (kTaskbarSpacing - kTaskbarNarrowSpacing) * t;
  return v.clamp(kTaskbarMinSpacing, kTaskbarSpacing).toDouble();
}

// ---------------------------------------------------------------------------
// P1b：非全屏长按菜单 + 评论半屏面板（DOUYIN_UX_SPEC.md §8/§9，
// 动画取 DOUYIN_VISUAL_SPEC.md §5：200ms easeOut）。
// 只服务非全屏；全屏分支不调用以下任何一项。
// ---------------------------------------------------------------------------

/// §8 长按判定：按住 ≥500ms、位移 ≤12px 才算长按。
const int kStageLongPressMs = 500;
const double kStageLongPressMaxMove = 12;

/// §8 长按菜单项文案（顺序即展示顺序）。
const List<String> kStageMenuLabels = <String>[
  '不感兴趣',
  '保存到本机',
  '复制文案',
  '举报',
];

/// §9 评论面板：初始 60% 屏高，再次上滑到全屏，下滑关闭。
const double kCommentPanelInitialFraction = 0.6;
const double kCommentPanelFullFraction = 1.0;
const double kCommentPanelClosedFraction = 0.0;

/// §5 面板动画 200ms easeOut；遮罩黑 40%。
const int kOverlayAnimMs = 200;
const Color kStageScrimColor = Color(0x66000000);
const Color kStageMenuBackground = Color(0xE6000000);

/// 上滑/下滑速度阈值（px/s）：超过即按方向 snap。
const double kCommentPanelFlingVelocity = 420;

/// §8 长按可触发区域：排除顶栏、底部进度/任务栏与右侧互动栏，
/// 避免按在控件上误弹菜单。
bool stageLongPressAllowed({
  required Offset position,
  required Size stageSize,
  required double topInset,
  required double bottomInset,
  required double rightInset,
  required bool fullscreen,
}) {
  if (fullscreen) return false;
  if (position.dy < topInset + 44) return false;
  if (position.dy > stageSize.height - bottomInset) return false;
  if (position.dx > stageSize.width - rightInset) return false;
  return true;
}

/// 长按手势跟踪器：按下 → 位移超限取消 → 时间到且仍合格即触发。
class StageLongPressTracker {
  StageLongPressTracker({
    this.holdMs = kStageLongPressMs,
    this.maxMove = kStageLongPressMaxMove,
  });

  final int holdMs;
  final double maxMove;

  int? _startMs;
  Offset? _startPos;
  bool _moved = false;
  bool _fired = false;

  bool get tracking => _startMs != null;
  bool get fired => _fired;

  void begin({required int nowMs, required Offset pos}) {
    _startMs = nowMs;
    _startPos = pos;
    _moved = false;
    _fired = false;
  }

  /// 指针移动；返回 false 表示已超出位移阈值而被取消。
  bool update(Offset pos) {
    final start = _startPos;
    if (start == null) return false;
    if ((pos - start).distance > maxMove) {
      _moved = true;
      return false;
    }
    return true;
  }

  /// 定时器到点时判定是否应触发（只触发一次）。
  bool shouldFire(int nowMs) {
    final start = _startMs;
    if (start == null || _fired) return false;
    if (_moved) return false;
    // 阈值判定只有这一处：舞台长按的全部路径都走本跟踪器。
    return nowMs - start >= holdMs;
  }

  void fire() => _fired = true;

  void cancel() {
    _startMs = null;
    _startPos = null;
  }
}

/// §9 评论面板位置 snap：当前高度比例 + 手势速度 → 目标比例（0 / 0.6 / 1）。
///
/// 速度正方向为向下（下拉收紧），负方向为向上（上滑展开）。
double commentPanelSnap({
  required double fraction,
  required double velocity,
  double initial = kCommentPanelInitialFraction,
}) {
  // `NaN.clamp(0,1)` **返回 1.0**（clamp 不消 NaN，NaN 落不进区间就走上界）。
  // 于是「面板比例未知」被判成「已展开到 100%」：手势在第一帧上报、或
  // `_commentFraction` 被非有限值写脏时，松手会把面板吸到全屏而不是原来的档位。
  // 与 [commentPanelHeight]（非有限 → 0，视为关闭）口径保持一致：这里把
  // 非有限比例按「关闭」处理，非有限初值按默认档。
  final f = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
  final initialTarget =
      initial.isFinite ? initial.clamp(0.0, 1.0) : kCommentPanelInitialFraction;
  // 速度非有限时不能进方向判定：`velocity <= -x` 与 `>= x` 对 NaN 都是
  // false（会走到下面的纯比例分支），对 ±Infinity 恒真（一路判成上甩/下甩）。
  // 按「没有速度」处理，只用比例决定档位。
  final v = velocity.isFinite ? velocity : 0.0;
  if (v <= -kCommentPanelFlingVelocity) {
    // 上滑：从 60% 继续上甩直接到全屏；几乎不可见时才回到初始档。
    return f > 0.3 ? kCommentPanelFullFraction : initialTarget;
  }
  if (v >= kCommentPanelFlingVelocity) {
    if (f < 0.5) return kCommentPanelClosedFraction;
    return f > 0.85 ? initialTarget : kCommentPanelClosedFraction;
  }
  if (f < initialTarget * 0.5) return kCommentPanelClosedFraction;
  if (f < (initialTarget + kCommentPanelFullFraction) / 2) {
    return initialTarget;
  }
  return kCommentPanelFullFraction;
}

/// 面板比例 → 面板高度（非负，不超过屏幕高度）。
double commentPanelHeight({
  required double fraction,
  required double screenHeight,
}) {
  // 同上：`screenHeight` 非有限时结果是 NaN/Infinity，而它直接进
  // `SizedBox(height:)` / `Positioned(bottom:)`，NaN 在布局阶段断言失败。
  // 返回 0 表示「面板没有高度」，由调用方按关闭态渲染。
  if (!screenHeight.isFinite || screenHeight <= 0) return 0;
  final f = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
  return f * screenHeight;
}

/// 桌面端可落盘保存；Android/iOS 暂无下载目录权限，提示暂不可用。
bool mediaDownloadSupported({required bool android, required bool ios}) =>
    !(android || ios);

/// 从媒体 URL 推断保存文件扩展名（含点），无扩展名时按媒体类型兜底。
///
/// 不能只看「最后一个点」：路径里的目录名经常带点（`2026.11/作品`、
/// `v1.2/a`）。取到的「扩展名」会带进 `/`，实测
/// `http://h/media/lib-1/2026.11/x` → `.11/x`，落盘文件名里出现分隔符，
/// 保存直接失败或写到别的目录里。
///
/// 所以先把路径截到最后一个 `/` 之后，再要求扩展名只含字母数字——
/// 不满足就当作没扩展名，回落到按媒体类型给的 `.mp4`/`.jpg`。
String mediaSaveExtension({required String url, bool video = true}) {
  final path = Uri.tryParse(url)?.path ?? url;
  final slash = path.lastIndexOf('/');
  final name = slash >= 0 ? path.substring(slash + 1) : path;
  final dot = name.lastIndexOf('.');
  if (dot > 0 && dot < name.length - 1) {
    final ext = name.substring(dot).toLowerCase();
    if (ext.length <= 6 && RegExp(r'^\.[a-z0-9]+$').hasMatch(ext)) return ext;
  }
  return video ? '.mp4' : '.jpg';
}

/// 生成本机保存用的安全文件名（保留扩展名，去掉路径分隔符等字符）。
String mediaSaveFileName({
  required String base,
  required String url,
  bool video = true,
}) {
  final buf = StringBuffer();
  for (final ch in base.trim().runes) {
    final s = String.fromCharCode(ch);
    if (RegExp(r'[\\/:*?"<>|\x00-\x1f]').hasMatch(s)) continue;
    buf.write(s);
  }
  var name = buf.toString().trim();
  if (name.isEmpty) name = 'dizi_${DateTime.now().millisecondsSinceEpoch}';
  // runes 循环已经保证这里是完整码点，不会切开代理对；
  // 但 80 上限仍按 runes 切（不是 code unit），否则 emoji 文件名会被截成
  // 半个字符，落盘后文件名显示为方块。
  if (name.runes.length > 80) {
    name = String.fromCharCodes(name.runes.take(80));
  }
  return name + mediaSaveExtension(url: url, video: video);
}

/// 呼出式进度条（owner 2026-11-18）。
///
/// 规格：紧跟任务栏上缘、极细；不操作时完全不可见；手指触到底部热区才在
/// 指下放大并可直接拖动；拖动过程**不暂停**视频，只显示预览时间；松手按
/// 所选位置跳转，随后缩回细条，3 秒后消失。Windows 端常驻细条。
const double kScrubHotZoneHeight = 28;
const double kScrubThinHeight = 2.5;
const double kScrubActiveHeight = 10;
const double kScrubKnobRadius = 6;
const double kScrubBubbleGap = 12;
/// 气泡预留高度：气泡本身 + 间距，热区总高度要把它算进去，否则会被裁掉。
const double kScrubBubbleSpace = 34;
const int kScrubThinHoldMs = 3000;
const int kScrubFadeMs = 180;

const Color kScrubTrackColor = Color(0x40FFFFFF);
const Color kScrubPlayedColor = Color(0xFFFFFFFF);

/// 滑块中心 x：按比例落在轨道内，并夹住半径，避免半个圆出界。
double scrubKnobX({
  required double trackWidth,
  required double fraction,
  double knobRadius = kScrubKnobRadius,
}) {
  // `trackWidth` 来自 `LayoutBuilder`，在「还没量出宽度 / 放在无界约束里」
  // 的中间态可以是 `Infinity`。旧守卫只判 `<= 0`，而 `infinity <= 0` 为
  // false——`(∞ * f).clamp(r, ∞ - r)` 直接返回 **Infinity**，交给
  // `Positioned(left:)` 就是布局断言失败（整页灰屏）。非有限值按「没有
  // 轨道」处理，与 `<= 0` 走同一条出口。
  if (!trackWidth.isFinite || trackWidth <= 0) return 0;
  final f = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
  // 半径同样可能是 NaN（外部直接传布局值）：先归零，再夹到半轨道内。
  final rawR = (knobRadius.isFinite && knobRadius > 0) ? knobRadius : 0.0;
  final half = trackWidth / 2;
  final r = rawR > half ? half : rawR;
  return (trackWidth * f).clamp(r, trackWidth - r);
}

class ScrubBar extends StatelessWidget {
  const ScrubBar({
    super.key,
    required this.fraction,
    required this.active,
    required this.visible,
    this.labelFor,
  });

  final ValueListenable<double> fraction;
  final bool active;
  final bool visible;

  /// 按当前比例生成时间文案（拖动时实时更新）。
  final String Function(double)? labelFor;

  @override
  Widget build(BuildContext context) {
    final h = active ? kScrubActiveHeight : kScrubThinHeight;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: kScrubFadeMs),
      curve: Curves.easeOut,
      child: SizedBox(
        // 高度包含气泡空间：气泡画在进度条上方，不能被父级裁剪。
        height: kScrubHotZoneHeight + kScrubBubbleSpace,
        child: ValueListenableBuilder<double>(
          valueListenable: fraction,
          builder: (_, f, __) => LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth;
          final x = scrubKnobX(trackWidth: w, fraction: f, knobRadius: 0);
          final timeLabel = labelFor?.call(f) ?? '';
          return Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: h,
                decoration: const BoxDecoration(color: kScrubTrackColor),
              ),
            ),
            Positioned(
              left: 0,
              width: x,
              bottom: 0,
              child: Container(
                height: h,
                decoration: const BoxDecoration(color: kScrubPlayedColor),
              ),
            ),
            if (active) ...[
              // owner 2026-11-18：去掉末端圆点，纯条状更干净。
              if (timeLabel.isNotEmpty)
                Positioned(
                  // owner 2026-11-18：时间固定显示在进度条正上方居中，
                  // 不再跟着滑块移动，避免和头像/简介区重叠。
                  left: 0,
                  right: 0,
                  bottom: h + kScrubBubbleGap,
                  child: Center(child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kSeekBubbleColor,
                      borderRadius: BorderRadius.circular(kSeekBubbleRadius),
                    ),
                    child: Text(timeLabel,
                        style: kSeekBubbleTextStyle
                            .copyWith(fontFeatures: const [
                          FontFeature.tabularFigures()
                        ])),
                  )),
                ),
            ],
          ]);
        }),
        ),
      ),
    );
  }
}
