// 第四十批契约：把「输入不可能是真的」挡在渲染之前（4 处同类缺口）。
//
// 主类是同一件事：判断器用「数值大小」当守卫，而真正的坏输入是
// **非有限值 / 越界值**，`<= 0` 与 `clamp` 都拦不住或会帮倒忙。
//
//   1. `willOverflowText`：`TextPainter.layout(maxWidth:)` 对负数与 NaN
//      **断言失败**，而调用方算的是 `c.maxWidth - 22`（窄容器直接为负）；
//   2. 头像裁剪：`avatarCropDisplaySize` 只判 `<= 0`，NaN 视窗算出
//      `Size(NaN, NaN)`，`max(0.0, NaN)` 又是 NaN → 偏移 NaN → 图不画；
//   3. 时长文案：`1e18` / int 上限被算成 `277777777777777:46:40`；
//   4. 命中率：服务端给 0–1 之外的值（`62` / `-0.5`）显示成 `6200.0%`。
//
// 还有一条结构约束：进度比例的换算（`scrubFractionOf`）只能有一份实现，
// 拖动与桌面端点按必须走同一个出口，否则两处口径会分叉。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:shoucangjia/cover_badges.dart';
import 'package:shoucangjia/main.dart'
    show avatarCropClampOffset, avatarCropDisplaySize;
import 'package:shoucangjia/player_controls.dart';
import 'package:shoucangjia/resize_cache_api.dart';
import 'package:shoucangjia/sync_ledger.dart';
import 'package:shoucangjia/text_fit.dart';

