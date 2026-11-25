import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/unit_fraction.dart';
import 'package:shoucangjia/playback_flow.dart';
import 'package:shoucangjia/player_controls.dart';
import 'package:shoucangjia/continue_watching.dart';

/// 「把值夹到 0–1」这件事在 `lib/` 里曾被写了 20 遍，且对非有限值的处理
/// 各不相同，其中一处注释把行为**写反了**。
///
/// 实测（`dart` 直接跑，不是推测）：
///   double.nan.clamp(0.0, 1.0)              -> 1.0
///   double.infinity.clamp(0.0, 1.0)         -> 1.0
///   double.negativeInfinity.clamp(0.0, 1.0) -> 0.0
///
/// 所以「比例未知」用裸 clamp 会被静默当成「进度 100%」：拖到片尾、
/// 面板吸到全屏、底纹拉满。这组用例同时锁住事实与统一后的口径。
void main() {
  group('事实：裸 clamp 对非有限值的行为（不是旧注释说的那样）', () {
    test('NaN.clamp(0,1) 返回 1.0，不是 NaN', () {
      final f = double.nan.clamp(0.0, 1.0);
      expect(f, 1.0);
      expect(f.isFinite, isTrue,
          reason: 'NaN 经 clamp 后是有限值——所以「NaN.floor() 抛异常」的说法不成立');
    });

    test('±Infinity 分别落到上界/下界', () {
      expect(double.infinity.clamp(0.0, 1.0), 1.0);
      expect(double.negativeInfinity.clamp(0.0, 1.0), 0.0);
    });
  });

  group('unitFraction：唯一实现', () {
    test('正常值原样夹紧', () {
      expect(unitFraction(0.0), 0.0);
      expect(unitFraction(0.42), 0.42);
      expect(unitFraction(1.0), 1.0);
      expect(unitFraction(-0.3), 0.0);
      expect(unitFraction(2.5), 1.0);
    });

    test('非有限值默认归 0（「还没开始 / 不可用」）', () {
      expect(unitFraction(double.nan), 0.0);
      expect(unitFraction(double.infinity), 0.0);
      expect(unitFraction(double.negativeInfinity), 0.0);
    });

    test('fallback 可指定，且自己也被夹到 0–1', () {
      expect(unitFraction(double.nan, fallback: 0.6), 0.6);
      expect(unitFraction(double.nan, fallback: 9.9), 1.0);
      expect(unitFraction(double.nan, fallback: -4), 0.0);
    });

    test('fallback 本身非有限时仍回落 0（不把 NaN 传出去）', () {
      expect(unitFraction(double.nan, fallback: double.nan), 0.0);
      expect(unitFraction(double.nan, fallback: double.infinity), 0.0);
    });
  });

  group('调用点接上统一口径', () {
    test('picIndexAtFraction：比例未知落到第 0 页，不再静默跳末页', () {
      // 旧行为（裸 clamp）：NaN → 1.0 → 末页。这就是要修的 bug。
      expect(picIndexAtFraction(double.nan, 4), 0);
      expect(picIndexAtFraction(double.infinity, 4), 0);
      expect(picIndexAtFraction(double.negativeInfinity, 4), 0);
      // 正常值不受影响。
      expect(picIndexAtFraction(0.99, 4), 3);
      expect(picIndexAtFraction(0.0, 4), 0);
    });

    test('scrubFractionOf：宽度未知返回 null（保持「不可用」语义）', () {
      expect(scrubFractionOf(10, 0), isNull);
      expect(scrubFractionOf(10, double.nan), isNull);
      expect(scrubFractionOf(10, double.infinity), isNull);
      expect(scrubFractionOf(double.nan, 100), isNull);
      expect(scrubFractionOf(50, 100), 0.5);
      expect(scrubFractionOf(-20, 100), 0.0);
      expect(scrubFractionOf(200, 100), 1.0);
    });

    test('ContinueItem.fraction：时长未知/为负一律 0', () {
      const zero =
          ContinueItem(lib: 'l', id: 'i', positionMs: 500, durationMs: 0);
      expect(zero.fraction, 0.0);
      const neg =
          ContinueItem(lib: 'l', id: 'i', positionMs: 500, durationMs: -1);
      expect(neg.fraction, 0.0);
      const half =
          ContinueItem(lib: 'l', id: 'i', positionMs: 500, durationMs: 1000);
      expect(half.fraction, 0.5);
      const over =
          ContinueItem(lib: 'l', id: 'i', positionMs: 5000, durationMs: 1000);
      expect(over.fraction, 1.0);
    });

    test('commentPanelSnap：非有限比例按「关闭」，非有限初值回落默认档', () {
      // 比例未知 → 不能当成「已展开到 100%」。
      expect(commentPanelSnap(fraction: double.nan, velocity: 0),
          kCommentPanelClosedFraction);
      // 初值未知 → 用默认档，不是 0。
      final r = commentPanelSnap(
          fraction: double.nan, velocity: 0, initial: double.nan);
      expect(r, kCommentPanelClosedFraction);
    });
  });

  group('契约：0–1 比例的夹紧只剩一个实现', () {
    test('lib/ 里不得再出现裸 .clamp(0.0, 1.0)', () {
      // 唯一允许的实现文件是 unit_fraction.dart 自己。
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('unit_fraction.dart')) continue;
        final src = f.readAsStringSync();
        // 去掉注释行再判，避免把说明文字当成代码。
        final code = src
            .split('\n')
            .where((l) {
              final t = l.trimLeft();
              return !t.startsWith('//') && !t.startsWith('///');
            })
            .join('\n');
        if (code.contains('.clamp(0.0, 1.0)')) {
          offenders.add(f.path.replaceAll('\\', '/'));
        }
      }
      expect(offenders, isEmpty,
          reason: '0–1 夹紧又出现第二份实现（非有限值的口径会再次分叉）：$offenders');
    });
  });
}
