import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_controls.dart';

void main() {
  group('P1 §1 互动栏：点赞删除后无残留', () {
    // owner 2026-11-23 删除双击点赞后，右侧互动栏整块成为无调用死代码；
    // 本组断言「不是忘了接，而是确实不再有这块 UI」，防止有人把它加回来
    // 又不接调用点，退化成只在测试里通过的假功能。
    test('lib/ 下没有任何互动栏调用点', () {
      final lib = Directory('lib');
      final hits = <String>[];
      for (final f in lib.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('player_controls.dart')) continue;
        final src = f.readAsStringSync();
        if (src.contains('PlayerInteractionRail')) hits.add(f.path);
      }
      expect(hits, isEmpty);
    });
  });

  group('P1 §2 信息区', () {
    test('文案最大宽度 = 屏宽 − 右栏 84 − 左边距 12', () {
      expect(infoAreaMaxWidth(375), 279);
      expect(infoAreaMaxWidth(320), 224);
      expect(infoAreaMaxWidth(0), 0);
      expect(infoAreaMaxWidth(double.nan), 0);
      expect(kInfoLeftMargin, 12);
      expect(kMusicIconSize, 16);
      expect(kMusicIconGap, 6);
      expect(kMusicFontSize, 13);
      expect(kInfoSecondaryColor, const Color(0xE6FFFFFF));
      expect(kMarqueeSpeed, 40);
      expect(kMarqueePause, const Duration(seconds: 2));
      expect(kInfoBottomGap, 12);
    });

    test('跑马灯位移：滚动 40px/s，到末尾停 2s 后重来', () {
      // 文本 140，可视 100 → 距离 40 → 滚动 1s，周期 3s。
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 0, textWidth: 140, viewWidth: 100),
          0);
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 0.5, textWidth: 140, viewWidth: 100),
          -20);
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 1.0, textWidth: 140, viewWidth: 100),
          -40);
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 2.5, textWidth: 140, viewWidth: 100),
          -40);
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 3.0, textWidth: 140, viewWidth: 100),
          0);
      // 不超宽不滚
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 1.5, textWidth: 80, viewWidth: 100),
          0);
      expect(
          marqueeCycleSeconds(textWidth: 140, viewWidth: 100), closeTo(3, 1e-9));
      expect(
          marqueeCycleSeconds(textWidth: 80, viewWidth: 100), 0);
    });

    test('文案行数：超过 2 行才需要展开', () {
      const style = TextStyle(fontSize: 14, height: 1.35);
      expect(captionNeedsExpand('短文案', style, 200), isFalse);
      final long = List.filled(80, '很长的文案').join();
      expect(captionNeedsExpand(long, style, 200), isTrue);
      expect(kCaptionMaxLines, 2);
      expect(kCaptionFontSize, 14);
      expect(kCaptionHeight, 1.35);
    });

    testWidgets('作者/文案/音乐渲染，展开按钮可达', (tester) async {
      const long = '这是一段会超过两行显示范围的文案内容，'
          '用来验证展开按钮会出现并且点击后进入全文模式。';
      var toggled = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: PlayerInfoPanel(
              author: '张三',
              caption: long,
              music: '张三 的原声',
              maxWidth: infoAreaMaxWidth(375),
              onToggleExpand: () => toggled++,
            ),
          ),
        ),
      ));
      expect(find.text('@张三'), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.text('展开'), findsOneWidget);
      await tester.tap(find.text('展开'));
      expect(toggled, 1);
    });

    testWidgets('320 窄屏不溢出', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 640)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: PlayerInfoPanel(
                author: '一个很长很长的作者名字用来测试省略',
                caption: '文案也很长，需要在窄屏下自动省略而不是溢出屏幕边界。',
                music: '一段同样很长很长的音乐名称用于跑马灯测试',
                maxWidth: infoAreaMaxWidth(320),
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('P1 §4 任务栏', () {
    test('间距：默认 28、320 窄屏 20、并夹在最低 16', () {
      expect(taskbarSpacingFor(375), 28);
      expect(taskbarSpacingFor(390), 28);
      expect(taskbarSpacingFor(360), 28);
      expect(taskbarSpacingFor(320), 20);
      expect(taskbarSpacingFor(300), 20);
      expect(taskbarSpacingFor(340), closeTo(24, 1e-9));
      expect(taskbarSpacingFor(double.nan), 28);
      expect(kTaskbarHeight, 56);
      expect(kTaskbarIconSize, 24);
      expect(kTaskbarSidePadding, 16);
      expect(kTaskbarDividerColor, const Color(0x1AFFFFFF));
      expect(kTaskbarInactiveColor, const Color(0xB3FFFFFF));
    });
  });
}
