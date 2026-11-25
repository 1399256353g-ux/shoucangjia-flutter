import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'unit_fraction.dart';

/// M9：作者页「抖音式跟手拖拽」。
///
/// 播放页向左拖动时，作者页跟着手指从右侧滑入（位移跟手、超过 60% 后加阻尼）；
/// 松手时进度 ≥ 30% 或左向速度足够则完成进入，否则回弹原位。
/// 进入后从左侧边缘右滑可反向跟手收回，进度 ≤ 70% 或右向速度足够则关闭。
///
/// 纯策略部分（[AuthorDrag]）不依赖 widget，便于回归测试。
class AuthorDrag {
  const AuthorDrag._();

  /// 松手完成进入所需的最小进度（占屏宽比例）。
  static const double completeFraction = 0.3;


  /// 视为「甩动完成」的速度阈值（逻辑像素/秒，取绝对值）。
  static const double flingVelocity = 700;

  /// 超过该进度后开始加阻尼，避免拖过头露出黑底。
  static const double dampStart = 0.6;

  /// 阻尼区里位移的折算比例。
  static const double dampFactor = 0.55;

  static const int openMs = 200;
  static const int closeMs = 170;

  /// 作者页左侧可触发「右滑收回」的边缘宽度。
  static const double edgeDragWidth = 36;

  /// 手指横向位移 → 进度（0..1）。前 [dampStart] 线性跟手，之后加阻尼。
  static double progress({required double dx, required double width}) {
    // `width <= 0` 拦不住 NaN：`NaN <= 0` 为 false，随后 `dx / NaN` 得到 NaN，
    // 一路传进 `AnimationController.value`（它只夹紧不消 NaN），作者页整层
    // 变成不可见也不可关的空白。非有限值按「还没有可拖动宽度」处理。
    if (!width.isFinite || width <= 0 || !dx.isFinite) return 0;
    final raw = dx / width;
    if (raw <= 0) return 0;
    if (raw <= dampStart) return raw;
    final extra = (raw - dampStart) * dampFactor;
    final p = dampStart + extra;
    return p > 1 ? 1 : p;
  }

  /// 松手时是否完成进入。
  static bool completes({required double progress, required double velocity}) =>
      progress >= completeFraction || velocity <= -flingVelocity;

  /// 反向拖拽松手时是否收回。
  static bool dismisses({required double progress, required double velocity}) =>
      progress <= 1 - completeFraction || velocity >= flingVelocity;

  /// 反向拖拽：从 [start] 起按手指位移折算进度（右移减小）。
  static double progressFromClose({
    required double start,
    required double dx,
    required double width,
  }) {
    if (!width.isFinite || width <= 0 || !dx.isFinite) return start;
    final p = start - dx / width;
    if (!p.isFinite) return start;
    if (p < 0) return 0;
    return p > 1 ? 1 : p;
  }
}

/// 左滑进作者页的「能不能起手」判定（owner 2026-11-22）。
///
/// 全部规则集中在这里，播放页只负责传当次实测值：
///  - 从作者页进来的作品：永远不能（否则原地绕回同一作者）；
///  - 非全屏：只有右侧 [edgeWidth] 内起手才算（避免画面中间误触）；
///  - 全屏：任意位置可起手，但**任务栏区域除外**（任务栏可见时，
///    底部 [taskbarHeight] 内起手交给任务栏/进度条）；
///  - 宽度/高度非法时不放行，避免除以 0 后的误判。
bool authorDragAllowed({
  required bool fromAuthor,
  required bool fullscreen,
  required double startDx,
  required double startDy,
  required double width,
  required double screenHeight,
  required double taskbarHeight,
  required bool taskbarVisible,
  double edgeWidth = 48,
}) {
  if (fromAuthor) return false;
  if (width <= 0) return false;
  if (!fullscreen) {
    // 右边缘起手：startDx 距右边不足 edgeWidth。
    return width - startDx <= edgeWidth;
  }
  // 全屏：排除任务栏热区（只在任务栏可见时排除；隐藏后该区域是普通画面）。
  if (taskbarVisible &&
      taskbarHeight > 0 &&
      screenHeight > 0 &&
      startDy >= screenHeight - taskbarHeight) {
    return false;
  }
  return true;
}

