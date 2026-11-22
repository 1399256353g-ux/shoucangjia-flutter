import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_crop.dart';

void main() {
  const display = Size(400, 600);

  group('CoverCropBox.initial', () {
    test('保持宽高比、居中、落在图片内', () {
      final b = CoverCropBox.initial(display, kLibraryCoverAspect);
      expect(b.rect.width / b.rect.height, closeTo(kLibraryCoverAspect, 1e-6));
      expect(b.rect.left, greaterThanOrEqualTo(0));
      expect(b.rect.top, greaterThanOrEqualTo(0));
      expect(b.rect.right, lessThanOrEqualTo(display.width + 1e-6));
      expect(b.rect.bottom, lessThanOrEqualTo(display.height + 1e-6));
      expect(b.rect.center.dx, closeTo(display.width / 2, 1e-6));
    });

    test('横图里也能放得下（宽度不超出）', () {
      const wide = Size(1200, 300);
      final b = CoverCropBox.initial(wide, kLibraryCoverAspect);
      expect(b.rect.width, lessThanOrEqualTo(wide.width + 1e-6));
      expect(b.rect.height, lessThanOrEqualTo(wide.height + 1e-6));
    });

    test('非法尺寸不崩', () {
      final b = CoverCropBox.initial(Size.zero, kLibraryCoverAspect);
      expect(b.rect.isEmpty, isTrue);
    });
  });

  group('CoverCropBox.moved', () {
    test('平移后仍在图片内', () {
      final b = CoverCropBox.initial(display, kLibraryCoverAspect);
      final m = b.moved(const Offset(-999, -999), display);
      expect(m.rect.left, closeTo(0, 1e-6));
      expect(m.rect.top, closeTo(0, 1e-6));
      final m2 = m.moved(const Offset(999, 999), display);
      expect(m2.rect.right, closeTo(display.width, 1e-6));
      expect(m2.rect.bottom, closeTo(display.height, 1e-6));
      expect(m2.rect.size, b.rect.size);
    });
  });

  group('CoverCropBox.resized', () {
    test('保持比例且不越界', () {
      final b = CoverCropBox.initial(display, kLibraryCoverAspect);
      for (final c in CropCorner.values) {
        final r = b.resized(c, const Offset(-500, -500), display);
        expect(r.rect.width / r.rect.height,
            closeTo(kLibraryCoverAspect, 1e-6),
            reason: '$c');
        expect(r.rect.left, greaterThanOrEqualTo(-1e-6));
        expect(r.rect.top, greaterThanOrEqualTo(-1e-6));
        expect(r.rect.right, lessThanOrEqualTo(display.width + 1e-6));
        expect(r.rect.bottom, lessThanOrEqualTo(display.height + 1e-6));
      }
    });

    test('放大不超过图片边界', () {
      final b = CoverCropBox.initial(display, kLibraryCoverAspect);
      final r = b.resized(CropCorner.bottomRight,
          const Offset(5000, 5000), display);
      expect(r.rect.width, lessThanOrEqualTo(display.width + 1e-6));
      expect(r.rect.height, lessThanOrEqualTo(display.height + 1e-6));
      expect(r.rect.width / r.rect.height, closeTo(kLibraryCoverAspect, 1e-6));
    });

    test('缩到最小边后不再变小', () {
      final b = CoverCropBox.initial(display, kLibraryCoverAspect);
      final r = b.resized(CropCorner.topLeft,
          const Offset(9999, 9999), display);
      expect(r.rect.width, greaterThanOrEqualTo(
          kCoverCropMinEdge - 1e-6 > r.rect.width ? 0 : kCoverCropMinEdge - 1e-6));
      expect(r.rect.width, greaterThan(0));
    });
  });

  group('CoverCropBox.normalized', () {
    test('归一化 0..1 且与屏幕像素无关', () {
      final b = CoverCropBox(
          const Rect.fromLTWH(100, 150, 200, 200 / kLibraryCoverAspect),
          kLibraryCoverAspect);
      final n = b.normalized(display)!;
      expect(n[0], closeTo(0.25, 1e-6));
      expect(n[1], closeTo(0.25, 1e-6));
      expect(n[2], closeTo(0.5, 1e-6));
      // 同一选框在 2 倍显示尺寸下归一化结果不变
      final b2 = CoverCropBox(
          Rect.fromLTWH(200, 300, 400, 400 / kLibraryCoverAspect),
          kLibraryCoverAspect);
      final n2 = b2.normalized(const Size(800, 1200))!;
      expect(n2[0], closeTo(n[0], 1e-6));
      expect(n2[2], closeTo(n[2], 1e-6));
    });

    test('整帧返回 null（走旧行为）', () {
      final b = CoverCropBox(
          Rect.fromLTWH(0, 0, display.width, display.height),
          display.width / display.height);
      expect(b.normalized(display), isNull);
    });
  });

  group('containDisplayRect', () {
    test('竖图放进横向区域：高度贴合、水平居中、留黑边', () {
      final r = containDisplayRect(const Size(1080, 1920), const Size(1000, 400));
      expect(r.height, closeTo(400, 1e-6));
      expect(r.width, closeTo(1080 * 400 / 1920, 1e-6));
      expect(r.top, closeTo(0, 1e-6));
      expect(r.left, closeTo((1000 - 1080 * 400 / 1920) / 2, 1e-6));
      expect(r.width / r.height, closeTo(1080 / 1920, 1e-6));
    });

    test('横图放进竖向区域：宽度贴合、垂直居中', () {
      final r = containDisplayRect(const Size(1920, 1080), const Size(400, 900));
      expect(r.width, closeTo(400, 1e-6));
      expect(r.height, closeTo(1080 * 400 / 1920, 1e-6));
      expect(r.left, closeTo(0, 1e-6));
      expect(r.top, closeTo((900 - 1080 * 400 / 1920) / 2, 1e-6));
    });

    test('非法尺寸返回空矩形（页面据此走「画面尺寸异常」）', () {
      expect(containDisplayRect(Size.zero, const Size(100, 100)), Rect.zero);
      expect(containDisplayRect(const Size(10, 10), Size.zero), Rect.zero);
    });
  });

  group('构图链：选框 → 归一化 → 图片像素', () {
    // 9:16 竖屏源（视频作品常见）放在 1000×400 的横向可用区里，
    // 两侧各约 387.5 的黑边——选框只在图片显示矩形内活动。
    const image = Size(1080, 1920);
    final shown = containDisplayRect(image, const Size(1000, 400));

    test('选框在显示区内的相对位置 = 图片像素的相对位置', () {
      // 取显示区上半部的一个框（人脸通常在上面）
      final box = CoverCropBox(
        Rect.fromLTWH(shown.width * 0.25, shown.height * 0.10,
            shown.width * 0.5, shown.width * 0.5 / kLibraryCoverAspect),
        kLibraryCoverAspect,
      );
      final n = box.normalized(shown.size)!;
      expect(n[0], closeTo(0.25, 1e-6));
      expect(n[1], closeTo(0.10, 1e-6));
      expect(n[2], closeTo(0.5, 1e-6));
      // 换算回源图像素：框住的就是源图这一块
      final px = Rect.fromLTWH(n[0] * image.width, n[1] * image.height,
          n[2] * image.width, n[3] * image.height);
      expect(px.left, closeTo(image.width * 0.25, 1e-6));
      expect(px.top, closeTo(image.height * 0.10, 1e-6));
      // 入库裁切比例必须还是库卡片比例（不会被卡片再裁一次）
      expect(px.width / px.height, closeTo(kLibraryCoverAspect, 1e-6));
    });

    test('黑边偏移不参与归一化（框贴右边界仍落在图片内）', () {
      final box = CoverCropBox.initial(shown.size, kLibraryCoverAspect)
          .moved(const Offset(9999, 0), shown.size);
      final n = box.normalized(shown.size)!;
      expect(n[0] + n[2], closeTo(1.0, 1e-6));
      final pxRight = (n[0] + n[2]) * image.width;
      expect(pxRight, closeTo(image.width, 1e-6));
    });

    test('不同显示尺寸下，同一构图归一化结果一致', () {
      const wide = Size(1400, 500);
      final shownWide = containDisplayRect(image, wide);
      final a = CoverCropBox.initial(shown.size, kLibraryCoverAspect)
          .normalized(shown.size)!;
      final b = CoverCropBox.initial(shownWide.size, kLibraryCoverAspect)
          .normalized(shownWide.size)!;
      for (var i = 0; i < 4; i++) {
        expect(b[i], closeTo(a[i], 1e-6), reason: '元素 $i');
      }
    });
  });
}
