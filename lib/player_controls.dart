/// M2/M3：播放页底部任务栏的通用控件。
///
/// M2 要求「全屏且功能区呼出时」任务栏出现播放/暂停与横竖屏切换；
/// M3 要求 Windows 保持原交互——有播放/暂停（状态双向同步），但不得
/// 出现横竖屏按钮。这里把纯逻辑与两个按钮拆出来，便于单元/组件测试。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 屏幕方向（只区分竖屏/横屏，横屏两向都接受）。
enum ScreenMode { portrait, landscape }

/// 由窗口尺寸判定当前方向；正方形按竖屏处理。
ScreenMode screenModeOf(Size size) =>
    size.width > size.height ? ScreenMode.landscape : ScreenMode.portrait;

/// 切换目标：竖屏 ↔ 横屏。
ScreenMode toggledMode(ScreenMode mode) =>
    mode == ScreenMode.portrait ? ScreenMode.landscape : ScreenMode.portrait;

/// 目标方向对应的系统方向白名单。
List<DeviceOrientation> orientationsFor(ScreenMode mode) =>
    mode == ScreenMode.portrait
        ? const [DeviceOrientation.portraitUp]
        : const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ];

/// 任务栏播放/暂停按钮：图标与提示随 [paused] 实时变化（M2/M3）。
class TaskbarPlayButton extends StatelessWidget {
  const TaskbarPlayButton({
    super.key,
    required this.paused,
    required this.onPressed,
  });

  final bool paused;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('taskbar-play'),
      onPressed: onPressed,
      tooltip: paused ? '播放' : '暂停',
      icon:
          Icon(paused ? Icons.play_arrow : Icons.pause, color: Colors.white70),
    );
  }
}

/// 任务栏横竖屏切换按钮：只能在移动端出现（M2），桌面端不渲染。
class TaskbarRotateButton extends StatelessWidget {
  const TaskbarRotateButton({
    super.key,
    required this.mode,
    required this.onPressed,
  });

  final ScreenMode mode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final toLandscape = mode == ScreenMode.portrait;
    return IconButton(
      key: const Key('taskbar-rotate'),
      onPressed: onPressed,
      tooltip: toLandscape ? '横屏' : '竖屏',
      icon: Icon(
        toLandscape ? Icons.screen_lock_landscape : Icons.screen_lock_portrait,
        color: Colors.white70,
      ),
    );
  }
}

/// 组件渲染条件：仅 Android/iOS 显示横竖屏按钮；桌面端（含 Windows）不显示。
bool showRotateButton({required bool isAndroid, required bool isIOS}) =>
    isAndroid || isIOS;

/// M3：任务栏平台策略。
///
/// Windows/桌面端保持原交互：播放/暂停按钮必须常驻任务栏，横竖屏按钮
/// 一律不渲染；Android/iOS 只显示横竖屏按钮（O2：手机端播放/暂停改由
/// 画面中央大圆钮承担，任务栏不再重复放置）。把规则集中在这里，避免
/// 调用点各自判断导致桌面端误出横屏按钮。
class TaskbarPolicy {
  const TaskbarPolicy({required this.isAndroid, required this.isIOS});

  final bool isAndroid;
  final bool isIOS;

  bool get showPlayPause => !(isAndroid || isIOS);

  bool get showRotate => showRotateButton(isAndroid: isAndroid, isIOS: isIOS);
}

/// 按当前平台生成任务栏策略。
TaskbarPolicy taskbarPolicyFor({
  required bool isAndroid,
  required bool isIOS,
}) =>
    TaskbarPolicy(isAndroid: isAndroid, isIOS: isIOS);
