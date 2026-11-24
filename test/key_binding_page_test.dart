import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/main.dart';

/// P0：按键绑定页的**可达性与组合键捕获**，用测试替代「只能 Windows 手测」。
///
/// 背景：队列长期写着「该页仅 Windows 可见（`main.dart:9140` 早返回），
/// Android/MuMu 永远进不去，只能 Windows 桌面版手测」。核对后 9140 是
/// `didChangeMetrics` 里的**窗口尺寸**门禁，按键页与 `_KeyCaptureDialog`
/// 里没有任何 `Platform.` 判断——那句注释把窗口门禁误当成页面门禁，
/// 于是这一项连着几轮被记成「不可验证」。
///
/// 本测试钉住两件事：
///  1. `KeyBindingsPage` 可以直接构建（没有平台门禁拦在 build 前面）；
///  2. 弹窗里按住修饰键再按主键，绑定表落的是**修饰键+主键**，
///     且单键绑定不被改动（冲突判定的核心语义）。
void main() {
  setUp(() => AppSettings.resetDefaults());

  testWidgets('按键绑定页直接可构建，每个动作都有一行且显示当前键', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: KeyBindingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('按键绑定'), findsOneWidget);
    // 每个动作都必须有可点的行（漏一个就等于那个动作永远改不了键）。
    for (final a in PlayerAction.values) {
      expect(find.text(actionLabels[a]!), findsOneWidget,
          reason: '缺少动作行：${a.name}');
    }
    // 当前绑定以 monospace 标签显示，默认 next = J。
    expect(find.text(AppSettings.keyLabel(PlayerAction.next)), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('弹窗捕获修饰键+主键：Ctrl+F 只改目标动作，不动单键 F', (tester) async {
    final fId = LogicalKeyboardKey.keyF.keyId;
    // 先把全屏绑到单键 F，用来验证 Ctrl+F 不会把它顶掉。
    AppSettings.bindCombo(PlayerAction.fullscreen, KeyCombo(fId));

    await tester.pumpWidget(const MaterialApp(home: KeyBindingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(actionLabels[PlayerAction.mute]!));
    await tester.pumpAndSettle();
    expect(find.textContaining('请按下要绑定的按键'), findsOneWidget);

    // 真实按住 Ctrl 再按 F：currentMods() 读的就是 HardwareKeyboard 状态。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // 弹窗关闭，静音落成 Ctrl+F。
    expect(find.textContaining('请按下要绑定的按键'), findsNothing);
    expect(AppSettings.keyBindings[PlayerAction.mute],
        KeyCombo(fId, KeyCombo.modCtrl));
    // 单键 F 仍然是全屏：组合键与单键在冲突判定上是两条不同的绑定。
    expect(AppSettings.actionForCombo(fId, 0), PlayerAction.fullscreen);
    expect(
        AppSettings.actionForCombo(fId, KeyCombo.modCtrl), PlayerAction.mute);
    // 绑定表仍然一对一（没有出现两个动作共用一个组合）。
    expect(AppSettings.keyBindings.values.toSet().length,
        PlayerAction.values.length);
  });

  testWidgets('保留键在弹窗里当场拒绝，弹窗不关闭、绑定不变', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: KeyBindingsPage()));
    await tester.pumpAndSettle();

    final before = Map<PlayerAction, KeyCombo>.of(AppSettings.keyBindings);
    await tester.tap(find.text(actionLabels[PlayerAction.mute]!));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // 还停在弹窗里，并给出原因（不是静默关闭）。
    expect(find.textContaining('请按下要绑定的按键'), findsNothing);
    expect(find.textContaining('不能绑定'), findsOneWidget);
    expect(AppSettings.keyBindings, before);
  });
}
