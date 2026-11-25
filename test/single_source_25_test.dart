// 第四十一批契约：**计数与文案的回绕/荒唐值**（4 处同类缺口）。
//
// 主类是同一件事：一个 int64 坏值（服务端把计数写成 int 上限，或本机
// prefs 里手改坏）在**加法**和**格式化**两处分别出事：
//
//   1. 单元库/分类树的计数用裸 `+` 累加 → `max + max = -2`，卡片显示
//      「0 作品」（看起来只是空库，最难发现）；
//   2. 删除监测的总数同样裸加 → 负数，页头摘要变成负值；
//   3. 字节文案没有 TB 档 → int 上限输出 `8589934592.00 GB`；
//   4. 抓取间隔没有上限 → int 上限输出「每 153722867280912930 小时」。
//
// 另两条是「非有限值走进 UI 文案」：`speedLabel(NaN)` 显示 `NaNx`、
// `volumeIconFor(NaN)` 判成**满音量**（与同文件的数字显示 0 相反）。
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/byte_size.dart';
import 'package:shoucangjia/category_tree.dart';
import 'package:shoucangjia/deleted_monitor.dart';
import 'package:shoucangjia/interval_label.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/player_controls.dart';
import 'package:shoucangjia/resize_cache_api.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/video_layout.dart';
import 'package:shoucangjia/volume_control.dart';

const int _maxInt = 9223372036854775807;

BasicLib _basic(String id, {int works = 10, int authors = 1}) => BasicLib(
      id: id,
      name: id,
      rel: id,
      bigId: '',
      authors: authors,
      works: works,
    );

UnitLibrary _unit(String id, {List<BasicLib> basics = const [], List<UnitLibrary> children = const []}) =>
    UnitLibrary(
      node: LibNode(id: id, rel: id, name: id),
      basics: basics,
      children: children,
    );

List<File> _libFiles() {
  return [
    for (final f in Directory('lib').listSync())
      if (f is File && f.path.replaceAll('\\', '/').endsWith('.dart')) f
  ];
}

