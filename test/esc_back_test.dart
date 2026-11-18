import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/esc_back.dart';

/// L3（Windows Esc 返回在部分页面失效）：EscBackScope 必须比 TextField 的
/// 默认 Esc 映射更早收到按键，且首页不吞键。
void main() {
  Widget harness(GlobalKey<NavigatorState> navKey) => MaterialApp(
        navigatorKey: navKey,
        builder: (context, child) =>
            EscBackScope(navKey: navKey, child: child ?? const SizedBox()),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
            navKey.currentState?.maybePop();
            return null;
          }),
        },
        home: const _HomePage(),
      );

  testWidgets('输入框有焦点时 Esc 仍能返回上一页', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(harness(navKey));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);

    // 让 TextField 拿到焦点：这正是原先 Esc 失效的场景。
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('第二页'), findsNothing);
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets('没有可返回页面时 Esc 不被消费（不崩、不弹）', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(harness(navKey));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets('没有输入框焦点的页面 Esc 也能返回', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(harness(navKey));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsNothing);
  });
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const _SecondPage()),
          ),
          child: const Text('打开'),
        ),
      ),
    );
  }
}

class _SecondPage extends StatelessWidget {
  const _SecondPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('第二页')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: TextField(decoration: InputDecoration(hintText: '搜索')),
      ),
    );
  }
}
