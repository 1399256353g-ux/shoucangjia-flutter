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

import 'dart:ui' show Offset, Rect, Size;

/// 视频显示模式。`fill` = 铺满（BoxFit.cover + 裁剪），
/// `contain` = 适应（BoxFit.contain，留黑边）。
enum VideoFit { fill, contain }

/// 竖屏判定阈值：源宽高比（宽/高）小于此值视为竖屏。
const double portraitAspectThreshold = 0.8;

/// 按源比例与用户覆盖设置决定填充模式。
///
/// [mode] 非空时手动覆盖优先；[aspect] 为源的宽/高，竖屏（<0.8）铺满，
/// 横屏/方形留边；宽高比未知时保守地用 contain，避免裁掉画面。
VideoFit videoFitFor({double? aspect, VideoFit? mode}) {
  if (mode != null) return mode;
  // owner 2026-11-18：视频必须顶到进度条（进度条是视频与任务栏的分界线），
  // 默认一律铺满；比例差异造成的裁切由用户在设置里改「适应」。
  return VideoFit.fill;
}

/// 播放视口高度 = 屏幕高 − 底部任务栏高度（含 SafeArea）。
/// 结果夹在 [0, screenHeight] 内，异常尺寸时退化为 0。
double videoViewportHeight({
  required double screenHeight,
  required double taskbarHeight,
}) {
  if (screenHeight <= 0) return 0;
  final bar = taskbarHeight > 0 ? taskbarHeight : 0.0;
  return (screenHeight - bar).clamp(0.0, screenHeight).toDouble();
}

/// 首次布局前对任务栏高度的保守估算：内容高 + 底部安全区。
/// 实际高度由播放页测量后覆盖，这里只用于避免首帧跳动。
double taskbarReservedHeight({
  double contentHeight = 78,
  double safeBottom = 0,
}) {
  final b = safeBottom > 0 ? safeBottom : 0.0;
  return (contentHeight > 0 ? contentHeight : 0.0) + b;
}

/// 按容器尺寸与视频宽高比计算 `BoxFit.contain` 后的画面矩形。
/// [aspect] 非法（<=0）时退回整个容器。
Rect videoContentRect(Size box, double? aspect) {
  if (box.width <= 0 || box.height <= 0) return Rect.zero;
  if (aspect == null || aspect <= 0) {
    return Offset.zero & box;
  }
  final containerAspect = box.width / box.height;
  if (containerAspect > aspect) {
    // 容器更宽：左右留黑边，画面高度撑满。
    final w = box.height * aspect;
    final left = (box.width - w) / 2;
    return Rect.fromLTWH(left, 0, w, box.height);
  }
  // 容器更高（手机竖屏播放宽屏视频）：上下留黑边，画面宽度撑满。
  final h = box.width / aspect;
  final top = (box.height - h) / 2;
  return Rect.fromLTWH(0, top, box.width, h);
}

/// 底栏相对屏幕底部的内缩量：把栏贴在画面下沿。
/// [fullscreen] 为真时始终贴屏幕底；桌面端调用方直接传 0。
double taskbarBottomInset({
  required Size box,
  required double? aspect,
  bool fullscreen = false,
}) {
  if (fullscreen || box.height <= 0) return 0;
  final rect = videoContentRect(box, aspect);
  if (rect.height <= 0) return 0;
  final inset = box.height - rect.bottom;
  if (inset <= 0) return 0;
  // 极端长图/异常宽高比时最多上移 45% 屏高，避免任务栏跑到画面中央。
  return inset.clamp(0.0, box.height * 0.45);
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
