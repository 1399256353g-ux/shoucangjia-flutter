import 'package:flutter/material.dart';

/// 深页面统一「返回主页」按钮：直接回到根路由（主页）。
class HomeAction extends StatelessWidget {
  const HomeAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '返回主页',
      icon: const Icon(Icons.home_outlined),
      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
    );
  }
}

/// 全屏深页面（播放页）用的「返回主页」按钮：黑底半透明，和播放页返回键
/// 同一套样式；显隐由调用方的功能区动画控制。
class HomeOverlayButton extends StatelessWidget {
  const HomeOverlayButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('home-overlay-btn'),
      tooltip: '返回主页',
      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
      icon: const Icon(Icons.home_outlined, color: Colors.white70),
      style: IconButton.styleFrom(backgroundColor: Colors.black45),
    );
  }
}
