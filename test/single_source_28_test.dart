/// 0.9.269 第四十八批：四类「同一件事两份口径」缺口。
///
/// 共同点不是「某个数字算错」，而是**同一个读数有两个写法**，而用户看到的
/// 那一版恰好是说大的那个：
///
///  1. `formatBytes` 的 TB 是最后一档 → int 上限（9.22e18 字节 = 8 EiB）
///     显示成 `8388608.00 TB`（七位数 + 两位小数，诊断页那行撑破）；
///  2. `syncDurationLabel` 的档位按**原始秒数**判 → 9999ms 走一位小数分支，
///     四舍五入成 `10.0s`，而 10000ms 是 `10s`：同一个「10 秒」两种写法，
///     且 `10.0s` 那个本来是 9.999s，被说大成整 10 秒；
///  3. `ResizeCacheStats.hitRateText` 直接 `toStringAsFixed(1)` → `0.99995`
///     显示成 `100.0%`（等于说「一次没漏」，实际还有未命中）；
///  4. `ContinueItem.key` 不 `trim()` 库 id，而观看记录/播放量两条都 `trim()`
///     → 同一条作品在两张表里是两个键：`A /1` vs `A/1`，「看完即从继续观看
///     移除」删不掉自己写进去的那条。
///
/// 四条都改成与既有口径一致（截断而非四舍五入；键只认一处实现）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/byte_size.dart';
import 'package:shoucangjia/continue_watching.dart';
import 'package:shoucangjia/resize_cache_api.dart';
import 'package:shoucangjia/sync_ledger.dart';
import 'package:shoucangjia/watch_progress.dart';
import 'package:shoucangjia/work_key.dart';
import 'package:shoucangjia/work_plays.dart';

const int _maxInt = 9223372036854775807;

