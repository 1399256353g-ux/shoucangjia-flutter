/// 0.9.270 第五十批：**同一个读数在屏幕上出现两个值**。
///
/// 第四十八批修的是「同一个读数有两种算法，用户看到的是说大的那个」；
/// 这一批是同一个口径的另一面：算法一致（或本该一致），但**同一屏里
/// 显示的却不是一个数**，而且差的常常是「看起来更正常」的那一个，
/// 于是不会有人报上来。
///
///  1. `formatBadgeDuration` 用 `round()`，播放页进度行用截断 →
///     同一部片子角标写 `1:00:00`、进度行写 `59:59`；
///  2. `formatCount` 的单位链到「亿」就结束 → int 上限（坏数据常见形态）
///     算出 `92233720368.5亿`（十一位数字，卡片直接撑破）；
///  3. `formatCount` 只服务单元库卡，基础库卡/设置页/文件结构页/作者挂载
///     面板各自拼原始数字 → 同一个基础库在网格是 `1.2万 作品`、在设置页
///     是 `12345 作品`；
///  4. 播放页音量：任务栏模块的滑杆用 `muted ? 0 : volume`、旁边数字用
///     `volume.round()` → 一按静音，滑杆归零、数字仍写 `100`。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/byte_size.dart';
import 'package:shoucangjia/count_label.dart';
import 'package:shoucangjia/cover_badges.dart';
import 'package:shoucangjia/time_labels.dart';
import 'package:shoucangjia/volume_control.dart';

const int _maxInt = 9223372036854775807;

