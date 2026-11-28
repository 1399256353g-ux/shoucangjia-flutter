/// 说明文字的唯一样式（第一百一十九批 · 0.9.366）。
///
/// 为什么要有这个文件：设置页/对话框里那些「这段东西是什么意思」的灰色小字，
/// 在 54 个地方各写了一遍：
///
/// ```
/// TextStyle(fontSize: 12, color: Colors.grey)          // 44 处
/// const TextStyle(fontSize: 12, color: Colors.grey)    // 12 处
/// TextStyle(color: Colors.grey, fontSize: 12)          //  2 处（只是参数顺序不同）
/// ```
///
/// 三份写法渲染结果**完全一致**，所以一直没人发现它是三份。但「同一段说明
/// 文字」在浅色主题（`daylight`，背景 `0xFFF5F7FB`）下用硬编码 `Colors.grey`
/// 本来就是可读性下限；等哪天要按主题换色、要统一加行高、要把说明文字降到
/// 11dp，就得到 58 个地方逐个找——漏掉的那处不会报错，只会跟旁边不一样。
///
/// 这里**只**收「12dp / 灰」这一种。刻意不动 11dp 那一批（`fontSize: 11`，
/// 28 处）：它们是列表项的副标题/计数行，字号不同、语义不同，合并会改观感。
/// 也不收 `Colors.grey.shade400` 这类派生色——那是明度微调，不是同一样式。
///
/// 值与原来逐字一致（12dp、`Colors.grey`），所以这次收口**不改任何观感**。
library;

import 'package:flutter/material.dart';

/// 说明文字（灰色 12dp）。作为 `const` 变量可直接用在 `const` 构造里。
const TextStyle kHintTextStyle = TextStyle(fontSize: 12, color: Colors.grey);
