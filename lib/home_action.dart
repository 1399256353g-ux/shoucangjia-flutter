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
