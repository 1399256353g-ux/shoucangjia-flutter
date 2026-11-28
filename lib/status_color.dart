/// 状态色（成功 / 失败 / 警告）的唯一来源。
///
/// 收口前 `Colors.green` / `Colors.redAccent` / `Colors.orange` 这三个字面量
/// 在 `connection_status` / `main` / `unit_crawler_page` 里各写一遍，共 13 处。
/// 它们形态一致（所以没坏），但都是同一件事的多份实现：想统一「成功绿」的
/// 色号，或把警告从橙改成琥珀，就得逐个找；漏改的那一处不会报错，只是
/// 同一屏上两个「正常」显示成两种绿。
///
/// 与 `toast.dart` 的 `kToastErrorBackground` 分开：那是**提示条底色**（深红
/// 填充），这里是**文字/图标前景色**（亮色描边）。两者用途不同，不能合并
/// ——合并会让「提示条红底」和「错误文字红字」互相牵制。
///
/// 三个值刻意保持与被替换的字面量**完全一致**，所以这次收口不改变任何观感。
library;

import 'package:flutter/material.dart';

/// 成功 / 已连接 / 通过。
const Color kStatusOk = Colors.green;

/// 失败 / 已断连 / 校验不通过。
const Color kStatusBad = Colors.redAccent;

/// 警告 / 功能不可用 / 需要关注但不算失败。
const Color kStatusWarn = Colors.orange;

/// 状态底纹：把状态色压到 12% 作背景（横幅/提示块）。
///
/// 只此一处定义 `0.12`：此前 `unit_crawler_page` 与 `main` 的横幅各写一遍，
/// 改一个不亮另一个就会「同一页两种底色浓度」。
Color statusTint(Color c) => c.withValues(alpha: 0.12);
