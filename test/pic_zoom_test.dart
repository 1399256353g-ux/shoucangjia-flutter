import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/pic_zoom.dart';

const viewport = Size(400, 800);

void main() {
  test('初始状态不放大、重置后恢复原状', () {
    const z = PicZoom.initial;
    expect(z.isZoomed, false);
    expect(z.scale, kPicZoomMin);
    expect(z.offset, Offset.zero);
    expect(z.reset(), PicZoom.initial);
  });

  test('缩放倍率被夹紧在 1–4，回到 1 时偏移归零', () {
    expect(PicZoom.initial.scaleTo(0.2, Offset.zero, viewport).scale, 1);
    expect(PicZoom.initial.scaleTo(99, Offset.zero, viewport).scale, kPicZoomMax);
    final z = const PicZoom(scale: 2).reset();
    expect(z.isZoomed, false);
    expect(z.offset, Offset.zero);
  });

  test('以焦点为中心缩放时该点画面保持不动', () {
    const focal = Offset(100, -50);
    final z = PicZoom.initial.scaleTo(2, focal, viewport);
    expect(z.scale, 2);
    // 变换后 (p * s + offset) 仍等于焦点本身
    final mappedX = focal.dx * z.scale + z.offset.dx;
    final mappedY = focal.dy * z.scale + z.offset.dy;
    expect(mappedX, closeTo(focal.dx, 1e-6));
    expect(mappedY, closeTo(focal.dy, 1e-6));
  });

  test('平移不会超出图片边界（不露黑边）', () {
    final z = PicZoom.initial
        .scaleTo(2, Offset.zero, viewport)
        .panBy(const Offset(9999, -9999), viewport);
    expect(z.offset.dx, closeTo(200, 1e-6)); // 400 * (2-1) / 2
    expect(z.offset.dy, closeTo(-400, 1e-6)); // 800 * (2-1) / 2
    final z2 = z.panBy(const Offset(-9999, 9999), viewport);
    expect(z2.offset.dx, closeTo(-200, 1e-6));
    expect(z2.offset.dy, closeTo(400, 1e-6));
  });

  test('未放大时平移无效', () {
    final z = PicZoom.initial.panBy(const Offset(50, 50), viewport);
    expect(z.offset, Offset.zero);
    expect(z.isZoomed, false);
  });

  test('双指间距换算倍率', () {
    expect(pinchScale(1, 100, 150), 1.5);
    expect(pinchScale(2, 100, 150), 3);
    expect(pinchScale(1, 100, 1000), kPicZoomMax);
    expect(pinchScale(1, 100, 20), 1);
    // 双指几乎重合时不放大，避免抖动
    expect(pinchScale(1.5, 1, 100), 1.5);
    expect(pinchScale(1.5, 0, 100), 1.5);
  });

  test('缩小回 1 倍会自动回到未放大状态', () {
    final zoomed = PicZoom.initial.scaleTo(2, const Offset(80, 80), viewport);
    expect(zoomed.isZoomed, true);
    final back = zoomed.scaleTo(1, const Offset(80, 80), viewport);
    expect(back, PicZoom.initial);
  });
}
