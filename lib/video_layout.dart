/// O4：手机端底部任务栏跟随视频画面下沿。
///
/// 播放器用 `BoxFit.contain` 渲染，竖屏播放宽屏视频时上下会留黑边。
/// 任务栏原先固定贴屏幕最底，离画面很远；这里按视频宽高比算出实际
/// 画面矩形，把任务栏 Positioned 到画面下沿（全屏时仍贴屏幕底）。
/// 计算保持纯函数，便于单元测试。
///
/// T：任务栏改为贴屏幕最底的不透明实底后，视频舞台（PageView 单页）
/// 按屏高 − 栏高内缩；进度条等随页元素则贴在本页舞台底边。相关纯函数
/// （[stageBottomInset] / [stageProgressBottomOffset] /
/// [stageProgressOverlayHeight]）同样集中在这里，便于回归测试。
library;

import 'dart:ui' show Size;

/// 视频显示模式。`fill` = 铺满（BoxFit.cover + 裁剪），
/// `contain` = 适应（BoxFit.contain，留黑边）。
enum VideoFit { fill, contain }

/// 竖屏判定阈值：源宽高比（宽/高）小于此值视为竖屏。
const double portraitAspectThreshold = 0.8;

/// 允许为了铺满而裁掉的最大比例（8%）。超过就必须「适应」保原比例。
const double maxFillCrop = 0.08;

/// 竖屏源在竖屏容器里允许的最大裁切（30%）。
/// 9:16 → 9:19.5 约 15%，仍算「放大顶边」；接近方形则接近 40%，必须适应。
const double maxPortraitFillCrop = 0.30;

/// 按源比例与用户覆盖设置决定填充模式。
///
/// owner 2026-11-18 规则：
/// - 竖屏（宽/高 ≤ [portraitAspectThreshold]，含 3:4）→ 铺满，画面下缘正好
///   压在进度条上缘，进度条就是视频与任务栏的分界线；
/// - 横板（宽/高 > 阈值，如 16:9 / 21:9）→ 必须保持完整画面，**不裁不拉伸**，
///   水平撑满、垂直居中，上下留黑（抖音频道的横屏视频也是画面很小）；
///   此时视频下缘不贴进度条，中间是黑区；
/// - 宽高比未知（首帧未就绪）→ 铺满，避免先闪一圈黑边再跳。
///
/// 为什么横板不能铺满：9:16 舞台里 cover 一个 16:9 源，需要把宽度撑到
/// 28.4 个舞台宽度，左右各裁掉约 68%，画面基本被毁。
VideoFit videoFitFor({double? aspect, VideoFit? mode, double? containerAspect}) {
  if (mode != null) return mode;
  // owner 2026-11-18：竖屏源在竖屏容器里一律「铺满」（与抖音一致）。
  // iPhone 9:19.5 屏幕放 9:16 视频时，铺满只横向裁掉约 15%，观感是满屏；
  // 按 8% 阈值改适应反而上下留黑边、被灵动岛切一块，很难看。
  // 只有「竖屏源 + 宽容器」（如 Windows 宽窗口）才保比例，避免裁成横条。
  if (aspect != null && aspect > 0 && containerAspect != null && containerAspect > 0) {
    if (aspect <= portraitAspectThreshold && containerAspect <= portraitAspectThreshold) {
      // 只允许「小幅放大顶到上下边」：9:16 放进 9:19.5 屏约裁 15%，保留铺满；
      // 接近方形（如 0.79）要裁近 40%，那就不是「顶边」而是毁画面，改适应。
      final cropW = aspect > containerAspect
          ? 1 - containerAspect / aspect
          : 0.0;
      return cropW <= maxPortraitFillCrop ? VideoFit.fill : VideoFit.contain;
    }
    final cropW = aspect > containerAspect ? 1 - containerAspect / aspect : 0.0;
    final cropH = aspect < containerAspect ? 1 - aspect / containerAspect : 0.0;
    final crop = cropW > cropH ? cropW : cropH;
    return crop <= maxFillCrop ? VideoFit.fill : VideoFit.contain;
  }
  // owner 2026-11-18：比例未知时一律「适应」，绝不先按铺满放大裁切。
  // 之前 default=fill 会让横板视频在首帧前被放大裁掉大半，观感像强行拉伸。
  if (aspect == null || aspect <= 0) return VideoFit.contain;
  return aspect > portraitAspectThreshold ? VideoFit.contain : VideoFit.fill;
}