void main() {
  group('字节文案：单位用尽继续往上，不输出七位数 TB', () {
    test('int 上限是 8 EiB，不再写成 `8388608.00 TB`', () {
      final s = formatBytes(_maxInt);
      expect(s.contains('TB'), isFalse, reason: '实际：$s');
      expect(s, '8.00 EB');
    });

    test('1 EiB 不再写成 `1048576.00 TB`', () {
      expect(formatBytes(1152921504606846976), '1.00 EB');
    });

    test('PB 档存在且不进位', () {
      // 1 PB = 1024^5
      expect(formatBytes(1125899906842624), '1.00 PB');
      // 1 PB − 1 字节：截断后仍是 1023.99 TB，绝不显示 1024.00 TB
      final s = formatBytes(1125899906842624 - 1);
      expect(s.contains('1024.00 TB'), isFalse, reason: '实际：$s');
      expect(s.endsWith('TB'), isTrue);
    });

    test('既有四档与跨档边界一字不改', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536 * 1024), '1.5 MB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
      expect(formatBytes(1024 * 1024 * 1024 * 1024), '1.00 TB');
      expect(formatBytes(1024 * 1024 - 1).contains('1024.0 KB'), isFalse);
      expect(formatBytes(1024 * 1024 * 1024 - 1).contains('1024.0 MB'), isFalse);
      expect(
          formatBytes(1024 * 1024 * 1024 * 1024 - 1).contains('1024.00 GB'),
          isFalse);
    });
  });

  group('同步耗时：档位按显示值判，不跨档说大', () {
    test('9999ms 不再显示 `10.0s`（10000ms 是 `10s`）', () {
      expect(syncDurationLabel(9999), '9.9s');
      expect(syncDurationLabel(10000), '10s');
    });

    test('9.94s~9.99s 全部截断成 9.9s，不出现 10.0s', () {
      for (final ms in [9940, 9950, 9990, 9999]) {
        expect(syncDurationLabel(ms), '9.9s', reason: '4ms=$ms');
      }
    });

    test('59.9s 仍不显示成 60s，59.99s 也不', () {
      expect(syncDurationLabel(59900), '59s');
      expect(syncDurationLabel(59999), '59s');
    });

    test('秒级既有行为不变', () {
      expect(syncDurationLabel(820), '820ms');
      expect(syncDurationLabel(2400), '2.4s');
      expect(syncDurationLabel(0), '—');
      expect(syncDurationLabel(-5), '—');
      expect(syncDurationLabel(60000), '1m 00s');
      expect(syncDurationLabel(65000), '1m 05s');
      expect(syncDurationLabel(119600), '2m 00s');
    });
  });

  group('命中率文案：截断而不是四舍五入成 100%', () {
    test('0.99995 不再显示 `100.0%`', () {
      expect(ResizeCacheStats(hitRate: 0.99995).hitRateText, '99.9%');
      expect(ResizeCacheStats(hitRate: 0.99994).hitRateText, '99.9%');
    });

    test('真的是 100% 时才写 100.0%', () {
      expect(ResizeCacheStats(hitRate: 1.0).hitRateText, '100.0%');
      expect(ResizeCacheStats(hitRate: 0.0).hitRateText, '0.0%');
      expect(ResizeCacheStats(hitRate: 0.9).hitRateText, '90.0%');
    });

    test('非有限/负数不产出 NaN% 或负百分比', () {
      expect(ResizeCacheStats(hitRate: double.nan).hitRateText, '0.0%');
      expect(ResizeCacheStats(hitRate: -0.5).hitRateText, '0.0%');
    });
  });

  group('继续观看的键与观看记录/播放量同一口径', () {
    test('库 id 带空白时三张表算出同一个键', () {
      const ci = ContinueItem(lib: 'A ', id: '1');
      expect(ci.key, workKey(lib: 'A ', id: '1'));
      expect(ci.key, watchProgressKey(lib: 'A ', id: '1'));
      expect(ci.key, workPlaysKey(lib: 'A ', id: '1'));
      expect(ci.key, 'A/1');
    });

    test('写进去的键能被同一条记录删掉', () {
      final items = <ContinueItem>[
        const ContinueItem(
            lib: 'A ', id: '1', positionMs: 5000, durationMs: 10000),
      ];
      final after = removeContinueItem(items, 'A ', '1');
      expect(after, isEmpty);
      expect(removeContinueItem(items, 'A', '1'), isEmpty);
    });

    test('空白 id 没有键（调用方据此跳过）', () {
      expect(const ContinueItem(lib: 'A', id: '  ').key, '');
    });

    test('从 JSON 读回的键与内存里的键一致', () {
      final parsed = ContinueItem.fromJson(
          {'l': ' A ', 'i': ' 1 ', 'p': 5000, 'd': 10000});
      expect(parsed, isNotNull);
      expect(parsed!.key, 'A/1');
    });
  });

  group('契约扫描：四条规则各自只有一处实现', () {
    test('formatBytes 不再以 TB 收尾', () {
      final src = File('lib/byte_size.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(src.contains("'TB'"), isTrue);
      expect(src.contains("return '\${_truncated(gb / 1024, 2)} TB';"), isFalse);
    });

    test('同步耗时档位不再拿原始秒数比 10', () {
      // 只扫代码行（去掉注释）：注释里引用旧写法是说明，不算实现。
      final code = File('lib/sync_ledger.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('sec < 10'), isFalse);
      expect(code.contains(r'${sec.toStringAsFixed(1)}s'), isFalse);
    });

    test('命中率不再直接 toStringAsFixed', () {
      final src = File('lib/resize_cache_api.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(src.contains(r'(hitRate * 100).toStringAsFixed(1)'), isFalse);
    });

    test('ContinueItem.key 只转发 workKey', () {
      final src = File('lib/continue_watching.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(src.contains("lib.isEmpty ? id : '\$lib/\$id'"), isFalse);
      expect(src.contains('String get key => workKey(lib: lib, id: id);'), isTrue);
    });
  });
}
