import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_state.dart';

/// 播放显示层单一真源契约（0.9.190）。
///
/// 相位机接线第 3 步：显示层（暂停图标 / 非全屏暂停三角 / 任务栏播放键）
/// 不再直接读用户意图 `paused`，而是读相位派生出来的 `_showsPaused`。
///
/// 为什么这是结构问题：`paused` 回答「用户想不想播」，相位回答「实际有没有
/// 在播」。两者在自救补 play、后台恢复、失败重试等路径上短时不一致，显示层
/// 各画各的，就会出现「暂停键显示成播放键但画面还在走」这类自相矛盾——
/// 这正是 owner 反复报的「暂停不灵敏 / 状态自己乱跳」。
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

  group('暂停显示派生自相位', () {
    test('_showsPaused 派生自 PlaybackPhase.showsPaused', () {
      final page = playerPageSource();
      expect(page.contains('bool get _showsPaused => _phase.showsPaused;'), isTrue,
          reason: '暂停显示必须派生自相位，不能另立布尔量');
    });

    test('渲染层不得再用原始 paused 决定图标/浮层/任务栏状态', () {
      final page = playerPageSource();
      // 这三个都是纯显示位：中央大圆钮图标、非全屏暂停三角、任务栏播放键。
      expect(page.contains('Icon(paused ? Icons.play_arrow'), isFalse,
          reason: '中央大圆钮图标必须读 _showsPaused');
      expect(page.contains('!fs && !broken && paused)'), isFalse,
          reason: '非全屏暂停三角必须读 _showsPaused');
      expect(page.contains('TaskbarPlayButton(paused: paused'), isFalse,
          reason: '任务栏播放键必须读 _showsPaused');
    });
  });

  group('缓冲态单一真源', () {
    test('_buffering 派生自相位，不再有 ValueNotifier 双写', () {
      final page = playerPageSource();
      expect(page.contains('bool get _buffering => _phase.showsBuffering;'),
          isTrue,
          reason: '缓冲态必须派生自相位');
      expect(RegExp(r'_buffering\s*=(?![=>])').hasMatch(page), isFalse,
          reason: '不得再出现 _buffering 的赋值（相位推进即缓冲态）');
      expect(page.contains('_bufferingVN'), isFalse,
          reason: '缓冲 ValueNotifier 应已删除');
      expect(page.contains('_slowBufferVN'), isFalse,
          reason: '弱网缓冲 ValueNotifier 应已删除');
    });

    test('缓冲事件只喂相位，监听回调不自己改状态', () {
      final page = playerPageSource();
      final start = page.indexOf('p.stream.buffering.listen');
      expect(start, greaterThan(0), reason: '缓冲监听找不到');
      final body = page.substring(start, start + 600);
      expect(body.contains('_feed(b ? PlaybackEvent.bufferStart'),
          isTrue,
          reason: '缓冲起止必须走相位事件');
      expect(body.contains('_buffering ='), isFalse,
          reason: '监听回调里不得再直接写缓冲布尔量');
    });

    test('弱网判定只是「同一缓冲相位的时长」，不改变相位', () {
      final page = playerPageSource();
      // 计时器里只允许置 _slowBuffer，不允许喂事件或改相位。
      final start = page.indexOf('Timer(slowBufferThreshold');
      expect(start, greaterThan(0), reason: '弱网计时器找不到');
      final body = page.substring(start, start + 320);
      expect(body.contains('_feed('), isFalse,
          reason: '弱网计时不得推进相位（否则又变成兜底定时器）');
      expect(body.contains('_phase ='), isFalse,
          reason: '弱网计时不得直接改相位');
    });

    test('相位视图职责分离：缓冲相位不等于暂停也不等于 loading', () {
      expect(PlaybackPhase.buffering.showsBuffering, isTrue);
      for (final p in PlaybackPhase.values) {
        if (p == PlaybackPhase.buffering) continue;
        expect(p.showsBuffering, isFalse, reason: 'phase=$p');
      }
      expect(PlaybackPhase.buffering.showsPaused, isFalse);
      expect(PlaybackPhase.buffering.showsLoading, isFalse);
    });
  });
}
