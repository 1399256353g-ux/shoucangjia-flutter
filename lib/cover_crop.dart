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

/// 截取框的四个角（缩放时以对角为锚点）。
enum CropCorner { topLeft, topRight, bottomLeft, bottomRight }

/// 固定宽高比的截取框。
class CoverCropBox {
  final Rect rect;
  final double aspect;

  const CoverCropBox(this.rect, this.aspect);

  /// 初始框：居中、占图片约 80%，保持 `aspect`。
  static CoverCropBox initial(Size image, double aspect) {
    if (image.width <= 0 || image.height <= 0 || aspect <= 0) {
      return CoverCropBox(Rect.zero, aspect <= 0 ? 1.0 : aspect);
    }
    var w = image.width * 0.8;
    var h = w / aspect;
    if (h > image.height * 0.8) {
      h = image.height * 0.8;
      w = h * aspect;
    }
    return CoverCropBox(
      Rect.fromLTWH((image.width - w) / 2, (image.height - h) / 2, w, h),
      aspect,
    );
  }

  /// 拖动整框：始终留在图片内。
  CoverCropBox moved(Offset delta, Size image) {
    final dx = (rect.left + delta.dx)
        .clamp(0.0, math.max(0.0, image.width - rect.width))
        .toDouble();
    final dy = (rect.top + delta.dy)
        .clamp(0.0, math.max(0.0, image.height - rect.height))
        .toDouble();
    return CoverCropBox(Rect.fromLTWH(dx, dy, rect.width, rect.height), aspect);
  }

  /// 拖动某个角缩放：对角固定，保持宽高比与图片边界。
  CoverCropBox resized(CropCorner corner, Offset delta, Size image) {
    if (aspect <= 0) return this;
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

    final wFromX = east ? rect.width + delta.dx : rect.width - delta.dx;
    final hDelta = south ? delta.dy : -delta.dy;
    final wFromY = (rect.height + hDelta) * aspect;
    var w = delta.dy.abs() > delta.dx.abs() ? wFromY : wFromX;

    final lower = math.min(kCoverCropMinEdge, upper);
    w = w.clamp(lower, upper);
    final h = w / aspect;
    final left = east ? ax : ax - w;
    final top = south ? ay : ay - h;
    return CoverCropBox(Rect.fromLTWH(left, top, w, h), aspect);
  }

  /// 归一化为 `[x, y, w, h]`（0..1）；已是整帧/非法时返回 null。
  List<double>? normalized(Size image) {
    if (image.width <= 0 || image.height <= 0) return null;
    return coverCropRect(<double>[
      rect.left / image.width,
      rect.top / image.height,
      rect.width / image.width,
      rect.height / image.height,
    ]);
  }
}
