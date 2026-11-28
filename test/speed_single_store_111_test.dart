import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/collection_sync.dart';
import 'package:shoucangjia/playback_prefs.dart';

/// 第一百一十一批（0.9.356）：**同一个用户可调的量有两个落盘处**。
///
/// 设置页「默认播放倍速」写 `AppSettings.defaultSpeed`（`app_settings_v1`），
/// 播放页恢复却读 `playback_prefs_v1` 的 `speed`——本机从来没有人写那个键，
/// 所以它恒为默认 1.0：设置页选的倍速一次都不生效，而副标题还写着
/// 「进入播放器时自动应用」。
///
/// 这批的规则：**一个量只有一个落盘处**。倍速归 `AppSettings.defaultSpeed`，
/// `PlaybackPrefs` 只记连播/循环/乱序。
String codeOf(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  setUp(AppSettings.resetDefaults);

  group('1. PlaybackPrefs 不再持有倍速', () {
    test('类里没有 speed 字段，toJson 不写 speed 键', () {
      final src = codeOf('lib/playback_prefs.dart');
      expect(src.contains('final double speed'), isFalse,
          reason: '倍速在 PlaybackPrefs 里活着，就一定会有人再写第二份');
      const p = PlaybackPrefs();
      expect(p.toJson().containsKey('speed'), isFalse);
    });

    test('旧 payload 里的 speed（含坏值）被忽略，不连累其它字段', () {
      for (final old in <Object?>[1.5, 'fast', 99.0, -5, null]) {
        final p = PlaybackPrefs.fromJson(<String, dynamic>{
          'speed': old,
          'shuffle': true,
          'autoplay': false,
        });
        expect(p.shuffle, isTrue, reason: '旧 speed=$old 连累乱序开关');
        expect(p.link.autoplay, isFalse, reason: '旧 speed=$old 连累连播开关');
      }
    });

    test('copyWith 已删（零调用点，留着就是「改一处还有第二处」的入口）', () {
      final src = codeOf('lib/playback_prefs.dart');
      expect(src.contains('copyWith('), isFalse);
    });
  });

  group('2. 播放页：读 AppSettings、写 AppSettings', () {
    String player() {
      final src = codeOf('lib/main.dart');
      final start = src.indexOf('class _PlayerPageState');
      expect(start, greaterThan(0), reason: '找不到 _PlayerPageState');
      return src.substring(start);
    }

    test('恢复播放设置时不覆盖倍速，倍速来自 AppSettings.defaultSpeed', () {
      final body = player();
      final start = body.indexOf('Future<void> _restorePlaybackPrefs()');
      expect(start, greaterThan(0));
      final end = body.indexOf('void _persistPlaybackPrefs()', start);
      expect(end, greaterThan(start));
      final fn = body.substring(start, end);
      expect(fn.contains('speed = p.speed'), isFalse,
          reason: '仍在用 prefs 里的倍速覆盖设置页的值');
      expect(fn.contains('AppSettings.defaultSpeed'), isTrue,
          reason: '倍速应来自设置页写的那个唯一落盘处');
    });

    test('落盘播放设置时不带倍速', () {
      final body = player();
      final start = body.indexOf('void _persistPlaybackPrefs()');
      expect(start, greaterThan(0));
      final fn = body.substring(start, start + 600);
      expect(fn.contains('speed: speed'), isFalse,
          reason: 'PlaybackPrefs 里已没有 speed 字段，这里不该再塞');
      expect(fn.contains('link: _link'), isTrue);
      expect(fn.contains('shuffle: shuffle'), isTrue);
    });

    test('播放页改倍速就是改「下次进页的默认倍速」', () {
      final body = player();
      final start = body.indexOf('void setSpeed(double value)');
      expect(start, greaterThan(0));
      final fn = body.substring(start, start + 700);
      expect(fn.contains('AppSettings.defaultSpeed = next'), isTrue,
          reason: 'owner 要的是「沿用上次的播放设置」，播放中改的倍速也算');
      expect(fn.contains('AppSettings.save()'), isTrue,
          reason: '不落盘的话重启后又回到旧值');
    });
  });

  group('3. 倍速选项只有一份清单', () {
    test('kPlaybackSpeeds 是唯一清单，两处都用它', () {
      expect(kPlaybackSpeeds, const [0.75, 1.0, 1.25, 1.5, 2.0]);
      final main = codeOf('lib/main.dart');
      // 旧写法：两处各写一遍 `[0.75, 1.0, 1.25, 1.5, 2.0]` 字面量。
      final literals =
          RegExp(r'\[0\.75,\s*1\.0,\s*1\.25,\s*1\.5,\s*2\.0\]').allMatches(main);
      expect(literals.length, lessThanOrEqualTo(0),
          reason: '仍有 ${literals.length} 处倍速字面量清单，改一处就会漂移');
      expect(main.contains('kPlaybackSpeeds'), isTrue,
          reason: '设置页与播放页菜单应共用 kPlaybackSpeeds');
    });

    test('设置页倍速文案与播放页同一个出口（speedLabel）', () {
      final src = codeOf('lib/main.dart');
      final start = src.indexOf('默认播放倍速');
      expect(start, greaterThan(0));
      final seg = src.substring(start, start + 900);
      expect(seg.contains("Text('\${s}x')"), isFalse,
          reason: '设置页自己拼 `1.0x`，播放页用 speedLabel，两页两种格式');
      expect(seg.contains('speedLabel('), isTrue);
    });
  });

  group('4. 同步源面板的提示语不再插目录原名', () {
    test('syncUnitLabel 去序号、空名回落 rel 末段', () {
      expect(syncUnitLabel('(2) 丝', '(2) douyin/(2) 丝'), '丝');
      expect(syncUnitLabel('（02）南宁', 'x/(02) 南宁'), '南宁');
      // 只给 rel 时取末段，不把整条相对路径塞进提示语。
      expect(syncUnitLabel('', '(2) douyin/(5) 其他'), '其他');
      expect(syncUnitLabel('  ', ''), '该单元库');
    });

    test('面板文案走 syncUnitLabel，不再裸插 unitName', () {
      final src = codeOf('lib/collection_sync_panel.dart');
      expect(src.contains(r'与「${widget.unitName}」同名'), isFalse,
          reason: '目录原串会带着 (2) 出现在提示里，与同一页的标题两个说法');
      expect(src.contains('syncUnitLabel('), isTrue);
      // 匹配仍只走 syncUnitKey（名字归一后比较）。
      final sync = codeOf('lib/collection_sync.dart');
      expect(sync.contains('keys.contains(syncUnitKey(r.name))'), isTrue);
    });
  });

  group('5. 已删的死实现不得复活', () {
    test('source_lib.normalizeLibLabel 不得回来（lib/ 零调用点）', () {
      final src = codeOf('lib/source_lib.dart');
      expect(src.contains('String normalizeLibLabel('), isFalse);
      final whole = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      expect(whole.contains('normalizeLibLabel('), isFalse,
          reason: 'lib/ 内仍有调用点，删函数会编译失败，说明还有第二份规则在用');
    });
  });
}
