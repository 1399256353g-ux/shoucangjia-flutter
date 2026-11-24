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
import 'package:shoucangjia/json_num.dart';

String _code(String path) => File(path)
    .readAsStringSync()
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
}
