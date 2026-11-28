import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/collection_sync.dart';
import 'package:shoucangjia/json_num.dart';
import 'package:shoucangjia/library_rank.dart';
import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/playback_prefs.dart';
import 'package:shoucangjia/recommend_grid.dart';
import 'package:shoucangjia/sync_ledger.dart';
import 'package:shoucangjia/time_labels.dart';
import 'package:shoucangjia/unit_crawler.dart';

/// 第三十一批：布尔字段 / 时间戳范围 / 推荐页高度。
///
/// 三条都是「测试全绿、真机上崩或显示错」的形态：
///  - 布尔字段各写一遍 `== true` / `!= false`：`1`、`"true"` 在不同页面结论相反；
///  - 时间戳直接 `DateTime.fromMillisecondsSinceEpoch`：一个坏值让整页 build 抛异常；
///  - 推荐数量 `.clamp(120.0, size.height)`：窗口比 120 矮时下界大于上界，`clamp` 抛。
void main() {
  group('推荐页首屏数量：窗口矮于预留高度时不再抛异常', () {
    test('窗口高度 80（下界 120 > 上界）不抛，仍按一屏估算', () {
      // 旧实现是 `(height - chromeHeight).clamp(120.0, height)`：
      // height=80 时 clamp(120.0, 80.0) 抛 Invalid argument(s): 120.0。
      expect(() => (80.0 - 110.0).clamp(120.0, 80.0), throwsArgumentError,
          reason: '旧写法确实会抛，这条用例钉住缺口');
      expect(() => recommendVisibleCount(const Size(360, 80)), returnsNormally);
      expect(recommendVisibleCount(const Size(360, 80)), 40);
    });

    test('高度刚好等于预留高度也不抛', () {
      expect(
          () => recommendVisibleCount(const Size(360, 110)), returnsNormally);
      expect(recommendVisibleCount(const Size(360, 110)), 40);
    });

    test('0 宽高、0 列宽参数走早退分支，不进除法', () {
      expect(recommendVisibleCount(Size.zero), 40);
      expect(recommendVisibleCount(const Size(400, 800), maxCrossAxisExtent: 0),
          40);
      expect(recommendVisibleCount(const Size(400, 800), aspect: 0), 40);
    });

    test('正常尺寸仍按列×行铺满', () {
      expect(recommendVisibleCount(const Size(1440, 1400)), greaterThan(40));
    });
  });

  group('时间戳越界：不再让 build 抛 RangeError', () {
    test('DateTime 的可表示范围之外返回空，不抛', () {
      // 1e30 经 num.toInt() 落在 int 上限，FromMillisecondsSinceEpoch 抛
      // RangeError: 9223372036854775807。
      final huge = 1e30.toInt();
      expect(() => DateTime.fromMillisecondsSinceEpoch(huge), throwsRangeError,
          reason: '缺口是真的：坏值会抛');
      expect(isValidEpochMs(huge), isFalse);
      expect(dateTimeOfMs(huge), isNull);
      expect(monthDayTimeOfMs(huge), '—');
      expect(yearMonthDayTimeOfSec(huge), '—');
      expect(yearMonthDayOfSec(huge), '');
    });

    test('秒→毫秒先判范围：不回绕成 1969 年', () {
      // sec * 1000 在 int64 上静默回绕：1e19 秒 → -1000 毫秒 → 1969。
      final sec = 1e19.toInt();
      expect(sec * 1000 < 0, isTrue, reason: 'int64 乘法会回绕，旧写法会显示 1969');
      expect(dateTimeOfSec(sec), isNull);
      expect(yearMonthDayTimeOfSec(sec), '—');
      expect(yearMonthDayOfSec(sec), '');
    });

    test('正常时间照旧显示', () {
      final ms = DateTime(2026, 11, 23, 17, 5).millisecondsSinceEpoch;
      expect(monthDayTimeOfMs(ms), '11-23 17:05');
      final sec = ms ~/ 1000;
      expect(yearMonthDayTimeOfSec(sec), '2026-11-23 17:05');
      expect(yearMonthDayOfSec(sec), '2026-11-23');
      expect(monthDayTimeOfMs(0), '—');
      expect(monthDayTimeOfMs(-5), '—');
      expect(yearMonthDayOfSec(-5), '');
    });
  });

  group('布尔字段：同一份数据在所有页面结论一致', () {
    test('json_num 是唯一判定：1 / "true" / "yes" 都为真', () {
      for (final t in [true, 1, 'true', 'TRUE', '1', 'yes', 'on']) {
        expect(boolOf(t), isTrue, reason: '$t 应为真');
      }
      for (final f in [false, 0, 'false', '0', 'no', 'off']) {
        expect(boolOf(f, true), isFalse, reason: '$f 应为假');
      }
      expect(boolOrNull(null), isNull);
      expect(boolOf(null, true), isTrue);
    });

    test('同步源：sync/inIndex/account/customName 接受数字与字符串布尔', () {
      final r = parseCollectionSettings({
        'collections': [
          {
            'idx': 2,
            'name': 'x',
            'count': 3,
            'sync': 'true',
            'inIndex': 1,
            'account': 'yes',
            'customName': 1,
          },
        ],
      }).single;
      expect(r.sync, isTrue);
      expect(r.inIndex, isTrue);
      expect(r.account, isTrue);
      expect(r.customName, isTrue);
      // 旧写法 `sync: j['sync'] != false` 对字符串 "false" 判真，
      // 表现为「设置页已取消勾选，主页仍显示这个同步源」。
      final off = parseCollectionSettings({
        'collections': [
          {'idx': 3, 'name': 'y', 'count': 1, 'sync': 'false', 'inIndex': 0},
        ],
      }).single;
      expect(off.sync, isFalse);
      expect(off.inIndex, isFalse);
      expect(off.subtitle, contains('不参与同步'));
    });

    test('墓碑判断走同一实现：deleted:"true" / 1 都算删除', () {
      for (final v in [true, 1, 'true']) {
        final rows = parseCollectionSettings({
          'collections': [
            {'idx': 2, 'name': 'x', 'count': 1, 'deleted': v},
            {'idx': 5, 'name': 'y', 'count': 1},
          ],
        });
        expect(rows.map((e) => e.idx), [5], reason: 'deleted=$v 应被过滤');
      }
    });

    test('连接表：enabled / 旧 visible 的 0 与 "false" 都是已断连', () {
      final a = decodeServers('[{"id":"a","base":"http://x:1","enabled":0}]');
      expect(a.single.enabled, isFalse);
      final b =
          decodeServers('[{"id":"b","base":"http://y:1","visible":"false"}]');
      expect(b.single.enabled, isFalse);
      // 断连的连接不得保留密码（旧写法 `!= false` 会把 "false" 当连接，
      // 于是密码又被读回来）。
      final c = decodeServers(
          '[{"id":"c","base":"http://z:1","visible":"false","pass":"p"}]');
      expect(c.single.pass, '');
      // 正常值不受影响。
      expect(
          decodeServers('[{"id":"d","base":"http://d:1","enabled":true}]')
              .single
              .enabled,
          isTrue);
      expect(decodeServers('[{"id":"e","base":"http://e:1"}]').single.enabled,
          isTrue);
    });

    test('单元库爬虫标记：1 / "true" 视为已配置脚本', () {
      final f = unitCrawlerFlags({
        'crawler': {'(1) A': 1, '(2) B': 'true', '(3) C': false, '(4) D': 'x'},
      });
      expect(f['(1) A'], isTrue);
      expect(f['(2) B'], isTrue);
      expect(f['(3) C'], isFalse);
      expect(f['(4) D'], isFalse);
    });

    test('同步日志 running：1 / "true" 也算运行中', () {
      final log = parseSyncLog({
        'runs': [
          {'id': 'r1', 'at': 1795427100000, 'running': 1},
          {'id': 'r2', 'at': 1795427100000, 'running': 'true'},
          {'id': 'r3', 'at': 1795427100000, 'running': false},
        ],
      });
      expect(log.runs[0].running, isTrue);
      expect(log.runs[1].running, isTrue);
      expect(log.runs[2].running, isFalse);
    });

    test('播放设置：本机 prefs 只认 bool，类型不对回默认', () {
      // 本机写入的 prefs 永远是 bool；`"true"` / 1 这种是服务端形态，
      // 进了 prefs 说明数据被别处改过，按默认值处理比“猜”更安全。
      // 0.9.356：`speed` 已不在本类（倍速归 AppSettings.defaultSpeed），
      // 旧 payload 里的这个键读入时忽略，且不影响其余三个开关。
      final p = PlaybackPrefs.fromJson({
        'speed': '1.5',
        'loopOne': 'true',
        'autoplay': 0,
        'restoreAutoplay': true,
        'shuffle': 'yes',
      });
      expect(p.link.loopOne, isFalse);
      expect(p.link.autoplay, isTrue);
      expect(p.link.restoreAutoplay, isTrue);
      expect(p.shuffle, isFalse);
    });
  });

  group('统计聚合：authors 字段类型漂移时不抛', () {
    test('authors 是字符串/数字/null 一律空表', () {
      expect(statsAuthors({'authors': 'oops'}), isEmpty);
      expect(statsAuthors({'authors': 3}), isEmpty);
      expect(statsAuthors({'authors': null}), isEmpty);
      expect(statsAuthors('oops'), isEmpty);
      expect(
          statsAuthors({
            'authors': {'a': 1}
          }),
          {'a': 1});
    });
  });

  group('契约：lib/ 内布尔判定只剩 json_num 一处写法', () {
    String codeOf(String path) => File(path)
        .readAsStringSync().replaceAll('\r\n', '\n')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('布尔字段不再写 != false（0/"false" 会被当成真）', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('json_num.dart') ||
            f.path.endsWith('http_json.dart')) {
          continue;
        }
        for (final line in codeOf(f.path).split('\n')) {
          if (!RegExp(r"!=\s*false").hasMatch(line)) continue;
          // 只看 JSON 字段判定；`ok` 是写接口契约（缺字段即失败），保留。
          if (!line.contains("['")) continue;
          if (line.contains("'ok'")) continue;
          offenders.add('${f.path}: ${line.trim()}');
        }
      }
      expect(offenders, isEmpty, reason: '又出现 != false 的布尔判定：$offenders');
    });

    test('非 ok 字段不再写 == true（1/"true" 会被当成假）', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('json_num.dart') ||
            f.path.endsWith('http_json.dart')) {
          continue;
        }
        for (final line in codeOf(f.path).split('\n')) {
          if (!line.contains('== true')) continue;
          // 只看 JSON 字段判定：Flutter 回调里的 `v == true`（Checkbox 的
          // `bool?`）是框架类型，不是服务端字段。
          if (!line.contains("['")) continue;
          // `ok == true` 是写接口契约（缺字段即失败），保留。
          if (line.contains("'ok'")) continue;
          offenders.add('${f.path}: ${line.trim()}');
        }
      }
      expect(offenders, isEmpty, reason: '布尔字段又各写一遍 == true：$offenders');
    });

    test('布尔字段不再写 == false（"false"/0 会被当成在线）', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('json_num.dart') ||
            f.path.endsWith('http_json.dart')) {
          continue;
        }
        for (final line in codeOf(f.path).split('\n')) {
          if (!RegExp(r"==\s*false").hasMatch(line)) continue;
          if (!line.contains("['")) continue;
          if (line.contains("'ok'")) continue;
          offenders.add('${f.path}: ${line.trim()}');
        }
      }
      expect(offenders, isEmpty, reason: '又出现 == false 的布尔判定：$offenders');
    });

    test('时间戳构造只有 time_labels 的安全入口', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('time_labels.dart')) continue;
        if (codeOf(f.path).contains('DateTime.fromMillisecondsSinceEpoch') ||
            codeOf(f.path).contains('DateTime.fromMicrosecondsSinceEpoch')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty, reason: '时间戳又绕开安全构造：$offenders');
    });
  });
}
