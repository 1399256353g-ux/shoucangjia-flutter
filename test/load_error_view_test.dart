import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/load_error_view.dart';

void main() {
  group('LoadErrorView：11 处手写错误块收成一个控件', () {
    testWidgets('带重试时显示按钮并能点', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LoadErrorView(
            message: '加载失败：HTTP 500',
            onRetry: () => taps++,
          ),
        ),
      ));
      expect(find.text('加载失败：HTTP 500'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(taps, 1);
    });

    testWidgets('不给 onRetry 时不出现重试按钮（页面级错误）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LoadErrorView(message: '加载失败：连接失败')),
      ));
      expect(find.text('加载失败：连接失败'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
    });

    testWidgets('长错误在窄屏不溢出（旧的两处没有内边距，会顶到边缘）', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LoadErrorView(
            message: '加载失败：${'很长的错误说明' * 12}',
            onRetry: () {},
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('很长的错误说明'), findsOneWidget);
    });

    testWidgets('文案居中、字号与旧版一致（12）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LoadErrorView(message: '加载失败：X')),
      ));
      final text = tester.widget<Text>(find.text('加载失败：X'));
      expect(text.textAlign, TextAlign.center);
      expect(text.style?.fontSize, 12);
    });
  });
}
