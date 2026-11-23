/// M2/M3：播放页底部任务栏的通用控件。
///
/// M2 要求「全屏且功能区呼出时」任务栏出现播放/暂停与横竖屏切换；
/// M3 要求 Windows 保持原交互——有播放/暂停（状态双向同步），但不得
/// 出现横竖屏按钮。这里把纯逻辑与两个按钮拆出来，便于单元/组件测试。
library;

import 'package:flutter/foundation.dart';
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

/// §5 暂停提示：暂停时只显示播放图标，0.8s / Curves.easeOut 淡出。
const int kPlayHintFadeMs = 800;

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

// ---------------------------------------------------------------------------
// P1：抖音式非全屏播放页——右侧互动栏 / 左侧信息区 / 底部任务栏。
// 数值严格取自 DOUYIN_VISUAL_SPEC.md §1/§2/§4；只服务非全屏，全屏不调用。
// ---------------------------------------------------------------------------

/// §1 右侧互动栏。
const double kRailAvatarSize = 44;
const double kRailBadgeSize = 22;
const double kRailBadgeOverhang = 8; // 徽标向下突出头像底边
const Color kRailAccent = Color(0xFFFE2C55);
const double kRailIconSize = 32;
const double kRailCountFontSize = 11;
const FontWeight kRailCountWeight = FontWeight.w500;
const double kRailIconCountGap = 2;
const double kRailItemGap = 18;
const double kRailRightMargin = 10;
const double kRailBottomGap = 12;
const double kRailAvatarGap = 20;
const double kRailTouchSize = 48;

/// §2 文案最大宽度的预留：右侧互动栏约 84dp（44 头像 + 10 右边距 + 余量）。
const double kRailReservedWidth = 84;

/// §2 左侧信息区。
const double kInfoLeftMargin = 12;
const double kAuthorFontSize = 15;
const FontWeight kAuthorWeight = FontWeight.w600;
const double kAuthorCaptionGap = 8;
const double kCaptionFontSize = 14;
const double kCaptionHeight = 1.35;
const int kCaptionMaxLines = 2;
const double kCaptionMusicGap = 10;
const double kMusicFontSize = 13;
const Color kInfoSecondaryColor = Color(0xE6FFFFFF);
const double kMusicIconSize = 16;
const double kMusicIconGap = 6;
const double kMarqueeSpeed = 40; // px/s
const Duration kMarqueePause = Duration(seconds: 2);
const double kInfoBottomGap = 12;

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

/// §2 信息区文字最大宽度 = 屏宽 − 右侧栏宽 − 左边距。
double infoAreaMaxWidth(double screenWidth) {
  if (!screenWidth.isFinite || screenWidth <= 0) return 0;
  final w = screenWidth - kRailReservedWidth - kInfoLeftMargin;
  return w > 0 ? w : 0;
}

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

/// §1 互动数字：0 不显示；≥10000 用「x.x万」（与抖音一致的紧凑写法）。
String formatRailCount(int n) {
  if (n <= 0) return '';
  if (n < 10000) return '$n';
  final v = n / 10000;
  final s = v >= 100 ? v.round().toString() : v.toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}万';
}

/// §2 跑马灯位移：文字比可视区宽才滚动，到末尾停 [pauseSeconds] 秒后从头再来。
/// 返回负值表示向左移动的距离。
double marqueeOffsetAt({
  required double elapsedSeconds,
  required double textWidth,
  required double viewWidth,
  double speed = kMarqueeSpeed,
  double pauseSeconds = 2,
}) {
  final distance = textWidth - viewWidth;
  if (distance <= 0 || speed <= 0) return 0;
  final travel = distance / speed;
  final cycle = travel + (pauseSeconds > 0 ? pauseSeconds : 0);
  if (cycle <= 0) return 0;
  final t = elapsedSeconds % cycle;
  if (t >= travel) return -distance;
  return -speed * t;
}

/// §2 跑马灯一轮的完整时长（滚动 + 停顿），用于动画控制器。
double marqueeCycleSeconds({
  required double textWidth,
  required double viewWidth,
  double speed = kMarqueeSpeed,
  double pauseSeconds = 2,
}) {
  final distance = textWidth - viewWidth;
  if (distance <= 0 || speed <= 0) return 0;
  return distance / speed + (pauseSeconds > 0 ? pauseSeconds : 0);
}

/// §2 文案是否真的需要「展开」：超过 2 行即需要。
bool captionNeedsExpand(
  String text,
  TextStyle style,
  double maxWidth, {
  TextScaler textScaler = TextScaler.noScaling,
  Locale? locale,
}) {
  if (text.isEmpty || maxWidth <= 0) return false;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: kCaptionMaxLines,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    locale: locale,
  )..layout(maxWidth: maxWidth);
  final exceeded = painter.didExceedMaxLines;
  painter.dispose();
  return exceeded;
}

