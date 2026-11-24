/// 全应用唯一的轻震动入口。
///
/// 背景：`main.dart` 里有一份 `hapticTap()`（12 处调用），
/// `author_letter_bar.dart` 里又私有复制了一份 `_hapticOnce()` 做同一件事
/// （`HapticFeedback.selectionClick()`）。同一个动作两处实现，改一处另一处
/// 不会跟上——正是本仓库反复清理的「真实路径自己写了一份」缺陷。
///
/// 桌面端（Windows/Linux/macOS）会静默失败，所以统一用 try 包住，
/// 调用点不需要再做平台判断。
library;

import 'package:flutter/services.dart';

/// 轻触反馈：按钮、开关、菜单动作等常见轻交互。
void hapticTap() {
  try {
    HapticFeedback.lightImpact();
  } catch (_) {}
}

/// 选择反馈：比 [hapticTap] 更轻，用于「切换到新档位/新字母」这类离散选择。
void hapticSelect() {
  try {
    HapticFeedback.selectionClick();
  } catch (_) {}
}
