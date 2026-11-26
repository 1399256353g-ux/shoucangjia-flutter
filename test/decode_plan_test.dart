import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/decode_plan.dart';
import 'package:shoucangjia/grid_spec.dart';

void main() {
  group('decodeWidthForDisplay', () {
    test('显示尺寸 × 像素比，向上取整', () {
      expect(decodeWidthForDisplay(58, 3), 174);
      expect(decodeWidthForDisplay(220, 2), 440);
      expect(decodeWidthForDisplay(96.5, 2), 193);
    });

    test('像素比非法按 1.0，尺寸非法返回 0', () {
      expect(decodeWidthForDisplay(58, 0), 58);
      expect(decodeWidthForDisplay(58, -1), 58);
      expect(decodeWidthForDisplay(0, 3), 0);
      expect(decodeWidthForDisplay(-10, 3), 0);
    });

    test('maxWidth 生效，且至少 1 像素', () {
      expect(decodeWidthForDisplay(400, 3, maxWidth: 660), 660);
      expect(decodeWidthForDisplay(400, 3, maxWidth: 0), 1200);
      expect(decodeWidthForDisplay(0.1, 1), 1);
    });
  });

  group('统一解码宽度', () {
    test('作品卡：220 × DPR，上限 660（1x/2x/3x 都稳定）', () {
      expect(kWorkCardDisplayWidth, 220);
      expect(workCardDecodeWidth(1), 220);
      expect(workCardDecodeWidth(2), 440);
      expect(workCardDecodeWidth(3), 660);
      expect(workCardDecodeWidth(4), kWorkCardMaxDecodeWidth);
    });

    test('库卡片：显示宽度来自网格规格，公式只有一处', () {
      // 0.9.288：`kLibCardDisplayWidth` / `libCardDecodeWidth()` 已删除——
      // 「显示宽度」与「网格列宽」是同一个数字，不再各立一个名字。
      expect(kUnitLibGrid.displayWidth, 260);
      expect(kBasicLibGrid.displayWidth, 220);
      expect(kUnitLibGrid.decodeWidth(2), 520);
      expect(kBasicLibGrid.decodeWidth(2), 440);
      expect(kBasicLibGrid.decodeWidth(1), 220);
      expect(kBasicLibGrid.decodeWidth(0), 220);
    });
  });

  group('DecodeBudget', () {
    test('默认 4 / 滚动 2，滚动时取较小值', () {
      final b = DecodeBudget();
      expect(b.limit, 4);
      expect(b.scrollLimit, 2);
      expect(b.effectiveLimit, 4);
      b.setScrolling(true);
      expect(b.scrolling, isTrue);
      expect(b.effectiveLimit, 2);
      b.setScrolling(false);
      expect(b.effectiveLimit, 4);
    });

    test('并发不超过上限，超出的排队', () async {
      final b = DecodeBudget(limit: 2, scrollLimit: 1);
      var active = 0;
      var peak = 0;
      final gates = <Completer<void>>[];

      final futures = <Future<void>>[];
      for (var i = 0; i < 5; i++) {
        futures.add(b.run(() async {
          active++;
          if (active > peak) peak = active;
          final g = Completer<void>();
          gates.add(g);
          await g.future;
          active--;
        }));
      }

      await Future<void>.delayed(Duration.zero);
      expect(active, 2);
      expect(b.active, 2);
      expect(b.waiting, 3);

      // 逐个放行：始终不超过 2，排队的会补上。
      gates.removeAt(0).complete();
      await Future<void>.delayed(Duration.zero);
      expect(active, 2);

      gates.removeAt(0).complete();
      await Future<void>.delayed(Duration.zero);
      expect(active, 2);

      for (var i = 0; i < 50 && (b.active > 0 || b.waiting > 0); i++) {
        if (gates.isNotEmpty) gates.removeAt(0).complete();
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(futures);
      expect(active, 0);
      expect(b.active, 0);
      expect(b.waiting, 0);
      expect(peak, 2);
    });

    test('滚动收紧后不再放新任务，排队的不超过滚动上限', () async {
      final b = DecodeBudget(limit: 4, scrollLimit: 1);
      var active = 0;
      final gates = <Completer<void>>[];
      final futures = <Future<void>>[];
      for (var i = 0; i < 6; i++) {
        futures.add(b.run(() async {
          active++;
          final g = Completer<void>();
          gates.add(g);
          await g.future;
          active--;
        }));
      }
      await Future<void>.delayed(Duration.zero);
      expect(active, 4);
      expect(b.waiting, 2);

      // 滚动开始：在途 4 个不打断，但释放出来的名额要等全空后才按 1 补。
      b.setScrolling(true);
      expect(active, 4);
      gates.removeAt(0).complete();
      await Future<void>.delayed(Duration.zero);
      expect(active, 3, reason: '滚动上限 1：还有 3 个在途时不再补位');
      expect(b.waiting, 2);

      for (var i = 0; i < 50 && (b.active > 0 || b.waiting > 0); i++) {
        if (gates.isNotEmpty) gates.removeAt(0).complete();
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(futures);
      expect(active, 0);
    });

    test('上限可调，非法值钳到 1；重复 setScrolling 不抖动', () {
      final b = DecodeBudget(limit: 0, scrollLimit: -3);
      expect(b.limit, 1);
      expect(b.scrollLimit, 1);
      b.limit = 3;
      b.scrollLimit = 2;
      expect(b.effectiveLimit, 3);
      b.setScrolling(true);
      b.setScrolling(true);
      expect(b.effectiveLimit, 2);
    });

    test('任务抛异常也释放名额', () async {
      final b = DecodeBudget(limit: 1, scrollLimit: 1);
      await expectLater(
        b.run<void>(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(b.active, 0);
      expect(await b.run(() async => 7), 7);
    });
  });
}
