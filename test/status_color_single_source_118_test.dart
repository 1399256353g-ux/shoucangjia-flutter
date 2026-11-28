// 第 118 批：状态色（成功/失败/警告）只有一处定义。
//
// 收口前 `Colors.green` / `Colors.redAccent` / `Colors.orange` 这三个字面量
// 在 `connection_status` / `main` / `unit_crawler_page` 里共写了 13 处。
// 形态一致所以没坏，但都是同一件事的多份实现：想统一色号就得逐个找，
// 漏改的那一处不会报错，只是同一屏上两个「正常」显示成两种绿。
//
// 本契约只钉三件事：
//  1. 三个状态色在 `status_color.dart` 里各定义一次，且取自 Material 同名色
//     （保证这次收口不改变任何观感）；
//  2. 横幅底纹的 `0.12` 只有 `statusTint` 一处；
//  3. 业务文件里不再出现裸的 `Colors.green` / `Colors.redAccent` /
//     `Colors.orange`（`Colors.orange.shade800` 这类派生色是另一回事，
//     只约束这三个被点名收口的基色）。
//
// 只读源码文本，不构建页面、不碰任何媒体内容。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/status_color.dart';

void main() {
  group('状态色只有一个来源', () {
    test('三个常量取自 Material 同名色（本次收口不改变观感）', () {
      expect(kStatusOk, Colors.green);
      expect(kStatusBad, Colors.redAccent);
      expect(kStatusWarn, Colors.orange);
    });

    test('statusTint 就是 12% 状态色', () {
      final t = statusTint(Colors.green);
      expect(t.a, closeTo(0.12, 1e-9));
      expect(t.r, closeTo(Colors.green.r, 1e-9));
    });

    test('status_color.dart 之外没有裸的三个基色', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('status_color.dart'));
      final hits = <String>[];
      // 只要裸基色；`Colors.green.shade700` 这类派生色是另一种用途（明度微调），
      // 不在本契约范围内。
      final bare = RegExp(
          r'Colors\.(green|redAccent|orange)(?!\s*\.\s*shade)(?![A-Za-z])');
      for (final f in files) {
        final s = f.readAsStringSync();
        final m = bare.firstMatch(s);
        if (m != null) hits.add('${f.path}: ${m.group(0)}');
      }
      expect(hits, isEmpty,
          reason: '状态色回到了页面里：${hits.join(' / ')}'
              '（改 status_color.dart，不要各写一份）');
    });

    test('0.12 的横幅底纹只有 statusTint 一处', () {
      // 只查「箭头函数/调用里直接写 0.12」这种横幅写法，不误伤其它 alpha。
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      final hits = <String>[];
      for (final f in files) {
        final s = f.readAsStringSync();
        if (RegExp(r'withValues\(alpha: 0\.12\)')
            .allMatches(s)
            .isNotEmpty) {
          hits.add(f.path);
        }
      }
      expect(hits, ['lib/status_color.dart'],
          reason: '横幅底纹浓度散落在：$hits');
    });
  });
}