/// 铺满的竖屏视频是否应该锚到顶部。
///
/// 抖音的竖屏视频始终从屏幕顶部开始（与状态栏/灵动岛融合），
/// 比例多出来的部分只从底部裁掉；横屏/适应模式仍居中。
bool videoTopAnchored({required double? aspect, required VideoFit fit}) =>
    fit == VideoFit.fill &&
    aspect != null &&
    aspect.isFinite &&
    aspect > 0 &&
    aspect <= portraitAspectThreshold;

/// 首次布局前对任务栏高度的保守估算：内容高 + 底部安全区。
/// 实际高度由播放页测量后覆盖，这里只用于避免首帧跳动。
double taskbarReservedHeight({
  double contentHeight = 78,
  double safeBottom = 0,
}) {
  final b = safeBottom > 0 ? safeBottom : 0.0;
  return (contentHeight > 0 ? contentHeight : 0.0) + b;
}

/// 播放器上报的视频参数，换算成「是否已就绪」与「排版比例」。
///
/// 两个消费方（首帧事件、切预缓冲槽位时的主动同步）必须用同一套解释，
/// 否则会出现「事件路径已经就绪、快照路径还认为没就绪」，海报层一边撤
/// 一边盖。`displayWidth <= 1` 表示视频轨还没有输出尺寸。
///
/// **旋转必须在这里折算**（owner 2026-11-22）：手机拍的 .mov 大量是
/// 1920×1080 编码 + 旋转 90°/270° 元数据；media_kit 的纹理已经按旋转
/// 输出成竖屏（`media_kit_video` 在 90/270 时交换 dw/dh 去设置输出尺寸），
/// 但 `videoParams.dw/dh` 仍是未旋转的编码尺寸。若直接拿 dw/dh 当排版比例，
/// `Video(fit: BoxFit.fill)` 会把 9:16 的画面塞进 16:9 的框 → 整条被拉伸。
typedef VideoParamsInfo = ({double displayWidth, double? aspect});

VideoParamsInfo parseVideoParams(
    {int? dw, int? dh, double? aspect, int? rotate}) {
  final quarterTurn = rotate != null && rotate % 180 != 0;
  final width = quarterTurn
      ? (dh ?? dw ?? 0).toDouble()
      : (dw ?? 0).toDouble();
  double? a;
  if (aspect != null && aspect.isFinite && aspect > 0) {
    a = aspect;
  } else if (dw != null && dh != null && dh > 0) {
    a = dw / dh;
  }
  // 90/270 度：纹理宽高已交换，比例取倒数。
  if (a != null && quarterTurn) a = 1 / a;
  return (displayWidth: width, aspect: a);
}

/// 视频纹理的基准渲染尺寸：固定高度 [referenceHeight]，宽度按源比例换算。
///
/// 之前用 `width.clamp(64, 8192)`：极宽/极窄视频会被夹住宽度，而高度不变，
/// `Video(fit: fill)` 就会把画面拉伸变形。这里只在整张基准图超过
/// [maxSide] 时**等比缩小**，任何比例下都保持宽高比不变。
Size videoBaseSize({
  required double? aspect,
  double referenceHeight = 720,
  double maxSide = 4096,
}) {
  final h0 = referenceHeight.isFinite && referenceHeight > 0
      ? referenceHeight
      : 720.0;
  if (aspect == null || !aspect.isFinite || aspect <= 0) {
    return Size(h0, h0);
  }
  var w = h0 * aspect;
  var h = h0;
  final longest = w > h ? w : h;
  final limit = maxSide.isFinite && maxSide > 64 ? maxSide : 4096.0;
  if (longest > limit) {
    final k = limit / longest;
    w *= k;
    h *= k;
  }
  // 等比缩小后短边会掉到亚像素：`aspect = 1e18` 实测得
  // `Size(4096.0, 4.096e-15)`——框高只有 4e-15 逻辑像素，
  // `Video(fit: fill)` 在这个高度上画出来是空（渲染时高度会被截到 0），
  // 画面整块消失且没有任何报错。比例坏到这种程度不是「一个很宽的片子」，
  // 而是坏数据，与「比例未知」同一条出口：方形基准，至少能画出画面。
  //
  // 阈值取 1 逻辑像素：小于一像素的边在任何 DPR 下都不可能呈现内容。
  if (!w.isFinite || !h.isFinite || w < 1 || h < 1) return Size(h0, h0);
  return Size(w, h);
}

