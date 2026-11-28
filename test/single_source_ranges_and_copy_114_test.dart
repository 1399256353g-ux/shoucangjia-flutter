import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/http_json.dart';
import 'package:shoucangjia/interval_label.dart';
import 'package:shoucangjia/playback_prefs.dart';
import 'package:shoucangjia/ui_copy.dart';

/// 第一百一十四批（0.9.361）：**同一个量/同一个说法有两个家**。
///
/// 本轮抓到的都是同一族：一个值或一句话，在相邻的两个地方各写一遍，
/// 两边都「看起来正常」，只有改了其中一处才暴露——而那时用户看到的是
/// 「设置页能选、播放页没有」「同一页两个说法」这类无法自查的差异。
///
/// 六条并到一批收口：
/// 1. 倍速区间 `0.5..3.0`：显示层 / 写入层 / 读盘层各一份 → `clampSpeed`；
/// 2. 图文间隔 `1..20`、隐藏时间 `1..30`：读盘 clamp 与 Slider 各一份 →
///    `AppSettings.clamp*`；
/// 3. 库根爬虫频率档位：档位表连带文案写死 → 档位表与 `everyMinutesLabel`；
/// 4. 「不自动」三个字：档位 chip / 列表行 / 回显各一种说法 → 同一个出口；
/// 5. 「网络错误」：6 处字面量 → `kNoResponseText` / `failureTextOf`；
/// 6. 作者名输入框标签与挂载面板标题三处各写一遍 → `ui_copy.dart`。
String codeOf(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// 只取代码行（注释里引用旧写法不算实现）。
List<String> codeLines(String path) => [
      for (final l in codeOf(path).split('\n'))
        if (!l.trimLeft().startsWith('//')) l
    ];

void main() {
  group('1. 倍速区间只有一份（clampSpeed）', () {
    test('clampSpeed 的边界', () {
      expect(clampSpeed(1.0), 1.0);
      expect(clampSpeed(0.1), kSpeedMin);
      expect(clampSpeed(9.0), kSpeedMax);
      expect(clampSpeed(double.nan), 1.0);
      // 无穷/非正都是「不是倍速」：回到默认 1.0，与 `speedLabel` 同一条判定
      // （旧 `speedLabel` 对 `1e20` 显示 3.0x，对 `infinity` 却显示 1.0x，
      // 同一种坏数据两个答案——这里把它钉成后者，两处口径一致）。
      expect(clampSpeed(double.infinity), 1.0);
      expect(clampSpeed(double.negativeInfinity), 1.0);
      expect(clampSpeed(-2), 1.0);
      expect(clampSpeed(1e20), kSpeedMax);
    });

    test('显示层与写入层不再各写 0.5/3.0', () {
      final pc = codeOf('lib/player_controls.dart');
      expect(pc, contains('final s = clampSpeed(speed);'),
          reason: 'speedLabel 必须转发 clampSpeed');
      expect(RegExp(r'\.clamp\(0\.5, 3\.0\)').hasMatch(pc), isFalse,
          reason: 'player_controls 里又出现了一份倍速边界');

      final main = codeOf('lib/main.dart');
      expect(main, contains('final next = clampSpeed(value);'));
      expect(RegExp(r'value\.clamp\(0\.5, 3\.0\)').hasMatch(main), isFalse,
          reason: 'setSpeed 又自己夹了一份区间');
    });

    test('读盘夹紧也走同一个出口', () {
      final ap = codeOf('lib/app_settings.dart');
      expect(ap, contains('clampSpeed(doubleOf(j[\'speed\']'),
          reason: 'applyJson 读倍速必须走 clampSpeed');
      expect(RegExp(r'defaultSpeed\.clamp\(0\.5, 3\.0\)').hasMatch(ap), isFalse);
    });

    test('区间常量只在一处定义', () {
      var defs = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final s = f.readAsStringSync();
        defs += RegExp(r'const double kSpeedMin = ').allMatches(s).length;
      }
      expect(defs, 1, reason: 'kSpeedMin 只能在 playback_prefs 定义一次');
    });
  });

  group('2. 图文间隔 / 隐藏时间的区间只有一份', () {
    test('clamp* 与常量一致', () {
      expect(AppSettings.clampImageInterval(0), AppSettings.imageIntervalMinSec);
      expect(
          AppSettings.clampImageInterval(99), AppSettings.imageIntervalMaxSec);
      expect(AppSettings.clampHideUi(0), AppSettings.hideUiMinSec);
      expect(AppSettings.clampHideUi(99), AppSettings.hideUiMaxSec);
      expect(AppSettings.imageIntervalMinSec, 1);
      expect(AppSettings.imageIntervalMaxSec, 20);
      expect(AppSettings.hideUiMinSec, 1);
      expect(AppSettings.hideUiMaxSec, 30);
    });

    test('Slider 与读盘不再写裸数字', () {
      final main = codeOf('lib/main.dart');
      expect(RegExp(r'max: 20,').hasMatch(main), isFalse,
          reason: 'Slider 又手写了 20');
      expect(RegExp(r'divisions: 19,').hasMatch(main), isFalse);
      expect(RegExp(r'max: 30,').hasMatch(main), isFalse);
      expect(RegExp(r'divisions: 29,').hasMatch(main), isFalse);
      expect(main, contains('AppSettings.imageIntervalMaxSec'));
      expect(main, contains('AppSettings.hideUiMaxSec'));

      final ap = codeOf('lib/app_settings.dart');
      expect(RegExp(r'\.clamp\(1, 20\)').hasMatch(ap), isFalse,
          reason: '读盘还留着独立的 1..20');
      expect(RegExp(r'\.clamp\(1, 30\)').hasMatch(ap), isFalse);
    });
  });

  group('3. 库根爬虫频率档位与文案同源', () {
    test('档位表是唯一一份，且都落在合法值上', () {
      expect(kCrawlIntervalOptions, <int>[0, 30, 60, 360, 720, 1440]);
      for (final m in kCrawlIntervalOptions) {
        expect(everyMinutesLabel(m), isNotEmpty);
      }
      expect(everyMinutesLabel(0), '不自动');
    });

    test('设置页不再写死「每 N 小时」档位文案', () {
      final main = codeOf('lib/main.dart');
      expect(main, contains('for (final m in kCrawlIntervalOptions)'));
      for (final s in <String>[
        "'每 30 分钟'",
        "'每 1 小时'",
        "'每 6 小时'",
        "'每 12 小时'",
        "'每 24 小时'",
      ]) {
        expect(codeLines('lib/main.dart').any((l) => l.contains(s)), isFalse,
            reason: '档位文案 $s 又写回了页面');
      }
    });
  });

  group('4. 「不自动」只有一种说法', () {
    test('列表行与回显都走 everyMinutesLabel', () {
      final main = codeOf('lib/main.dart');
      expect(main, contains("everyMinutesLabel(intOf(_cfgOf(j)['intervalMin']))"));
      expect(codeLines('lib/main.dart').any((l) => l.contains("'不自动抓取'")),
          isFalse, reason: '「不自动抓取」是同一状态的第二个说法');
      expect(main, contains("'当前：\${everyMinutesLabel(0)}（仍可手动同步）'"));
    });

    test('everyMinutesLabel 的非正数答案只有「不自动」', () {
      expect(everyMinutesLabel(0), '不自动');
      expect(everyMinutesLabel(-1), '不自动');
      expect(everyMinutesLabel(kMaxIntervalMinutes + 1), '不自动');
    });
  });

  group('5. 失败原因只有一个短信道', () {
    test('failureTextOf：服务端原因优先，否则统一文案', () {
      expect(failureTextOf({'error': ' 缺 lib '}), '缺 lib');
      expect(failureTextOf({'ok': false}), kNoResponseText);
      expect(failureTextOf(null), kNoResponseText);
      expect(kNoResponseText, '网络错误');
    });

    test('main.dart 里不再散落「网络错误」字面量', () {
      final hits = codeLines('lib/main.dart')
          .where((l) => l.contains("'网络错误'"))
          .toList();
      expect(hits, isEmpty, reason: '应改走 kNoResponseText / failureTextOf：$hits');
    });

    test('六处调用点都换成单一出口', () {
      final main = codeOf('lib/main.dart');
      expect(RegExp(r'serverErrorText\(j\) \?\? ').hasMatch(main), isFalse);
      expect(main, contains('failureTextOf('));
      expect(main, contains('kNoResponseText'));
    });
  });

  group('6. 跨页面共用文案只有一份', () {
    test('作者名输入框标签三处都读常量', () {
      for (final p in <String>[
        'lib/basic_lib_page.dart',
        'lib/unit_author_mount_page.dart',
        'lib/main.dart',
      ]) {
        final lines = codeLines(p);
        expect(lines.any((l) => l.contains("'作者名（会建成 @作者名 目录）'")),
            isFalse,
            reason: '$p 又手写了标签文案');
        expect(lines.any((l) => l.contains('kAuthorNameFieldLabel')), isTrue,
            reason: '$p 没有转发 kAuthorNameFieldLabel');
      }
    });

    test('挂载面板标题三处都读常量', () {
      for (final p in <String>[
        'lib/author_mount_sheet.dart',
        'lib/unit_author_mount_page.dart',
        'lib/unit_library_view.dart',
      ]) {
        final lines = codeLines(p);
        expect(lines.any((l) => l.contains("'作者文件夹挂载'")), isFalse,
            reason: '$p 又手写了面板标题');
        expect(lines.any((l) => l.contains('kAuthorMountTitle')), isTrue);
      }
    });

    test('常量值就是界面上那句话', () {
      expect(kAuthorNameFieldLabel, '作者名（会建成 @作者名 目录）');
      expect(kAuthorMountTitle, '作者文件夹挂载');
    });
  });
}
