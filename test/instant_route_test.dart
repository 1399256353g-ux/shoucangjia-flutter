import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/instant_route.dart';

/// 播放页进场必须是零时长转场：转场淡入会在海报已就绪时把整页再压暗一次，
/// 实测就是 0.9.147 记录的那 ~100ms 暗段。这里锁住语义，避免以后被改回
/// MaterialPageRoute。
void main() {
  test('instantRoute 进出场都是零时长且不透明', () {
    final r = instantRoute<void>((_) => const SizedBox.shrink());
    expect(r.transitionDuration, Duration.zero);
    expect(r.reverseTransitionDuration, Duration.zero);
    expect(r.opaque, isTrue);
  });

  testWidgets('instantRoute 的 transitionsBuilder 直接返回 child（不叠任何动画层）',
      (tester) async {
    final r = instantRoute<void>((_) => const SizedBox.shrink());
    const child = SizedBox(key: ValueKey('child'));
    late Widget built;
    await tester.pumpWidget(Builder(builder: (context) {
      built = r.transitionsBuilder(
        context,
        const AlwaysStoppedAnimation<double>(0),
        const AlwaysStoppedAnimation<double>(0),
        child,
      );
      return const SizedBox.shrink();
    }));
    expect(identical(built, child), isTrue);
  });

  testWidgets('instantRoute 推入后同一帧即可看到页面（无过渡动画）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context)
              .push(instantRoute<void>((_) => const Text('player'))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    // 零时长转场：推入后的第一帧就已经是新页面，不需要再 pump 过渡。
    expect(find.text('player'), findsOneWidget);
    expect(find.text('open'), findsNothing);
  });
}