const TextStyle kRailCountStyle = TextStyle(
  fontSize: kRailCountFontSize,
  fontWeight: kRailCountWeight,
  color: Colors.white,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// §1 右侧互动栏：头像 + 「关注」徽标 + 4 个互动项。
///
/// 底部由调用方用 Positioned 锚到「任务栏上沿 − 12dp」的基线；这里只负责
/// 栏内节奏（头像下 20dp、项间 18dp、每项 48dp 触控热区）。
class PlayerInteractionRail extends StatelessWidget {
  const PlayerInteractionRail({
    super.key,
    required this.avatar,
    required this.liked,
    required this.onLike,
    required this.onComment,
    required this.onFavorite,
    required this.onShare,
    this.likeCount = 0,
    this.commentCount = 0,
    this.favoriteCount = 0,
    this.favorited = false,
  });

  final Widget avatar;
  final bool liked;
  final bool favorited;
  final int likeCount;
  final int commentCount;
  final int favoriteCount;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onFavorite;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 头像 44dp + 底部向下突出 8dp 的 22dp 红色加号徽标
        SizedBox(
          width: kRailAvatarSize,
          height: kRailAvatarSize + kRailBadgeOverhang,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              ClipOval(
                child: SizedBox(
                  width: kRailAvatarSize,
                  height: kRailAvatarSize,
                  child: avatar,
                ),
              ),
              Positioned(
                // 徽标底边 = 头像底边 + 8dp
                top: kRailAvatarSize - kRailBadgeSize + kRailBadgeOverhang,
                child: IgnorePointer(
                  child: Container(
                    width: kRailBadgeSize,
                    height: kRailBadgeSize,
                    decoration: const BoxDecoration(
                        color: kRailAccent, shape: BoxShape.circle),
                    child: const Icon(Icons.add, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: kRailAvatarGap),
        _RailItem(
          icon: Icons.favorite,
          color: liked ? kRailAccent : Colors.white,
          count: formatRailCount(likeCount),
          onTap: onLike,
          semanticLabel: '点赞',
        ),
        const SizedBox(height: kRailItemGap),
        _RailItem(
          icon: Icons.mode_comment_outlined,
          color: Colors.white,
          count: formatRailCount(commentCount),
          onTap: onComment,
          semanticLabel: '评论',
        ),
        const SizedBox(height: kRailItemGap),
        _RailItem(
          icon: favorited ? Icons.star : Icons.star_border,
          color: Colors.white,
          count: formatRailCount(favoriteCount),
          onTap: onFavorite,
          semanticLabel: '收藏',
        ),
        const SizedBox(height: kRailItemGap),
        _RailItem(
          icon: Icons.share,
          color: Colors.white,
          count: '',
          onTap: onShare,
          semanticLabel: '分享',
        ),
      ],
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.icon,
    required this.color,
    required this.count,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final Color color;
  final String count;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _down = false;

  void _setDown(bool v) {
    if (_down == v || !mounted) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minWidth: kRailTouchSize, minHeight: kRailTouchSize),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: _down ? kPressScaleTo : 1.0,
                duration: const Duration(milliseconds: kPressScaleMs),
                curve: Curves.easeOut,
                child:
                    Icon(widget.icon, size: kRailIconSize, color: widget.color),
              ),
              if (widget.count.isNotEmpty) ...[
                const SizedBox(height: kRailIconCountGap),
                Text(widget.count, style: kRailCountStyle),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// §2 左侧信息区：@作者 / 2 行文案（可展开）/ 音乐跑马灯。
class PlayerInfoPanel extends StatelessWidget {
  const PlayerInfoPanel({
    super.key,
    required this.author,
    required this.caption,
    required this.music,
    required this.maxWidth,
    this.expanded = false,
    this.onToggleExpand,
    this.onAuthorTap,
  });

  final String author;
  final String caption;
  final String music;
  final double maxWidth;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onAuthorTap;

  static const TextStyle _captionStyle = TextStyle(
    fontSize: kCaptionFontSize,
    height: kCaptionHeight,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final needsExpand = !expanded &&
        captionNeedsExpand(caption, _captionStyle, maxWidth,
            textScaler: textScaler, locale: locale);
    return SizedBox(
      width: maxWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onAuthorTap,
            child: Text(
              '@$author',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: kAuthorFontSize,
                fontWeight: kAuthorWeight,
                color: Colors.white,
              ),
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: kAuthorCaptionGap),
            if (expanded)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(caption, style: _captionStyle),
                  GestureDetector(
                    onTap: onToggleExpand,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('收起',
                          style: TextStyle(
                              fontSize: kCaptionFontSize,
                              color: Colors.white70)),
                    ),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      caption,
                      maxLines: kCaptionMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: _captionStyle,
                    ),
                  ),
                  if (needsExpand)
                    GestureDetector(
                      onTap: onToggleExpand,
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text('展开',
                            style: TextStyle(
                                fontSize: kCaptionFontSize,
                                color: Colors.white70)),
                      ),
                    ),
                ],
              ),
          ],
          if (music.isNotEmpty) ...[
            const SizedBox(height: kCaptionMusicGap),
            Row(
              children: [
                const Icon(Icons.music_note,
                    size: kMusicIconSize, color: kInfoSecondaryColor),
                const SizedBox(width: kMusicIconGap),
                Expanded(
                  child: MarqueeText(
                    music,
                    style: const TextStyle(
                        fontSize: kMusicFontSize, color: kInfoSecondaryColor),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// §2 音乐跑马灯：40px/s，一轮结束停 2s 后重来；文字不超宽时静止。
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    required this.style,
    this.speed = kMarqueeSpeed,
    this.pause = kMarqueePause,
  });

  final String text;
  final TextStyle style;
  final double speed;
  final Duration pause;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  double _textW = 0;
  double _viewW = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _sync(double textW, double viewW) {
    if ((textW - _textW).abs() < 0.5 && (viewW - _viewW).abs() < 0.5) return;
    _textW = textW;
    _viewW = viewW;
    final cycle = marqueeCycleSeconds(
      textWidth: textW,
      viewWidth: viewW,
      speed: widget.speed,
      pauseSeconds: widget.pause.inMilliseconds / 1000,
    );
    if (cycle <= 0) {
      _c.stop();
      return;
    }
    _c.duration = Duration(milliseconds: (cycle * 1000).round());
    _c.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (ctx, cons) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final textW = painter.width;
      painter.dispose();
      final viewW = cons.maxWidth;
      if (!viewW.isFinite || textW <= viewW) {
        return Text(widget.text,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: widget.style);
      }
      _sync(textW, viewW);
      final cycle = marqueeCycleSeconds(
        textWidth: textW,
        viewWidth: viewW,
        speed: widget.speed,
        pauseSeconds: widget.pause.inMilliseconds / 1000,
      );
      return ClipRect(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final dx = marqueeOffsetAt(
              elapsedSeconds: _c.value * cycle,
              textWidth: textW,
              viewWidth: viewW,
              speed: widget.speed,
              pauseSeconds: widget.pause.inMilliseconds / 1000,
            );
            return Transform.translate(
              offset: Offset(dx, 0),
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                style: widget.style,
              ),
            );
          },
        ),
      );
    });
  }
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