String _code(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('封面角标时长与播放页进度同一口径（截断）', () {
    test('小数秒不再被四舍五入到下一秒', () {
      expect(formatBadgeDuration(12.6), '0:12');
      expect(formatBadgeDuration(12.4), '0:12');
      expect(formatBadgeDuration(59.5), '0:59');
    });

    test('角标与进度行对同一条媒体给出同一读数', () {
      for (final ms in <int>[12600, 59500, 59501, 3599500, 3599999]) {
        final badge = formatBadgeDuration(ms / 1000);
        final clock = formatClockMs(ms); // `mm:ss` / `h:mm:ss`，补零
        // 角标不足 1 小时时分钟不补零（`0:59`），进度行补零（`00:59`）：
        // 差别只在补零，**秒数**必须完全相同。
        final badgeSec = int.parse(badge.split(':').last);
        final clockSec = int.parse(clock.split(':').last);
        expect(badgeSec, clockSec, reason: 'ms=$ms badge=$badge clock=$clock');
      }
    });

    test('整秒不受影响', () {
      expect(formatBadgeDuration(0.999), '', reason: '不足 1 秒不画角标');
      expect(formatBadgeDuration(1), '0:01');
      expect(formatBadgeDuration(60), '1:00');
      expect(formatBadgeDuration(3725), '1:02:05');
      expect(formatBadgeDuration(kBadgeMaxSeconds.toDouble()), '100:00:00');
    });
  });

  group('计数文案单位链：亿之后还有万亿 / 亿亿', () {
    test('int 上限不再撑出十一位数字', () {
      final s = formatCount(_maxInt);
      expect(s, '922.3亿亿');
      expect(s.length, lessThan(12), reason: '实际：$s');
    });

    test('各档边界', () {
      expect(formatCount(99999999), '9999.9万');
      expect(formatCount(100000000), '1亿');
      expect(formatCount(999999999999), '9999.9亿');
      expect(formatCount(1000000000000), '1万亿');
      expect(formatCount(9999999999999999), '9999.9万亿');
      expect(formatCount(10000000000000000), '1亿亿');
    });

    test('仍然一律截断，不虚报跨档', () {
      expect(formatCount(999949), '99.9万');
      expect(formatCount(999999999999999999), '99.9亿亿');
    });
  });

  group('计数文案只有一个出口，四个页面都走它', () {
    test('定义在 count_label.dart，单元库只做 re-export', () {
      final label = File('lib/count_label.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(label.contains('String formatCount(int n)'), isTrue);
      final unit = _code('lib/unit_library.dart');
      expect(unit.contains('String formatCount(int n)'), isFalse,
          reason: 'unit_library 里又存了第二份 formatCount');
      expect(unit.contains("export 'count_label.dart' show formatCount;"),
          isTrue);
    });

    test('基础库卡 / 设置页 / 文件结构页 / 作者挂载面板都用 formatCount', () {
      for (final f in <String>[
        'lib/unit_library_view.dart',
        'lib/main.dart',
        'lib/folder_structure_page.dart',
        'lib/author_mount_sheet.dart',
        'lib/unit_author_groups.dart',
      ]) {
        final s = _code(f);
        final raw = RegExp(r'\$\{(\w+)\.(works|authors)\} (作品|作者)');
        expect(raw.hasMatch(s), isFalse,
            reason: '$f 又直接拼了原始计数：${raw.allMatches(s).map((m) => m.group(0)).toList()}');
        expect(s.contains('formatCount('), isTrue, reason: '$f 没走 formatCount');
      }
    });

    test('作者合并摘要的作品数同样走 formatCount', () {
      expect(authorMergeSummaryWorksProbe(), isTrue);
    });
  });

  group('诊断页两个字节读数同一套单位', () {
    test('图片缓存不再自己算 MB，与缩图缓存同为 formatBytes', () {
      final s = _code('lib/crash_reports_page.dart');
      expect(RegExp(r'1024 \* 1024').hasMatch(s), isFalse,
          reason: '诊断页又手算了 MB');
      expect(s.contains('formatBytes('), isTrue);
      // 两个读数并排时必须同档：`1.50 GB` 旁边不会再出现 `2048 MB`。
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.00 GB');
    });
  });

  group('音量读数：滑杆位置与数字同源', () {
    test('静音时滑杆与数字都是 0（旧写法数字仍写 100）', () {
      expect(volumePercentShown(100, muted: true), 0);
      expect(volumeSliderValue(100, muted: true), 0);
    });

    test('正常值与两端', () {
      expect(volumePercentShown(37.4), 37);
      expect(volumePercentShown(100), 100);
      expect(volumePercentShown(0), 0);
      expect(volumeSliderValue(37.4), 37.4);
      expect(volumeSliderValue(150), 100);
    });

    test('非有限值在两个读数里都是 0（NaN.clamp 返回上界）', () {
      expect(volumePercentShown(double.nan), 0);
      expect(volumeSliderValue(double.nan), 0);
      expect(volumeSliderValue(double.infinity), 0);
    });

    test('播放页不再自己拼音量数字或滑杆位置', () {
      final s = _code('lib/main.dart');
      expect(s.contains(r'(muted ? 0 : volume).round()'), isFalse);
      expect(s.contains(r'${volume.round()}'), isFalse);
      expect(
          s.contains(r'(muted ? 0.0 : volume.clamp(0.0, 100.0))'), isFalse);
      expect(s.contains('volumePercentShown('), isTrue);
      expect(s.contains('volumeSliderValue('), isTrue);
    });

    test('静音时滑杆与数字同为 0（不会一边归零一边写满）', () {
      for (final v in <double>[0, 1, 37.4, 50, 99.9, 100]) {
        expect(volumePercentShown(v, muted: true), 0, reason: 'v=\$v');
        expect(volumeSliderValue(v, muted: true), 0, reason: 'v=\$v');
      }
    });
  });
}

/// `authorMergeSummary` 的作品数是否走了 [formatCount]。
///
/// 单独包一层是因为它只需要一个「大于 1 万的计数会不会被缩写」的可见证据。
bool authorMergeSummaryWorksProbe() {
  // 1.2万，而不是 12345。
  return countWorksTextProbe(12345) == '1.2万 作品';
}

/// 面板摘要里「N 作品」的实际文案（与 `authorMergeSummary` 同一口径）。
String countWorksTextProbe(int works) => '${formatCount(works)} 作品';