void main() {
  group('单元库/分类树计数不再回绕成负数', () {
    test('两个 int 上限的基础库相加仍是正数（旧写法得 -2）', () {
      final u = _unit('u', basics: [
        _basic('a', works: _maxInt),
        _basic('b', works: _maxInt),
      ]);
      expect(u.works, greaterThan(0));
      expect(u.works, _maxInt, reason: '饱和到 int 上限');
    });

    test('作者数同样饱和（不出现负作者）', () {
      final u = _unit('u', basics: [
        _basic('a', authors: _maxInt),
        _basic('b', authors: _maxInt),
      ]);
      expect(u.authors, greaterThan(0));
    });

    test('子树递归求和也走同一条（根节点含下级）', () {
      final child = _unit('c', basics: [_basic('x', works: _maxInt)]);
      final root = _unit('r', basics: [_basic('y', works: _maxInt)], children: [child]);
      expect(root.works, greaterThan(0));
    });

    test('正常计数结果不变（饱和不能改好数据）', () {
      final u = _unit('u', basics: [_basic('a', works: 3), _basic('b', works: 4)]);
      expect(u.works, 7);
      expect(u.authors, 2);
    });

    test('分类树的两个计数同样饱和', () {
      final deep = CategoryNode(name: 'd', rel: 'd', authors: const ['a']);
      var n = deep;
      for (var i = 0; i < 3; i++) {
        n = CategoryNode(name: 'x$i', rel: 'x$i', children: [n]);
      }
      expect(n.childCategoryCount, 3);
      expect(n.authorCount, 1);
    });
  });

  group('删除监测总数不再回绕', () {
    test('两个 int 上限相加仍为正（旧写法得 -2）', () {
      const st = DeletedStats(deleted: _maxInt, failed: _maxInt);
      expect(st.total, greaterThan(0));
    });

    test('正常计数不变', () {
      const st = DeletedStats(deleted: 3, failed: 1, landed: 2);
      expect(st.total, 6);
    });
  });

  group('字节文案：单位用尽换更大单位，不输出荒唐数字', () {
    test('int 上限不再是 `8589934592.00 GB`，也不再是七位数 TB', () {
      final s = formatBytes(_maxInt);
      expect(s.contains('GB'), isFalse, reason: '实际：$s');
      // 0.9.269：单位链又往上补了 PB/EB——int 上限是 8 EiB，写成
      // `8388608.00 TB` 同样是一个会把那行撑破的读数（旧断言只钉到 TB，
      // 因为当时 TB 就是最后一档）。规则不变：单位用尽继续往上。
      expect(s.contains('TB'), isFalse, reason: '实际：$s');
      expect(s.endsWith('EB'), isTrue, reason: '实际：$s');
    });

    test('既有四档未改', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536 * 1024), '1.5 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
    });

    test('刚过 1 TB 用 TB 档', () {
      expect(formatBytes(1024 * 1024 * 1024 * 1024), '1.00 TB');
    });
  });

  group('抓取间隔文案：超限值当「不自动」', () {
    test('int 上限不再输出十七位小时数', () {
      expect(everyMinutesLabel(_maxInt), '不自动');
    });

    test('上限常量本身合法、边界两侧口径正确', () {
      expect(everyMinutesLabel(kMaxIntervalMinutes), '每 ${kMaxIntervalMinutes ~/ 60} 小时');
      expect(everyMinutesLabel(kMaxIntervalMinutes + 1), '不自动');
    });

    test('既有档位未改', () {
      expect(everyMinutesLabel(0), '不自动');
      expect(everyMinutesLabel(-5), '不自动');
      expect(everyMinutesLabel(5), '每 5 分钟');
      expect(everyMinutesLabel(60), '每 1 小时');
      expect(everyMinutesLabel(90), '每 1 小时');
    });
  });

  group('倍速文案：非有限/越界值不写进 UI', () {
    test('NaN / Infinity 不再显示 `NaNx` / `Infinityx`', () {
      expect(speedLabel(double.nan), '1.0x');
      expect(speedLabel(double.infinity), '1.0x');
      expect(speedLabel(double.negativeInfinity), '1.0x');
      expect(speedLabel(0), '1.0x');
    });

    test('越界值夹到播放器支持区间（不再输出二十位数字）', () {
      expect(speedLabel(1e20), '3.0x');
      expect(speedLabel(0.01), '0.5x');
    });

    test('既有档位未改', () {
      expect(speedLabel(1.0), '1.0x');
      expect(speedLabel(1.25), '1.25x');
      expect(speedLabel(0.75), '0.75x');
      expect(speedLabel(2.0), '2.0x');
    });
  });

  group('音量图标：非有限值按静音（与同文件的数字显示同口径）', () {
    test('NaN / Infinity 不再被判成满音量', () {
      expect(volumeIconFor(double.nan), VolumeIcon.mute);
      expect(volumeIconFor(double.infinity), VolumeIcon.mute);
    });

    test('既有档位未改', () {
      expect(volumeIconFor(0), VolumeIcon.mute);
      expect(volumeIconFor(80, muted: true), VolumeIcon.mute);
      expect(volumeIconFor(49.9), VolumeIcon.down);
      expect(volumeIconFor(50), VolumeIcon.up);
    });
  });

  group('缓存占用百分比：超上限按 100%，不显示 350%', () {
    test('bytes 远大于 maxBytes 时夹到 100', () {
      const s = ResizeCacheStats(bytes: 350, maxBytes: 100);
      expect(s.usedPercent, 100);
    });

    test('上限未知 / 坏值返回 null', () {
      expect(const ResizeCacheStats(bytes: 10, maxBytes: 0).usedPercent, isNull);
      expect(const ResizeCacheStats(bytes: 10, maxBytes: -5).usedPercent, isNull);
    });

    test('正常比例仍是整数百分比', () {
      expect(const ResizeCacheStats(bytes: 50, maxBytes: 100).usedPercent, 50);
    });
  });

  group('拉伸判据：非有限框尺寸不再让判据静默失效', () {
    test('NaN 框返回 0（旧写法返回 NaN，与阈值比较恒 false）', () {
      final d = videoDistortion(sourceAspect: 1.0, base: const Size(double.nan, 100));
      expect(d.isNaN, isFalse);
      expect(d, 0);
    });

    test('Infinity 框返回 0', () {
      expect(
          videoDistortion(sourceAspect: 1.5, base: const Size(double.infinity, 100)),
          0);
    });

    test('真实偏差仍能报出来（判据没有变钝）', () {
      final d = videoDistortion(sourceAspect: 0.5, base: const Size(100, 100));
      expect(d, closeTo(1.0, 1e-9));
    });
  });

  group('契约扫描：回绕与荒唐文案不得复活', () {
    test('单元库计数必须是 sumSat（不再有 fold(0, (n, b) => n + b.works)）', () {
      final src = File('lib/unit_library.dart').readAsStringSync();
      expect(src.contains('sumSat('), isTrue);
      expect(RegExp(r'fold\(0,\s*\(n, b\) => n \+ b\.(works|authors)\)').hasMatch(src),
          isFalse);
    });

    test('分类树计数必须是 sumSat', () {
      final src = File('lib/category_tree.dart').readAsStringSync();
      expect(src.contains('sumSat('), isTrue);
      expect(RegExp(r'fold\(0,\s*\(n, c\) => n \+ c\.(childCategoryCount|authorCount)\)')
          .hasMatch(src), isFalse);
    });

    test('删除监测总数走 addSat', () {
      final src = File('lib/deleted_monitor.dart').readAsStringSync();
      expect(src.contains('int get total => addSat('), isTrue);
    });

    test('间隔上限常量只有一处定义', () {
      var n = 0;
      for (final f in _libFiles()) {
        n += RegExp(r'const int kMaxIntervalMinutes').allMatches(f.readAsStringSync()).length;
      }
      expect(n, 1);
    });

    test('lib/ 内没有第二处 `toStringAsFixed` 直接格式化倍速', () {
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final name = f.path.replaceAll('\\', '/').split('/').last;
        if (name == 'player_controls.dart') continue;
        final src = f.readAsStringSync();
        if (RegExp(r'speed\.toStringAsFixed').hasMatch(src)) offenders.add(name);
      }
      expect(offenders, isEmpty, reason: '这些文件又自己格式化倍速：$offenders');
    });
  });
}