/// 自带 Ticker 的 vsync。
///
/// 关键：不能让这个控制器用「播放页」的 TickerProvider——作者页路由推上来后，
/// 播放页被 TickerMode 静音，`animateTo` 的 Future 永远不会完成，收起的 pop()
/// 也就永远不执行，最后留下一层挡住输入的路由（表现为「返回必卡死」）。
class _FreeTickerProvider implements TickerProvider {
  const _FreeTickerProvider();
  @override
  Ticker createTicker(TickerCallback onTick) =>
      Ticker(onTick, debugLabel: 'author-drag');
}

/// 作者页滑入/收回的共享进度（0=完全隐藏，1=完全展开）。
class AuthorDragController extends ChangeNotifier {
  AuthorDragController()
      : _c = AnimationController(
          vsync: const _FreeTickerProvider(),
          duration: const Duration(milliseconds: AuthorDrag.openMs),
        ) {
    _c.addListener(notifyListeners);
  }

  final AnimationController _c;

  double get progress => _c.value;

  set progress(double v) {
    _c.stop();
    // 手写 `isNaN ? 0 : clamp` 只挡了 NaN，没挡 ±Infinity
    // （`∞` 会被夹成 1.0，表现为「一拖就到底」）。
    _c.value = unitFraction(v);
  }

  /// 松手后吸附到 0（关闭）或 1（进入）。
  Future<void> settleTo(double target, {required bool opening}) {
    final ms = opening ? AuthorDrag.openMs : AuthorDrag.closeMs;
    return _c.animateTo(
      unitFraction(target),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _c.removeListener(notifyListeners);
    _c.dispose();
    super.dispose();
  }
}

/// 承载作者页的透明路由：页面内容由 [builder] 生成，位置完全由 [drag] 决定。
class AuthorDragRoute extends PageRoute<void> {
  AuthorDragRoute({required this.builder, required this.drag});
  final WidgetBuilder builder;
  final AuthorDragController drag;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get barrierDismissible => false;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
          BuildContext context, Animation<double> animation, Animation<double> secondary) =>
      builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondary, Widget child) =>
      _AuthorDragHost(drag: drag, child: child);
}

class _AuthorDragHost extends StatefulWidget {
  const _AuthorDragHost({required this.drag, required this.child});
  final AuthorDragController drag;
  final Widget child;

  @override
  State<_AuthorDragHost> createState() => _AuthorDragHostState();
}

class _AuthorDragHostState extends State<_AuthorDragHost> {
  double _startProgress = 0;
  double _dragDx = 0;
  bool _closing = false;

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    // 兜底：动画万一没跑（ticker 被静音/页面销毁），也不能把路由留在原地
    // 挡住输入。超时就强制 pop，宁可少一段动画，也不能卡死。
    await widget.drag
        .settleTo(0, opening: false)
        .timeout(const Duration(milliseconds: 400), onTimeout: () {});
    if (!mounted) return;
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    // canPop:false 只拦截 maybePop（返回键/AppBar），这里主动 pop 直接移除路由。
    if (nav.canPop()) {
      nav.pop();
    } else if (route != null) {
      nav.removeRoute(route);
    }
  }

  void _edgeStart(DragStartDetails d) {
    _startProgress = widget.drag.progress;
    _dragDx = 0;
  }

  void _edgeUpdate(DragUpdateDetails d, double width) {
    _dragDx += d.delta.dx;
    widget.drag.progress = AuthorDrag.progressFromClose(
        start: _startProgress, dx: _dragDx, width: width);
  }

  void _edgeEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (AuthorDrag.dismisses(progress: widget.drag.progress, velocity: v)) {
      _close();
    } else {
      widget.drag.settleTo(1, opening: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnimatedBuilder(
        animation: widget.drag,
        builder: (context, child) {
          final p = widget.drag.progress;
          final offset = (1 - p) * w;
          return Stack(children: [
            // 轻微压暗下层播放页，进度越大越暗
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.25 * p)),
              ),
            ),
            Transform.translate(
              offset: Offset(offset, 0),
              child: SizedBox(
                width: w,
                height: size.height,
                child: IgnorePointer(
                  ignoring: p < 0.999,
                  child: child,
                ),
              ),
            ),
            // 展开后：左侧边缘右滑跟手收回
            if (p >= 0.999)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: AuthorDrag.edgeDragWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: _edgeStart,
                  onHorizontalDragUpdate: (d) => _edgeUpdate(d, w),
                  onHorizontalDragEnd: _edgeEnd,
                ),
              ),
          ]);
        },
        child: widget.child,
      ),
    );
  }
}
