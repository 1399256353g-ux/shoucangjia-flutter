import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_state.dart';

/// 暂停意图单一真源契约（0.9.189）。
///
/// 相位机（[PlaybackPhase]）回答「实际有没有在播」，播放页的暂停意图回答
/// 「用户想不想播」。0.9.188 之前后者就是一个公开可写的 `bool paused`，
/// 播放页里有 15 处各自赋值：用户点击、切后台、失败、软解重试、打开新条、
/// 自救补 play、从头播放、继续观看……谁都能盖住状态，`_feed` 的自检因此
/// 长期被假告警淹没——这正是 owner 反复反馈「暂停不灵敏 / 状态自己乱跳」
/// 的结构性来源。
///
/// 现在字段改名 `_pausedIntent` 并私有化，对外只保留只读 getter。任何人
/// 想改它，只能改这个字段本身，且必须想清楚是「用户/后台/失败」哪一类
/// 意图。下面的测试钉住这条边界：整页不得再出现对 `paused` 的赋值。
void main() {
  final String src = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

  String playerPageSource() {
    const marker = 'class _PlayerPageState extends State<PlayerPage>';
    final start = src.indexOf(marker);
    expect(start, greaterThan(0), reason: '播放页 State 找不到，测试需同步更新');
    final rest = src.substring(start + marker.length);
    final end = rest.indexOf('\nclass ');
    return end < 0 ? rest : rest.substring(0, end);
  }

  /// 去掉纯注释行（注释里举例说明旧写法是允许的），再去掉字符串字面量
  /// （日志里的 `paused=$paused` 是插值读取，不是赋值，不能算写入点）。
  String executableLines(String page) => page
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n')
      .replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''")
      .replaceAll(RegExp(r'"(?:[^"\\]|\\.)*"'), '""');

  group('播放页暂停意图单一真源', () {
    test('暂停意图是私有字段 + 只读 getter', () {
      final page = playerPageSource();
      expect(page.contains('bool _pausedIntent = false;'), isTrue,
          reason: '暂停意图必须存在且私有');
      expect(page.contains('bool get paused => _pausedIntent;'), isTrue,
          reason: '对外必须只读，语义保持 paused');
      expect(RegExp(r'\bbool paused\s*=').hasMatch(page), isFalse,
          reason: '不得再出现公开可写的 bool paused 字段');
    });

    test('整页没有任何对 paused 的赋值（写入点只走 _pausedIntent）', () {
      final code = executableLines(playerPageSource());
      // 拦 `paused = ...`，但放过 `== paused`、`!paused`、命名参数 `paused:`、
      // 以及 `.paused`（枚举成员如 PlaybackPhase.paused）。
      final assigns = RegExp(r'(?<![=\w.])(_?)paused\s*=(?!=)')
          .allMatches(code)
          .map((m) => code.substring(
              (m.start - 40).clamp(0, code.length),
              (m.end + 20).clamp(0, code.length)))
          .where((ctx) => !ctx.contains('_pausedIntent'))
          .toList();
      expect(assigns, isEmpty,
          reason: '这些位置仍在直接改 paused：\n${assigns.join('\n---\n')}');
    });

    test('暂停意图与相位职责分离：相位只管「在不在播」', () {
      // 暂停相位就是 paused；失败相位不算在播；其余相位都不能显示成暂停。
      expect(PlaybackPhase.paused.showsPaused, isTrue);
      expect(PlaybackPhase.failed.showsPaused, isTrue);
      for (final p in PlaybackPhase.values) {
        if (p == PlaybackPhase.paused || p == PlaybackPhase.failed) continue;
        expect(p.showsPaused, isFalse, reason: 'phase=$p');
      }
      // 暂停意图不参与 loading 判定，避免两套说法又分叉。
      expect(PlaybackPhase.paused.showsLoading, isFalse);
    });
  });
}
