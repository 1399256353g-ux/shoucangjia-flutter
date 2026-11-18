import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 桌面端 Esc 返回的统一兜底（Windows 上「部分页面 Esc 失效」的修复）。
///
/// 放在 `MaterialApp.builder` 里、Navigator 之上：
/// - 比 `DefaultTextEditingShortcuts` 更靠近焦点节点，所以输入框有焦点时
///   也能先收到 Esc（TextField 默认把 Esc 映射成
///   `DoNothingAndStopPropagationTextIntent`，会拦掉 `MaterialApp.shortcuts`）；
/// - 播放页、按键绑定弹窗等自己处理 Esc 的节点更深，仍由它们先接管；
/// - 只有 `Navigator.canPop()` 为真时才消费事件，首页按 Esc 不吞键。
class EscBackScope extends StatelessWidget {
  final GlobalKey<NavigatorState> navKey;
  final Widget child;

  const EscBackScope({super.key, required this.navKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          final nav = navKey.currentState;
          if (nav != null && nav.canPop()) {
            nav.maybePop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
