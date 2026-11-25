// 第四十四批契约（0.9.261）：
//
// 本轮四项都是「非有限/不可用输入被当成正常值」的同一族缺口，但落点各不相同，
// 而且**都不报错**——这正是要钉住的原因：它们不会抛异常，只会让画面消失、
// 尺寸错、缩放乱跳，日志里一个字都没有。
//
//  1. `withImageWidth` 的「已有 w=」判定只认 `^w=\d+$`：`?w=` / `w=0` / `w=-5`
//     会被判成「没有宽度」而再追加一个，`?W=100`（大写键）也会变成两个宽度。
//     服务端按第一个参数取值 → 缩图请求实际拿不到宽度，卡片又去拉原图。
//  2. `cover_crop` 的尺寸守卫只判 `<= 0`，而 `NaN <= 0` / `infinity <= 0` 为
//     false：首帧前的 `Size(NaN, NaN)` 一路算出 `Rect.fromLTRB(NaN, …)`，
//     `Positioned.fromRect` 拿到 NaN 直接不画（裁封面页黑屏，无日志）。
//  3. `videoBaseSize` 等比缩小后短边会掉到亚像素（`aspect: 1e18` 实测
//     `Size(4096, 4.096e-15)`）：视频层高度被截成 0，画面整块消失，
//     而拉伸判据（比例仍精确）显示 0.00%，验收完全看不到问题。
//  4. `pinchScale` 只挡了 `distance`：`startScale` / `startDistance` 是 NaN 时
//     `(NaN·d/s).clamp(1,4)` 实测返回 **4.0**（clamp 把 NaN 当上界）——
//     「缩放状态未知」被当成「用户捏到最大」，图片瞬间放大四倍。
//     `dampedDragOffset` 同族：NaN 偏移写进滚动物理后整页不再响应滑动，
//     而 `NaN.clamp(0,1)` = 1.0 还会悄悄关掉越界阻尼。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_crop.dart';
import 'package:shoucangjia/media_resize.dart';
import 'package:shoucangjia/pic_zoom.dart';
import 'package:shoucangjia/swipe_physics.dart';
import 'package:shoucangjia/video_layout.dart';

