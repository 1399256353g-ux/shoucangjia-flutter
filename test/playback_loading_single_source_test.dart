import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/playback_state.dart';

/// 起播 loading 单一真源契约（0.9.188）。
///
/// 以前 `loading` 是播放页自己的布尔量，在 open 命中 / 未命中 / 失败 /
/// 不可播放 / 重试 / 软解重建六处各自赋值；与相位并行推进时只能靠
/// `_feed` 的比对去「发现」两套说法冲突——那是拿检测兜住结构问题。
///
/// 现在 `loading` 直接派生自 [PlaybackPhase.showsLoading]，写入点必须为零。
/// 若有人再次加回 `loading = …` 赋值，这条测试立刻失败：相位会重新变成
/// 一份只写日志的副本，而界面回到各自拍脑袋。
void main() {
  final String src = File('lib/main.dart').readAsStringSync();

  /// 播放页 State 的源码片段（从类声明到下一个顶层类之前）。
  String playerPageSource() {
    const marker = 'class _PlayerPageState extends State<PlayerPage>';
    final start = src.indexOf(marker);
    expect(start, greaterThan(0), reason: '播放页 State 找不到，测试需同步更新');
    final rest = src.substring(start + marker.length);
    final end = rest.indexOf('\nclass ');
    return end < 0 ? rest : rest.substring(0, end);
  }

  group('播放页 loading 单一真源', () {
    test('loading 是相位派生的 getter，不再是可变字段', () {
      final page = playerPageSource();
      expect(page.contains('bool get loading => _phase.showsLoading'), isTrue,
          reason: 'loading 必须派生自 PlaybackPhase.showsLoading');
      expect(RegExp(r'\bbool loading\s*=').hasMatch(page), isFalse,
          reason: '不得再出现独立的 bool loading 字段');
    });

    test('播放页内没有任何 loading 赋值（写入点必须归零）', () {
      // 先剔掉纯注释行与 getter 自身：注释里举例说明旧写法是允许的，
      // 被拦的只能是真正会执行到的赋值语句。
      final page = playerPageSource()
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            if (t.startsWith('//')) return false;
            return !t.contains('bool get loading =>');
          })
          .join('\n');
      // 允许 `== loading`、`loading:` 命名参数，只拦赋值语句。
      final assigns = RegExp(r'(?<![=\w.])loading\s*=(?!=)')
          .allMatches(page)
          .map((m) => page.substring((m.start - 40).clamp(0, page.length),
              (m.end + 20).clamp(0, page.length)))
          .toList();
      expect(assigns, isEmpty,
          reason: '这些位置仍在直接改 loading：\n${assigns.join('\n---\n')}');
    });

    test('相位到 loading 的映射仍是 idle/opening', () {
      expect(PlaybackPhase.idle.showsLoading, isTrue);
      expect(PlaybackPhase.opening.showsLoading, isTrue);
      for (final p in PlaybackPhase.values) {
        if (p == PlaybackPhase.idle || p == PlaybackPhase.opening) continue;
        expect(p.showsLoading, isFalse, reason: 'phase=$p');
      }
    });
  });
}