/// T：舞台（PageView 单页）相对屏幕底部的内缩量。
///
/// 正常态 = 任务栏高度（栏已含底部安全区）；全屏沉浸态任务栏隐藏，
/// 舞台铺满屏幕，内缩量固定为 0。异常尺寸按 0 处理，避免负高度。
double stageBottomInset({
  required double screenHeight,
  required double taskbarHeight,
  bool fullscreen = false,
}) {
  if (screenHeight <= 0 || fullscreen) return 0;
  final bar = taskbarHeight > 0 ? taskbarHeight : 0.0;
  return bar.clamp(0.0, screenHeight).toDouble();
}

/// T：舞台内进度层距舞台底边的距离（底部安全区 + 少量内边距）。
///
/// 舞台本身已在上方把任务栏（含安全区）让掉了，正常态调用方传
/// `safeBottom: 0`；全屏沉浸式仍需给 iPhone Home 指示条留位置。
double stageProgressBottomOffset({
  double safeBottom = 0,
  // owner 2026-11-18：进度条就是视频与任务栏的分界线，必须贴住舞台底边（0dp）。
  double padding = 0,
}) {
  final safe = safeBottom > 0 ? safeBottom : 0.0;
  final p = padding > 0 ? padding : 0.0;
  return safe + p;
}

/// T：舞台底部进度层占用的高度（进度行 + 可选的集数标签行）。
/// 供作者/标题信息行避让，避免压住进度条。
double stageProgressOverlayHeight({bool hasChapter = false}) =>
    hasChapter ? 48 : 30;

/// 页内信息区（头像/作者名/标题）底边到舞台底边的距离。
///
/// 关键点：非全屏进度条真正响应拖动的是贴底的一条**可命中条带**
/// （[hitStripHeight]，见 `kScrubHotZoneHeight`），气泡预留区只做绘制。
/// 信息区必须让开这条条带，而不是只让开 2.5dp 的视觉细线——否则头像/
/// 作者名的下半截会落在条带里，点击被进度条热区整块吞掉（无任何指针
/// 事件、也无日志），表现就是「点头像没反应」。
///
/// owner 2026-11-22 两条：
///  1. 非全屏的位置**与有没有进度条无关**——固定按条带高度预留，
///     起播后进度层出现不再把信息区往上顶。
///  2. 非全屏整体再往下挪一点（贴近进度条）：间距用 [compactGap]。
double stageInfoBottom({
  required bool fullscreen,
  required bool hasProgressLayer,
  required bool hasChapter,
  required double progressBottom,
  required double hitStripHeight,
  double gap = 10,
  double compactGap = 8,
}) {
  final base = progressBottom > 0 ? progressBottom : 0.0;
  final g = gap > 0 ? gap : 0.0;
  if (!fullscreen) {
    // 固定预留：与 hasProgressLayer 无关，单图/多图/视频位置一致。
    final hit = hitStripHeight > 0 ? hitStripHeight : 0.0;
    final cg = compactGap > 0 ? compactGap : 0.0;
    return base + hit + cg;
  }
  if (!hasProgressLayer) return base + g;
  return base + stageProgressOverlayHeight(hasChapter: hasChapter) + g;
}

/// 画面失真度：渲染基准框的宽高比相对源比例的偏差（0 = 完全不变形）。
///
/// 这是「拉伸」的唯一量化判据，替代截图目测：
///  `Video(fit: BoxFit.fill)` 会把画面拉满它所在的框，因此只要框的宽高比
///  与源比例不一致，画面就被拉伸了。[videoBaseSize] 按源比例算框，所以正常
///  情况下结果恒为 0；一旦有人把宽度 clamp 回去（0.9.x 曾有这段代码），
///  这个函数会立刻给出非 0 值。
///
/// 返回值是**相对偏差**：0.02 表示偏差 2%（超出即视为拉伸）。
///
/// 框尺寸也必须是**有限**值：`Size(NaN, 100)` 走 `width <= 0` 为 false，
/// 于是 `boxAspect = NaN`、偏差 = NaN。NaN 与阈值的比较恒为 false——
/// 拉伸判据会**静默失效**（真的有拉伸也不再记日志），这比报错更难发现。
/// 与本函数文档里的「框尺寸非法时返回 0」保持一致。
double videoDistortion({required double? sourceAspect, required Size base}) {
  if (sourceAspect == null || !sourceAspect.isFinite || sourceAspect <= 0) {
    return 0;
  }
  if (!base.width.isFinite ||
      !base.height.isFinite ||
      base.width <= 0 ||
      base.height <= 0) {
    return 0;
  }
  final boxAspect = base.width / base.height;
  return ((boxAspect - sourceAspect) / sourceAspect).abs();
}

/// 拉伸判据的日志阈值：偏差超过 2% 才算拉伸（与视频参数重排阈值一致）。
const double kStretchTolerance = 0.02;