void main() {
  group('图片地址的 w= 判定：同名键只允许一个，且必须是可用宽度', () {
    test('空值/0/负值被替换，不再追加第二个 w=', () {
      expect(withImageWidth('/a.jpg?w=', 480), '/a.jpg?w=480');
      expect(withImageWidth('/a.jpg?w=0', 480), '/a.jpg?w=480');
      expect(withImageWidth('/a.jpg?w=-5', 480), '/a.jpg?w=480');
      // 缺 `=` 的同名键（`?w`）同样算「存在但不可用」。
      expect(withImageWidth('/a.jpg?w', 480), '/a.jpg?w=480');
      // 非数字值：坏参数，替换掉而不是并列。
      expect(withImageWidth('/a.jpg?w=abc&v=2', 480), '/a.jpg?w=480&v=2');
    });

    test('键名大小写不敏感：W=100 就是一个宽度', () {
      expect(withImageWidth('/a.jpg?W=100', 480), '/a.jpg?W=100');
      expect(withImageWidth('/a.jpg?W=300&v=1', 480), '/a.jpg?W=300&v=1');
    });

    test('已有可用宽度时原样返回（不重排查询串）', () {
      const url = '/a.jpg?w=300';
      expect(withImageWidth(url, 480), url);
      const url2 = '/a.jpg?v=3&w=300';
      expect(withImageWidth(url2, 440), url2);
    });

    test('正常追加的三种形态一个字都没变', () {
      expect(withImageWidth('/media/a/b.jpg', 480), '/media/a/b.jpg?w=480');
      expect(withImageWidth('/media/a/b.jpg?v=3', 440),
          '/media/a/b.jpg?v=3&w=440');
      expect(withImageWidth('/media/a/b.jpg#frag', 480),
          '/media/a/b.jpg?w=480#frag');
      expect(withImageWidth('/media/a/b.jpg?v=1#f', 480),
          '/media/a/b.jpg?v=1&w=480#f');
    });

    test('结果里同名宽度键严格只有一个', () {
      for (final q in <String>['', '?w=', '?w=0', '?w=-1', '?w=abc',
        '?x=1&w=', '?w=&w=9', '?W=7&w=']) {
        final out = withImageWidth('/a.jpg$q', 480);
        final query = out.split('?').length > 1
            ? out.split('?')[1].split('#').first
            : '';
        final keys = query
            .split('&')
            .map((e) => e.split('=').first.toLowerCase())
            .where((e) => e == 'w')
            .length;
        expect(keys, lessThanOrEqualTo(1), reason: '$q -> $out');
      }
    });
  });

  group('封面截取框：NaN / Infinity 尺寸不产出 NaN 矩形', () {
    test('containDisplayRect 对非有限尺寸返回空矩形', () {
      expect(containDisplayRect(Size(double.nan, 100), const Size(300, 300)),
          Rect.zero);
      expect(containDisplayRect(const Size(100, 100), Size(double.nan, 300)),
          Rect.zero);
      expect(containDisplayRect(const Size(100, 100),
          const Size(double.infinity, 300)), Rect.zero);
    });

    test('initial 遇到 NaN 尺寸退化为空框，比例回落到 1', () {
      final b = CoverCropBox.initial(const Size(double.nan, 100), 1.0);
      expect(b.rect, Rect.zero);
      expect(b.aspect, 1.0);
      // 比例自身非法时同样不把 NaN 带进几何。
      final c = CoverCropBox.initial(const Size(100, 100), double.nan);
      expect(c.aspect, 1.0);
      expect(c.rect.left.isFinite, isTrue);
      expect(c.rect.width, greaterThan(0));
    });

    test('moved / resized 收到 NaN 增量时保持原位', () {
      final b = CoverCropBox.initial(const Size(300, 300), 1.0);
      final nan = b.moved(const Offset(double.nan, 0), const Size(300, 300));
      expect(nan.rect, b.rect);
      final nan2 = b.resized(
          CropCorner.bottomRight, const Offset(double.nan, 0),
          const Size(300, 300));
      expect(nan2.rect, b.rect);
      // 图片尺寸不可用（首帧前）同样不动：夹取的边界会是 NaN。
      final nan3 = b.moved(const Offset(10, 10), const Size(double.nan, 300));
      expect(nan3.rect, b.rect);
    });

    test('normalized 对非有限矩形返回 null（整帧），不返回 NaN 数组', () {
      final bad = CoverCropBox(
          const Rect.fromLTWH(double.nan, 0, 10, 10), 1.0);
      expect(bad.normalized(const Size(300, 300)), isNull);
      final ok = CoverCropBox.initial(const Size(300, 300), 1.0);
      final norm = ok.normalized(const Size(300, 300));
      expect(norm, isNotNull);
      expect(norm!.every((v) => v.isFinite), isTrue);
    });
  });

  group('视频基准框：退化成亚像素时回落到方形，而不是画出空帧', () {
    test('极端比例不再给出高度≈0 的框', () {
      for (final a in <double>[1e6, 1e18, 1e300]) {
        final s = videoBaseSize(aspect: a);
        expect(s.height, greaterThanOrEqualTo(1.0), reason: 'aspect=$a');
        expect(s.width, greaterThanOrEqualTo(1.0), reason: 'aspect=$a');
      }
      // 极窄同理（宽度会先掉到亚像素）。
      for (final a in <double>[1e-6, 1e-18]) {
        final s = videoBaseSize(aspect: a);
        expect(s.width, greaterThanOrEqualTo(1.0), reason: 'aspect=$a');
        expect(s.height, greaterThanOrEqualTo(1.0), reason: 'aspect=$a');
      }
    });

    test('可信范围内的比例一个像素都没变', () {
      final p = videoBaseSize(aspect: 9 / 16);
      expect(p.height, closeTo(720, 1e-9));
      expect(p.width / p.height, closeTo(9 / 16, 1e-9));
      final w = videoBaseSize(aspect: 16 / 9);
      expect(w.width, closeTo(1280, 1e-9));
      expect(w.height, closeTo(720, 1e-9));
      // 4:1 这类极端但仍真实的片子保持原比例（阈值 1 像素不会误伤）。
      final r = videoBaseSize(aspect: 4.0);
      expect(r.width / r.height, closeTo(4.0, 1e-9));
    });
  });

  group('手势缩放 / 越界阻尼：非有限输入不得跳到极值', () {
    test('pinchScale 的 NaN/Infinity 参数保持原倍率', () {
      expect(pinchScale(double.nan, 100, 200), 1.0);
      expect(pinchScale(2.0, double.nan, 200), 2.0);
      expect(pinchScale(2.0, 0, 200), 2.0);
      expect(pinchScale(double.infinity, 100, 200), kPicZoomMin);
      expect(pinchScale(-1.0, 100, 200), kPicZoomMin);
    });

    test('pinchScale 正常路径不变', () {
      expect(pinchScale(1, 100, 150), closeTo(1.5, 1e-9));
      expect(pinchScale(2, 100, 150), closeTo(3, 1e-9));
      expect(pinchScale(1, 100, 1000), kPicZoomMax);
      expect(pinchScale(1, 100, 20), 1);
    });

    test('dampedDragOffset 的 NaN 偏移归零、非法系数视为无阻尼', () {
      expect(dampedDragOffset(double.nan, outOfRange: true), 0);
      expect(dampedDragOffset(double.infinity, outOfRange: true), 0);
      expect(dampedDragOffset(10, outOfRange: true,
          overscrollFactor: double.nan), 10);
      // 未越界时不参与阻尼计算，原样返回。
      expect(dampedDragOffset(double.nan, outOfRange: false).isNaN, isTrue);
    });

    test('dampedDragOffset 正常路径不变', () {
      expect(dampedDragOffset(100, outOfRange: true), closeTo(28, 1e-6));
      expect(dampedDragOffset(-100, outOfRange: true), closeTo(-28, 1e-6));
      expect(dampedDragOffset(12, outOfRange: false), 12);
    });
  });
}
