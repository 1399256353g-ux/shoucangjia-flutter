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
  ///
  /// `viewport` 来自 `MediaQuery.sizeOf` / `LayoutBuilder`，窗口被拖到 0 高或
  /// 尚未量出尺寸时可以是 NaN/Infinity。这里的 `math.max(0.0, NaN)` 返回
  /// **NaN**，而 `x.clamp(-NaN, NaN)` 不抛异常、直接返回 NaN——
  /// `Transform.translate` 拿到 NaN 偏移后整张图不画（真机上就是黑屏，
  /// 日志里什么都没有）。非有限尺寸按「没有可平移空间」处理：偏移归零，
  /// 缩放倍率保留。
  PicZoom clamped(Size viewport) {
    final s = _clampScale(scale);
    if (s <= kPicZoomMin + 0.001) return const PicZoom();
    final w = _finiteOrZero(viewport.width);
    final h = _finiteOrZero(viewport.height);
    final maxX = math.max(0.0, w * (s - 1) / 2);
    final maxY = math.max(0.0, h * (s - 1) / 2);
    return PicZoom(
      scale: s,
      offset: Offset(
        _finiteOrZero(offset.dx).clamp(-maxX, maxX),
        _finiteOrZero(offset.dy).clamp(-maxY, maxY),
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
    // 锚点也可能是非有限值（手势在第一帧就上报、坐标为 NaN）：
    // 按播放区中心（0,0）处理，否则 NaN 会经 ratio 传导到 offset。
    final fx = _finiteOrZero(focal.dx);
    final fy = _finiteOrZero(focal.dy);
    final next = Offset(
      fx - (fx - _finiteOrZero(offset.dx)) * ratio,
      fy - (fy - _finiteOrZero(offset.dy)) * ratio,
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

  /// 非有限值 → 0（尺寸/坐标在无约束中间态会给出 NaN/Infinity）。
  static double _finiteOrZero(double v) => v.isFinite ? v : 0.0;
}

/// 双指间距换算缩放倍率：startScale * (currentDistance / startDistance)。
/// 间距过小（双指几乎重合）时保持原倍率，避免抖动放大。
double pinchScale(double startScale, double startDistance, double distance) {
  if (startDistance < 4 || !distance.isFinite) return startScale;
  return (startScale * distance / startDistance)
      .clamp(kPicZoomMin, kPicZoomMax);
}