void main() {
  const style = TextStyle(fontSize: 12);

  group('文本溢出判定的可用宽度必须有限', () {
    testWidgets('负数宽度不再断言失败（窄容器真实形态）', (tester) async {
      // 旧实现把负数直接交给 TextPainter.layout -> _AssertionError。
      expect(willOverflowText('作品标题', style, -22), isFalse);
    });

    testWidgets('NaN 宽度不再断言失败', (tester) async {
      expect(willOverflowText('作品标题', style, double.nan), isFalse);
    });

    testWidgets('无限宽度按「放得下」处理', (tester) async {
      expect(willOverflowText('作品标题', style, double.infinity), isFalse);
    });

    testWidgets('正常宽度仍按真实测量判定（判据没有被改松）', (tester) async {
      expect(willOverflowText('这是一个非常非常长的作品标题', style, 60), isTrue);
      expect(willOverflowText('这是一个非常非常长的作品标题', style, 800), isFalse);
    });
  });

  group('头像裁剪：非有限视窗不产生 NaN 几何', () {
    test('视窗 NaN / Infinity 一律退化为 Size.zero', () {
      expect(avatarCropDisplaySize(const Size(1000, 500), double.nan, 1),
          Size.zero);
      expect(avatarCropDisplaySize(const Size(1000, 500), double.infinity, 1),
          Size.zero);
    });

    test('图片尺寸非有限同样退化', () {
      expect(
          avatarCropDisplaySize(
              const Size(double.nan, 500), 300, 1),
          Size.zero);
    });

    test('偏移夹紧遇到非有限显示尺寸返回零偏移（不是 NaN）', () {
      final o = avatarCropClampOffset(
          const Offset(10, 10), const Size(double.nan, 100), 300);
      expect(o.dx.isNaN, isFalse);
      expect(o.dy.isNaN, isFalse);
      expect(o, Offset.zero);
    });

    test('正常输入行为不变', () {
      final s = avatarCropDisplaySize(const Size(1000, 500), 300, 1);
      expect(s.width, 600);
      expect(s.height, 300);
    });
  });

  group('时长文案：不可信的量级不显示', () {
    test('封面角标超过 100 小时按「无时长」处理', () {
      expect(formatBadgeDuration(1e18), '');
      expect(formatBadgeDuration(9223372036854775807), '');
      expect(formatBadgeDuration(kBadgeMaxSeconds.toDouble()), '100:00:00');
      expect(formatBadgeDuration(kBadgeMaxSeconds + 1), '');
    });

    test('同步耗时超过 48 小时按「未知」处理', () {
      expect(syncDurationLabel(9223372036854775807), '—');
      expect(syncDurationLabel(1e18.toInt()), '—');
      expect(syncDurationLabel(kSyncMaxDurationMs), '2880m 00s');
      expect(syncDurationLabel(kSyncMaxDurationMs + 1), '—');
    });

    test('正常区间不受影响（含既有边界）', () {
      expect(formatBadgeDuration(3725), '1:02:05');
      expect(syncDurationLabel(820), '820ms');
      expect(syncDurationLabel(119600), '2m 00s');
    });
  });

  group('命中率只接受 0–1', () {
    test('越界值退回按计数自算，不显示 6200% / -50%', () {
      final pct = ResizeCacheStats.fromJson(
          {'hit': 3, 'miss': 1, 'hitRate': 62})!;
      expect(pct.hitRate, closeTo(0.75, 1e-9));
      expect(pct.hitRateText, '75.0%');

      final neg =
          ResizeCacheStats.fromJson({'hit': 1, 'miss': 1, 'hitRate': -0.5})!;
      expect(neg.hitRate, closeTo(0.5, 1e-9));
      expect(neg.hitRateText, '50.0%');
    });

    test('区间内的服务端值仍然优先', () {
      expect(
          ResizeCacheStats.fromJson({'hit': 1, 'miss': 9, 'hitRate': 0.62})!
              .hitRate,
          closeTo(0.62, 1e-9));
      expect(
          ResizeCacheStats.fromJson({'hit': 1, 'miss': 9, 'hitRate': 1.0})!
              .hitRate,
          closeTo(1.0, 1e-9));
      expect(
          ResizeCacheStats.fromJson({'hit': 1, 'miss': 9, 'hitRate': 0.0})!
              .hitRate,
          closeTo(0.0, 1e-9));
    });

    test('坏值（非数值/非有限）仍走自算，行为不变', () {
      expect(
          ResizeCacheStats.fromJson({'hit': 1, 'miss': 1, 'hitRate': 'x'})!
              .hitRate,
          closeTo(0.5, 1e-9));
      expect(
          ResizeCacheStats.fromJson(
                  {'hit': 1, 'miss': 1, 'hitRate': double.infinity})!
              .hitRate,
          closeTo(0.5, 1e-9));
    });
  });

  group('进度比例换算单一出口', () {
    test('正常比例按指针位置换算并夹紧', () {
      expect(scrubFractionOf(0, 100), 0.0);
      expect(scrubFractionOf(50, 100), 0.5);
      expect(scrubFractionOf(120, 100), 1.0);
      expect(scrubFractionOf(-10, 100), 0.0);
    });

    test('宽度不可用时返回 null（不是 0，也不是 1）', () {
      // NaN.clamp(0,1) 实测返回 1.0：旧写法会把「宽度未知」当成拖到片尾。
      expect(double.nan.clamp(0.0, 1.0), 1.0, reason: 'clamp 对 NaN 走上界');
      expect(scrubFractionOf(50, double.nan), isNull);
      expect(scrubFractionOf(50, double.infinity), isNull);
      expect(scrubFractionOf(50, 0), isNull);
      expect(scrubFractionOf(50, -100), isNull);
    });

    test('坐标非有限时返回 null', () {
      expect(scrubFractionOf(double.nan, 100), isNull);
      expect(scrubFractionOf(double.infinity, 100), isNull);
    });
  });

  group('契约扫描：不得再出现第二套实现', () {
    List<File> libFiles() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('lib/ 内没有第二处 `dx / width` 直接 clamp 成比例', () {
      // 允许的只有唯一实现本身；其余位置一律转调 scrubFractionOf。
      final offenders = <String>[];
      for (final f in libFiles()) {
        if (f.path.endsWith('player_controls.dart')) continue;
        final src = f.readAsStringSync();
        if (RegExp(r'dx\s*/\s*\w+\)\s*\.clamp\(0').hasMatch(src)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty, reason: '这些文件仍在自己换算进度：$offenders');
    });

    test('text_fit 的宽度守卫包含 isFinite（只判 <=0 会被 NaN 穿透）', () {
      final src = File('lib/text_fit.dart').readAsStringSync();
      expect(src.contains('maxWidth.isFinite'), isTrue);
    });

    test('时长上限常量只有一处定义', () {
      var badge = 0, sync = 0;
      for (final f in libFiles()) {
        final src = f.readAsStringSync();
        badge += RegExp(r'const int kBadgeMaxSeconds').allMatches(src).length;
        sync += RegExp(r'const int kSyncMaxDurationMs').allMatches(src).length;
      }
      expect(badge, 1);
      expect(sync, 1);
    });
  });
}
