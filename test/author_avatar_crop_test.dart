import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/main.dart';

void main() {
  group('J12b 头像裁切几何', () {
    test('zoom 夹紧到 1..4，非法值回落到 1', () {
      expect(avatarCropClampZoom(0.2), 1.0);
      expect(avatarCropClampZoom(2.5), 2.5);
      expect(avatarCropClampZoom(99), 4.0);
      expect(avatarCropClampZoom(double.nan), 1.0);
      expect(avatarCropClampZoom(double.infinity), 1.0);
    });

    test('cover 后按 zoom 放大：横图短边贴合视窗', () {
      final s = avatarCropDisplaySize(const Size(1000, 500), 300, 1);
      expect(s.width, 600);
      expect(s.height, 300);
      final z2 = avatarCropDisplaySize(const Size(1000, 500), 300, 2);
      expect(z2.width, 1200);
      expect(z2.height, 600);
    });

    test('cover 后按 zoom 放大：竖图同理', () {
      final s = avatarCropDisplaySize(const Size(500, 1000), 300, 1);
      expect(s.width, 300);
      expect(s.height, 600);
    });

    test('参数非法时显示尺寸为零', () {
      expect(avatarCropDisplaySize(Size.zero, 300, 1), Size.zero);
      expect(avatarCropDisplaySize(const Size(100, 100), 0, 1), Size.zero);
    });

    test('平移夹紧：不露黑边，不可移动方向恒为 0', () {
      const display = Size(600, 300);
      expect(avatarCropClampOffset(const Offset(999, 999), display, 300),
          const Offset(150, 0));
      expect(avatarCropClampOffset(const Offset(-999, -999), display, 300),
          const Offset(-150, 0));
      expect(avatarCropClampOffset(const Offset(20, -50), display, 300),
          const Offset(20, 0));
    });

    test('归一化平移与还原互为逆运算', () {
      const display = Size(600, 300);
      final n = avatarCropNormalizedOffset(const Offset(150, 0), display, 300);
      expect(n, const Offset(1, 0));
      final back = avatarCropOffsetFromNormalized(n, display, 300);
      expect(back.dx, closeTo(150, 1e-9));
      expect(back.dy, 0);
      final half =
          avatarCropOffsetFromNormalized(const Offset(0.5, 0), display, 300);
      expect(half.dx, closeTo(75, 1e-9));
    });

    test('归一化输入超界先夹紧', () {
      const display = Size(600, 300);
      final o =
          avatarCropOffsetFromNormalized(const Offset(5, -5), display, 300);
      expect(o, const Offset(150, 0));
    });

    test('渲染像素比保证短边 ≥512，且不无限放大', () {
      expect(avatarCropPixelRatio(320), closeTo(1.6, 1e-9));
      expect(avatarCropPixelRatio(100), closeTo(5.12, 1e-9));
      expect(avatarCropPixelRatio(50), 6.0);
      expect(avatarCropPixelRatio(2000), 1.0);
      expect(avatarCropPixelRatio(0), 1.0);
    });
  });

  group('J13 简介校验', () {
    test('按 Unicode 码点计数（中文/emoji 各算 1）', () {
      expect(authorBioLength('中文abc'), 5);
      expect(authorBioLength('😀'), 1);
      expect(authorBioLength(''), 0);
    });

    test('去掉 CR 与首尾空白，空串合法（表示清空）', () {
      expect(normalizeAuthorBio('  a\r\nb  '), 'a\nb');
      expect(validateAuthorBio(''), isNull);
      expect(validateAuthorBio('   '), isNull);
    });

    test('0–500 字合法，501 字拒绝', () {
      expect(validateAuthorBio('a' * 500), isNull);
      final err = validateAuthorBio('a' * 501);
      expect(err, isNotNull);
      expect(err, contains('500'));
    });

    test('bioAt 时间格式化：0 为空串，正常值带日期时间', () {
      expect(formatAuthorBioAt(0), '');
      expect(formatAuthorBioAt(-1), '');
      final ts = DateTime(2026, 11, 17, 22, 2).millisecondsSinceEpoch ~/ 1000;
      expect(formatAuthorBioAt(ts), '2026-11-17 22:02');
    });
  });
}
