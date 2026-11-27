// 第三十九批（0.9.233）：JSON 解析只有一份实现。
//
// 三条都是「同一件事多套写法，其中一套会崩」：
//  1. 对象数组 → Map 列表：6 处 `Map.from(e as Map)`，`e` 是字符串/数字时抛
//     `_TypeError`；首页那条在 `Future.wait` 的 catch 里 → 整个连接列表变空，
//     爬虫页那条没有 catch → 界面停在加载中；
//  2. 数值 → int：12 处，其中 `resize_cache_api` 用 `round()`、其余用 `toInt()`，
//     同一个 1.6 个文件在缓存页显示 2、在别处显示 1；
//  3. 设置读入用裸 `as num?`：落盘里 `"speed": "1.5"` 会在**启动时**抛，
//     整份设置（速度/预载/词条/全部按键绑定）一起退回默认。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/http_json.dart';
import 'package:shoucangjia/author_grade.dart';
import 'package:shoucangjia/json_num.dart';
import 'package:shoucangjia/watch_progress.dart';

String _code(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('对象数组解析：坏条目跳过，不抛异常', () {
    test('mapsOf 跳过非对象成员', () {
      expect(mapsOf([{'id': 'a'}, 'junk', 42, null, {'id': 'b'}]).length, 2);
      expect(mapsOf([{'id': 'a'}, 'junk']).first['id'], 'a');
    });

    test('mapsOf 非列表输入返回空（不猜、不抛）', () {
      expect(mapsOf(null), isEmpty);
      expect(mapsOf('a'), isEmpty);
      expect(mapsOf({'k': 1}), isEmpty);
    });

    test('mapOrNull 只认对象', () {
      expect(mapOrNull({'a': 1})?['a'], 1);
      expect(mapOrNull('a'), isNull);
      expect(mapOrNull(3), isNull);
      expect(mapOrNull(null), isNull);
    });

    test('契约：lib/ 里不得再写 Map.from(x as Map)', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = _code(f.path);
        if (RegExp(r'\.from\(\s*\w+(?:\.\w+)?\[[^]]*\]\s+as\s+Map\s*\)')
            .hasMatch(src)) {
          offenders.add(f.path);
        }
        if (RegExp(r'\.from\(\s*\w+\s+as\s+Map\s*\)').hasMatch(src)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '非对象成员会让整张列表消失（首页连接列表曾因此变空）：$offenders');
    });
  });

  group('数值解析：截断语义唯一', () {
    test('intOf 截断而不是四舍五入', () {
      // 缓存页此前用 round()：1.6 个文件显示成 2，凭空多一个文件。
      expect(intOf(1.6), 1);
      expect(intOf(1.4), 1);
      expect(intOf(-1.6), -1);
      expect(intOf(7), 7);
      expect(intOf('8'), 8);
      expect(intOf(' 9 '), 9);
      expect(intOf('abc'), 0);
      expect(intOf('abc', 5), 5);
      expect(intOf(null), 0);
      expect(intOf(double.nan), 0);
      expect(intOf(double.infinity), 0);
    });

    test('doubleOf 容错', () {
      expect(doubleOf('1.5'), 1.5);
      expect(doubleOf(2), 2.0);
      expect(doubleOf('x'), 0);
      expect(doubleOf('x', 3), 3);
      expect(doubleOf(double.nan), 0);
    });

    test('契约：lib/ 内不得再有第二份「num 或字符串 → int」', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('json_num.dart')) continue;
        final src = _code(f.path);
        if (RegExp(r'int\.tryParse\([^)]*\)\s*\?\?\s*(?:0|d|fallback)')
            .hasMatch(src)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '数值解析分叉后同一个值在不同页面显示不同：$offenders');
    });
  });

  group('设置读入：字符串数值不能让整份设置退回默认', () {
    setUp(AppSettings.resetDefaults);

    test('speed 是字符串也能读进来', () {
      AppSettings.applyJson(<String, dynamic>{'speed': '1.5'});
      expect(AppSettings.defaultSpeed, 1.5);
    });

    test('坏字段只影响它自己，其它字段照常生效', () {
      AppSettings.applyJson(<String, dynamic>{
        'speed': 'not-a-number',
        'imageInterval': '7',
        'hideUi': 5,
        'preloadPerSide': '2',
      });
      // speed 回落默认，但后面三个必须生效——旧实现整份抛异常，四个都丢。
      expect(AppSettings.defaultSpeed, 1.0);
      expect(AppSettings.imageIntervalSec, 7);
      expect(AppSettings.hideUiSec, 5);
      expect(AppSettings.preloadPerSide, 2);
    });

    test('按键绑定的键码是字符串时仍能恢复', () {
      AppSettings.applyJson(<String, dynamic>{
        'keys': {
          'playPause': {'k': '32', 'm': 0},
        },
      });
      final combo = AppSettings.keyBindings[PlayerAction.playPause];
      expect(combo, isNotNull);
      expect(combo!.keyId, 32);
    });

    test('键码缺失/为 0 的组合被丢弃，不生成空绑定', () {
      AppSettings.applyJson(<String, dynamic>{
        'keys': {
          'playPause': {'k': 0, 'm': 0},
          'mute': {'m': 1},
        },
      });
      expect(KeyCombo.fromJson({'k': 0}), isNull);
      expect(KeyCombo.fromJson({'m': 1}), isNull);
      expect(KeyCombo.fromJson('junk'), isNull);
    });

    test('契约：applyJson / KeyCombo.fromJson 不得再裸 cast num', () {
      final src = _code('lib/app_settings.dart');
      expect(RegExp(r'as\s+num\??').hasMatch(src), isFalse,
          reason: '启动路径上的裸 cast 会让整份设置退回默认');
      expect(src.contains('intOf('), isTrue);
    });
  });

  group('第三十批（0.9.234）：列表 / 布尔 / 非有限数值', () {
    test('listOf 只认列表，其余一律空（不抛）', () {
      // `(j['works'] as List?) ?? const []` 判的是 null：字段是字符串/对象时
      // 照样抛 _TypeError。基础库页作者与作品两栏会一起停在加载中。
      expect(listOf([1, 2]).length, 2);
      expect(listOf('a'), isEmpty);
      expect(listOf({'k': 1}), isEmpty);
      expect(listOf(null), isEmpty);
      expect(listOf(42), isEmpty);
      expect(listLengthOf([1, 2, 3]), 3);
      expect(listLengthOf('a'), 0);
      expect(listLengthOf(null), 0);
    });

    test('stringsOf 跳过对象条目，不把 {a: 1} 插值进列表', () {
      expect(stringsOf(['a', ' b ', null, {'x': 1}, ['y'], 3]),
          ['a', 'b', '3']);
      expect(stringsOf('a'), isEmpty);
      expect(stringsOf(null), isEmpty);
    });

    test('契约：lib/ 内不得再写 as List（写坏字段会让整块界面卡在加载中）', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lines = File(f.path).readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final t = lines[i].trimLeft();
          if (t.startsWith('//')) continue;
          if (RegExp(r'\bas\s+List\b').hasMatch(t)) {
            offenders.add('${f.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty, reason: '列表字段只用 listOf/stringsOf：$offenders');
    });
  });

  group('非有限数值：JSON 的 1e999 会让启动路径抛异常', () {
    test('intOrNull 对 infinity/NaN 返回 null，不当成 0', () {
      // jsonDecode('{"x":1e999}') 得到 double.infinity，而 infinity.toInt()
      // 抛 Unsupported operation。0 是合法值（0 号键、0 权重），不能拿来做失败标记。
      expect(intOrNull(double.infinity), isNull);
      expect(intOrNull(double.negativeInfinity), isNull);
      expect(intOrNull(double.nan), isNull);
      expect(intOrNull(0), 0);
      expect(intOrNull('12'), 12);
      expect(intOrNull('x'), isNull);
      expect(doubleOrNull(double.infinity), isNull);
      expect(doubleOrNull(0.0), 0.0);
      expect(numOrNull(double.nan), isNull);
      expect(numOrNull(2.5), 2.5);
    });

    test('等级权重是 1e999 时回默认，不抛', () {
      AuthorGrade.applyJson(<String, dynamic>{
        'play': double.infinity,
        'drop': 10,
        'work': 2,
        't': [100, 500, 2000, 8000],
      });
      expect(AuthorGrade.playWeight, AuthorGrade.defaultPlayWeight);
      expect(AuthorGrade.dropWeight, 10);
    });
  });

  group('布尔解析：true / 1 / "true" / "yes" 是同一个答案', () {
    test('boolOrNull 三态明确', () {
      for (final t in [true, 1, 'true', ' TRUE ', 'yes', 'on']) {
        expect(boolOrNull(t), isTrue, reason: '$t 应为真');
      }
      for (final f in [false, 0, 'false', '0', 'no', 'off']) {
        expect(boolOrNull(f), isFalse, reason: '$f 应为假');
      }
      expect(boolOrNull(null), isNull);
      expect(boolOrNull('maybe'), isNull);
      expect(boolOrNull({'a': 1}), isNull);
      expect(boolOrNull(double.infinity), isNull);
    });

    test('boolOf 无法判断时用 fallback', () {
      expect(boolOf('maybe'), isFalse);
      expect(boolOf('maybe', true), isTrue);
      expect(boolOf('1'), isTrue);
    });

    test('关注记录 f 写成 1/true/"1" 都算已看完', () {
      expect(WatchProgress.fromJson({'p': 1000, 'd': 5000, 'f': 1})!.done,
          isTrue);
      expect(WatchProgress.fromJson({'p': 1000, 'd': 5000, 'f': true})!.done,
          isTrue);
      expect(WatchProgress.fromJson({'p': 1000, 'd': 5000, 'f': '1'})!.done,
          isTrue);
      expect(WatchProgress.fromJson({'p': 1000, 'd': 5000, 'f': 0})!.done,
          isFalse);
    });
  });
}
