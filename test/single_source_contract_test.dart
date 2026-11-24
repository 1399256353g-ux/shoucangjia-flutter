import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 单源契约（owner 2026-11-24，第五批「测试为不存在的界面作证」）。
///
/// 上一批（0.9.202）删掉的是**完全没人用的替身**。这一批不同：删的是
/// **真实路径已经自己复制了一份**的函数与常量——测试还在断言那个替身，
/// 而真正跑的那条路上写着同样的数字/同样的三元表达式。测试全绿，但它断言
/// 的从来不是产品里的那条线。
///
/// 所以本文件钉的不是"某个名字不能存在"，而是"这段判定只能有一处实现"：
///  1. 音量图标档位：任务栏按钮、拖动浮层、桌面音量模块共用 volumeIconFor；
///  2. 进度条左右边距：真实布局必须引用 kProgressSideMargin；
///  3. 长按阈值：只有 StageLongPressTracker 判定，不得再有独立的判定函数。
void main() {
  final root = Directory('lib');

  String readLib(String name) => File('${root.path}/$name').readAsStringSync();

  String libSourceAll() => root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  group('音量图标：判定只有一处', () {
    test('volumeIconFor 是唯一档位判定', () {
      final src = libSourceAll();
      expect(src.contains('VolumeIcon volumeIconFor('), isTrue);
      // 旧的字符串档位替身不得复活（它只返回 'mute'/'down'/'up' 字符串，
      // 没有任何图标消费方，测试却断言它有四种取值）。
      expect(src.contains('volumeIconLevel'), isFalse);
    });

    test('真实布局里不再手写 muted/volume 三元表达式选图标', () {
      // 三处读数的旧写法都是 `Icons.volume_off : ... volume < 50
      // ? Icons.volume_down : Icons.volume_up`。图标映射只允许出现在
      // volumeIconData 里。
      final icons = RegExp(r'Icons\.volume_(off|down|up)');
      for (final name in ['main.dart', 'player_controls.dart']) {
        final hits = icons.allMatches(readLib(name)).length;
        final expected = name == 'player_controls.dart' ? 3 : 0;
        expect(hits, expected,
            reason: '$name 里 Icons.volume_like 出现次数应为 $expected');
      }
      // 两处调用点都必须走共用函数。
      expect(readLib('main.dart').contains('volumeIconFor('), isTrue);
      expect(readLib('player_controls.dart').contains('volumeIconFor('), isTrue);
    });
  });

  group('进度条边距：真实布局引用常量', () {
    test('kProgressSideMargin 被播放页进度行使用', () {
      final main = readLib('main.dart');
      expect(main.contains('kProgressSideMargin'), isTrue,
          reason: '真实布局必须先引用常量，而不是再写一个 12');
      // 旧的写死写法（`pad.left + 12, right: pad.right + 12`）不得回来。
      expect(
        RegExp(r'left:\s*pad\.left\s*\+\s*12\s*,\s*right:\s*pad\.right\s*\+\s*12')
            .hasMatch(main),
        isFalse,
      );
    });
  });

  group('长按阈值：只有跟踪器判定', () {
    test('stageLongPressQualifies 不得复活', () {
      final src = libSourceAll();
      expect(src.contains('stageLongPressQualifies'), isFalse,
          reason: '长按判定只走 StageLongPressTracker.shouldFire');
      expect(src.contains('class StageLongPressTracker'), isTrue);
    });

    test('shouldFire 是唯一比较 nowMs - start 与 holdMs 的地方', () {
      final controls = readLib('player_controls.dart');
      expect(controls.contains('nowMs - start >= holdMs'), isTrue);
    });
  });

  group('编码降级：删掉的替身不得复活', () {
    test('otherDecodeMode / softwareDecodeNotice 不再定义', () {
      final src = libSourceAll();
      expect(src.contains('otherDecodeMode'), isFalse);
      expect(src.contains('softwareDecodeNotice'), isFalse);
      // 真实路径：shouldRetryWithSoftwareDecode + _retryWithSoftwareDecode。
      expect(src.contains('shouldRetryWithSoftwareDecode'), isTrue);
    });
  });

  group('预载宽度：删掉的常量不得复活', () {
    test('kPlayerPreloadWidth 不再存在（预载页与正式海报同宽）', () {
      final src = libSourceAll();
      expect(src.contains('kPlayerPreloadWidth'), isFalse,
          reason: '邻页与正式海报必须同一个 URL 宽度才命中同一缓存键');
      expect(readLib('main.dart').contains('kPlayerImageWidth'), isTrue);
    });
  });

  group('暂停提示：无消费者的动画不得复活', () {
    test('_playHintAnim / kPlayHintFadeMs / playHintOpacityAt 都已消失', () {
      final src = libSourceAll();
      expect(src.contains('_playHintAnim'), isFalse);
      expect(src.contains('kPlayHintFadeMs'), isFalse);
      expect(src.contains('playHintOpacityAt'), isFalse);
      // 真实暂停提示：非全屏暂停期间常显的半透明播放图标。
      expect(src.contains('play_arrow_rounded'), isTrue);
    });
  });
}
