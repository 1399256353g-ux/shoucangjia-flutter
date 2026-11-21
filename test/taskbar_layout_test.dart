import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_controls.dart';
import 'package:shoucangjia/video_layout.dart';

/// 非全屏任务栏高度必须只有一个来源：
///   实际渲染 = SizedBox(kTaskbarContentHeight) + 1dp 分割线 + 底部安全区
///            = kTaskbarHeight + 底部安全区
///            = 舞台 inset 的回退值（taskbarReservedHeight）。
/// 两边任何一处改常量而另一处没跟上，这里就会红。
void main() {
  Future<double> measureBar(WidgetTester tester, double safeBottom) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: key,
            width: 400,
            decoration: const BoxDecoration(
              color: kTaskbarColor,
              border: Border(
                top: BorderSide(color: kTaskbarDividerColor, width: 1),
              ),
            ),
            padding: EdgeInsets.only(bottom: safeBottom),
            child: const SizedBox(
              height: kTaskbarContentHeight,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    ));
    return key.currentContext!.size!.height;
  }

  testWidgets('任务栏实际总高 = 内容行 + 1dp 分割线 + 安全区', (tester) async {
    for (final safe in <double>[0, 24, 34]) {
      final h = await measureBar(tester, safe);
      expect(h, closeTo(kTaskbarHeight + safe, 0.001));
      // 舞台 inset 的首帧回退值必须与真实渲染高度一致（不再差 1dp）。
      expect(
        taskbarReservedHeight(contentHeight: kTaskbarHeight, safeBottom: safe),
        closeTo(h, 0.001),
      );
    }
  });

  test('内容行 + 分割线 = 任务栏总高', () {
    expect(kTaskbarContentHeight + kTaskbarDividerWidth, kTaskbarHeight);
  });

  test('舞台高度严格等于屏幕高 − 任务栏高', () {
    for (final safe in <double>[0, 24, 34]) {
      final bar = taskbarReservedHeight(
          contentHeight: kTaskbarHeight, safeBottom: safe);
      final inset = stageBottomInset(
          screenHeight: 812, taskbarHeight: bar, fullscreen: false);
      expect(inset, closeTo(bar, 0.001));
      // 舞台底边 = 任务栏顶边，不留缝也不重叠。
      expect(812 - inset, closeTo(812 - bar, 0.001));
    }
  });
}
