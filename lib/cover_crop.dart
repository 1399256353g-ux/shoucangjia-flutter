/// 封面截取框的纯几何逻辑（无 Flutter 组件，便于单测）。
///
/// 坐标约定：`rect` 是**图片显示区**的局部像素坐标（左上原点），
/// 由调用方按 `BoxFit.contain` 算好显示尺寸后传入；归一化到 0..1 后
/// 交给 [coverCropRect] 做协议层的越界夹取（服务端还会各自再夹一次）。
library;

import 'dart:math' as math;
import 'dart:ui';

import 'cover_admin.dart';

/// 库卡片封面的宽高比，与 `unit_library_view.dart` 网格
/// `childAspectRatio: 1.02` 共用同一口径（卡片封面是 `BoxFit.cover` 铺满）。
const double kLibraryCoverAspect = 1.02;

/// 截取框的最小边（显示像素）。太小说明用户没真正框选，按整帧处理。
const double kCoverCropMinEdge = 44;

/// `BoxFit.contain` 的显示矩形：源图 [src] 在可用区域 [area] 内等比缩放并居中。
///
/// 截取页必须用这个矩形作为「图片坐标系」——选框是它的局部坐标，
/// 归一化后再乘回图片像素尺寸，才能保证「选框构图 = 入库卡片构图」。
/// 抽成纯函数是为了让这条链路可单测（页面布局与协议换算共用同一口径）。
Rect containDisplayRect(Size src, Size area) {
  if (!_usable(src.width) || !_usable(src.height)) return Rect.zero;
  if (!_usable(area.width) || !_usable(area.height)) return Rect.zero;
  final scale =
      math.min(area.width / src.width, area.height / src.height);
  if (scale <= 0 || !scale.isFinite) return Rect.zero;
  final w = src.width * scale;
  final h = src.height * scale;
  return Rect.fromLTWH((area.width - w) / 2, (area.height - h) / 2, w, h);
}

/// 尺寸是否可用于几何计算：必须是**有限**正数。
///
/// 旧守卫只判 `<= 0`，而 `NaN <= 0` 与 `infinity <= 0` 都是 **false**——
/// 一个还没解码完的图片（`ImageStream` 首帧前的 `Size(NaN, NaN)`）或
/// 零约束的 `LayoutBuilder` 会直接穿过去，算出 `Rect.fromLTRB(NaN, NaN, NaN, NaN)`
/// 交给 `Positioned.fromRect`，整块画面不画（真机上就是黑屏，日志里什么都没有）。
bool _usable(double v) => v.isFinite && v > 0;

/// 截取框的四个角（缩放时以对角为锚点）。
enum CropCorner { topLeft, topRight, bottomLeft, bottomRight }

/// 固定宽高比的截取框。
class CoverCropBox {
  final Rect rect;
  final double aspect;

  const CoverCropBox(this.rect, this.aspect);

  /// 初始框：居中、占图片约 80%，保持 `aspect`。
  static CoverCropBox initial(Size image, double aspect) {
    final a = (aspect.isFinite && aspect > 0) ? aspect : 1.0;
    if (!_usable(image.width) || !_usable(image.height)) {
      return CoverCropBox(Rect.zero, a);
    }
    var w = image.width * 0.8;
    var h = w / a;
    if (h > image.height * 0.8) {
      h = image.height * 0.8;
      w = h * a;
    }
    return CoverCropBox(
      Rect.fromLTWH((image.width - w) / 2, (image.height - h) / 2, w, h),
      a,
    );
  }

  /// 拖动整框：始终留在图片内。
  CoverCropBox moved(Offset delta, Size image) {
    // 图片尺寸不可用（NaN/Infinity）时**不动**：任何夹取都会产出 NaN，
    // 而 `Positioned.fromRect` 拿到 NaN 直接不画整块。
    if (!_usable(image.width) || !_usable(image.height)) return this;
    // 拖动增量也要过有限性：多指/合成器在首帧会上报 NaN 位移，
    // `rect.left + NaN` = NaN，`NaN.clamp(...)` 返回上界（不是 NaN）——
    // 于是选框会「跳」到右/下边界，看起来像自己滑走了。
    final ddx = delta.dx.isFinite ? delta.dx : 0.0;
    final ddy = delta.dy.isFinite ? delta.dy : 0.0;
    final dx = (rect.left + ddx)
        .clamp(0.0, math.max(0.0, image.width - rect.width))
        .toDouble();
    final dy = (rect.top + ddy)
        .clamp(0.0, math.max(0.0, image.height - rect.height))
        .toDouble();
    return CoverCropBox(Rect.fromLTWH(dx, dy, rect.width, rect.height), aspect);
  }

  /// 拖动某个角缩放：对角固定，保持宽高比与图片边界。
  CoverCropBox resized(CropCorner corner, Offset delta, Size image) {
    if (!aspect.isFinite || aspect <= 0) return this;
    if (!_usable(image.width) || !_usable(image.height)) return this;
    // 与 [moved] 同一条守卫：NaN 增量会让 `w.clamp(lower, upper)` 直接返回
    // 上界（clamp 对 NaN 走上界），选框一瞬间跳到最大——缩放看着像「失控」。
    final ddx = delta.dx.isFinite ? delta.dx : 0.0;
    final ddy = delta.dy.isFinite ? delta.dy : 0.0;
    final east =
        corner == CropCorner.topRight || corner == CropCorner.bottomRight;
    final south =
        corner == CropCorner.bottomRight || corner == CropCorner.bottomLeft;
    // 锚点 = 对角
    final ax = east ? rect.left : rect.right;
    final ay = south ? rect.top : rect.bottom;
    final maxW = east ? image.width - ax : ax;
    final maxH = south ? image.height - ay : ay;
    final upper = math.max(0.0, math.min(maxW, maxH * aspect));
    if (upper <= 0) return this;

    final wFromX = east ? rect.width + ddx : rect.width - ddx;
    final hDelta = south ? ddy : -ddy;
    final wFromY = (rect.height + hDelta) * aspect;
    var w = ddy.abs() > ddx.abs() ? wFromY : wFromX;

    final lower = math.min(kCoverCropMinEdge, upper);
    w = w.clamp(lower, upper);
    final h = w / aspect;
    final left = east ? ax : ax - w;
    final top = south ? ay : ay - h;
    return CoverCropBox(Rect.fromLTWH(left, top, w, h), aspect);
  }

  /// 归一化为 `[x, y, w, h]`（0..1）；已是整帧/非法时返回 null。
  List<double>? normalized(Size image) {
    if (!_usable(image.width) || !_usable(image.height)) return null;
    // 选框本身也可能是 NaN（历史状态/坏输入）：`x/NaN` = NaN，而
    // `coverCropRect` 会把它判成「整帧」——静默丢掉用户刚框的构图。
    if (!rect.left.isFinite ||
        !rect.top.isFinite ||
        !rect.width.isFinite ||
        !rect.height.isFinite) {
      return null;
    }
    return coverCropRect(<double>[
      rect.left / image.width,
      rect.top / image.height,
      rect.width / image.width,
      rect.height / image.height,
    ]);
  }
}
