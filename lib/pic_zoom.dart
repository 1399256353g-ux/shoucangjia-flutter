import 'dart:math' as math;
import 'dart:ui';

/// G14：图文图片双指缩放的纯逻辑。
///
/// 坐标约定：图片以 `BoxFit.contain` 铺满播放区，缩放/平移作用在整块播放区上，
/// 以播放区中心为原点（`Transform(alignment: center)`）。因此偏移量是
/// 相对中心的平移；缩放后最多只能平移到图片边缘，不会露出黑边。
const double kPicZoomMin = 1.0;
const double kPicZoomMax = 4.0;

/// 当前缩放状态：scale 为倍率，offset 为相对播放区中心的平移。
class PicZoom {
  final double scale;
  final Offset offset;

  const PicZoom({this.scale = kPicZoomMin, this.offset = Offset.zero});

  static const PicZoom initial = PicZoom();

  bool get isZoomed => scale > kPicZoomMin + 0.001;

  @override
  bool operator ==(Object other) =>
      other is PicZoom &&
      (other.scale - scale).abs() < 1e-9 &&
      (other.offset.dx - offset.dx).abs() < 1e-9 &&
      (other.offset.dy - offset.dy).abs() < 1e-9;

  @override
  int get hashCode => Object.hash(scale, offset);

  @override
  String toString() => 'PicZoom(scale: $scale, offset: $offset)';

  /// 把平移量夹紧到「缩放后的播放区仍覆盖播放区」的范围。
  PicZoom clamped(Size viewport) {
    final s = _clampScale(scale);
    if (s <= kPicZoomMin + 0.001) return const PicZoom();
    final maxX = math.max(0.0, viewport.width * (s - 1) / 2);
    final maxY = math.max(0.0, viewport.height * (s - 1) / 2);
    return PicZoom(
      scale: s,
      offset: Offset(
        offset.dx.clamp(-maxX, maxX),
        offset.dy.clamp(-maxY, maxY),
      ),
    );
  }

  /// 以 [focal]（相对播放区中心的坐标）为锚点缩放到 [target] 倍。
  /// 锚点下的画面保持不动，符合双指捏合直觉。
  PicZoom scaleTo(double target, Offset focal, Size viewport) {
    final s1 = _clampScale(target);
    if (s1 <= kPicZoomMin + 0.001) return const PicZoom();
    if (scale <= 1e-6) {
      return PicZoom(scale: s1, offset: Offset.zero).clamped(viewport);
    }
    final ratio = s1 / scale;
    final next = Offset(
      focal.dx - (focal.dx - offset.dx) * ratio,
      focal.dy - (focal.dy - offset.dy) * ratio,
    );
    return PicZoom(scale: s1, offset: next).clamped(viewport);
  }

  /// 单指平移（放大后拖动图片），偏移量会被夹紧。
  PicZoom panBy(Offset delta, Size viewport) =>
      PicZoom(scale: scale, offset: offset + delta).clamped(viewport);

  PicZoom reset() => const PicZoom();

  static double _clampScale(double v) {
    if (v.isNaN) return kPicZoomMin;
    return v.clamp(kPicZoomMin, kPicZoomMax);
  }
}

/// 双指间距换算缩放倍率：startScale * (currentDistance / startDistance)。
/// 间距过小（双指几乎重合）时保持原倍率，避免抖动放大。
double pinchScale(double startScale, double startDistance, double distance) {
  if (startDistance < 4 || !distance.isFinite) return startScale;
  return (startScale * distance / startDistance)
      .clamp(kPicZoomMin, kPicZoomMax);
}
