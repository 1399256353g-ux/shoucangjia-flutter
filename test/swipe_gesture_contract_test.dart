import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 亮度/音量边缘滑动：只保留「真的接上了」的那一半（0.9.200）。
///
/// 为什么删掉：`lib/swipe_control.dart` 里 9 个公有符号中，只有
/// `swipeEnabledFor` 与 `dimOpacityForBrightness` 被 `lib/` 引用，而它们
/// 服务的 `brightness` 字段**全项目只有声明处一处赋值**——没有任何手势
/// 写入它，压暗遮罩的分支 `brightness < 100` 永远为假。也就是说：
/// 一套完整的「左右边缘上下滑调亮度/音量」逻辑（边缘判定、位移换算、
/// 10% 震动档位、提示文案）只存在于 `test/swipe_control_test.dart` 的
/// 37 条断言里，产品里从来没有过。
///
/// 这与 0.9.193 删「右侧互动栏」、0.9.199 删「信息区面板」是同一个病：
/// 测试为一块不存在的界面作证，改真实渲染点没有任何测试拦得住。
///
/// 移动端的音量本来是系统音量键（`volumeUiEnabled` 只在桌面端为真）。
void main() {
  final String mainSrc = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

  test('不得再引入 swipe_control（边缘滑动那套从未接上）', () {
    expect(mainSrc.contains("import 'swipe_control.dart';"), isFalse,
        reason: '这套逻辑没有生产者，引回来就是又一份只给测试看的实现');
    expect(File('lib/swipe_control.dart').existsSync(), isFalse,
        reason: '文件本身已删除；若确需边缘手势，请从真实手势入口开始接');
  });

  test('亮度遮罩与它的状态字段一并删除，不留永远为假的分支', () {
    expect(mainSrc.contains('dimOpacityForBrightness'), isFalse);
    expect(RegExp(r'\bdouble brightness\s*=').hasMatch(mainSrc), isFalse,
        reason: 'brightness 曾只有声明、没有写入点，遮罩永远不出现');
    expect(mainSrc.contains('_swipeHintTimer'), isFalse);
    expect(mainSrc.contains('_mobileSwipe'), isFalse);
  });

  test('桌面端音量读数不再被一个永假的 _swipeHint 门控', () {
    expect(mainSrc.contains('_swipeHint'), isFalse,
        reason: '`ui && !_swipeHint` 里的 _swipeHint 恒为 false，是死条件');
  });
}