/// §8 长按判定纯逻辑：按住时长与最大位移。
bool stageLongPressQualifies({
  required int holdMs,
  required double moved,
  int holdMsThreshold = kStageLongPressMs,
  double maxMove = kStageLongPressMaxMove,
}) =>
    holdMs >= holdMsThreshold && moved <= maxMove;

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
    if (nowMs - start < holdMs) return false;
    return true;
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
  final f = fraction.clamp(0.0, 1.0);
  final initialTarget = initial.clamp(0.0, 1.0);
  if (velocity <= -kCommentPanelFlingVelocity) {
    // 上滑：从 60% 继续上甩直接到全屏；几乎不可见时才回到初始档。
    return f > 0.3 ? kCommentPanelFullFraction : initialTarget;
  }
  if (velocity >= kCommentPanelFlingVelocity) {
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
}) =>
    (fraction.clamp(0.0, 1.0)) * screenHeight;

/// 桌面端可落盘保存；Android/iOS 暂无下载目录权限，提示暂不可用。
bool mediaDownloadSupported({required bool android, required bool ios}) =>
    !(android || ios);

/// 从媒体 URL 推断保存文件扩展名（含点），无扩展名时按媒体类型兜底。
String mediaSaveExtension({required String url, bool video = true}) {
  final path = Uri.tryParse(url)?.path ?? url;
  final dot = path.lastIndexOf('.');
  if (dot > 0 && dot < path.length - 1) {
    final ext = path.substring(dot).toLowerCase();
    if (ext.length <= 6) return ext;
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
  if (name.length > 80) name = name.substring(0, 80);
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
  if (trackWidth <= 0) return 0;
  final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
  final r = knobRadius.clamp(0.0, trackWidth / 2);
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
