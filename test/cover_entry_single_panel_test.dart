import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 封面菜单必须只有一处实现。
///
/// 历史上长按信息区菜单里还有两条独立的「设/清基础库封面」项，与封面按钮
/// 弹出的四项面板重叠：同一件事两套说法、两种结果，owner 无从判断哪个是权威。
/// 本轮把四项收进 `_openCoverSheet`，长按菜单只留一个入口。这条契约钉住
/// 「只有一个封面面板」这个结构事实，避免以后又长出第二份。
///
/// 用源码扫描而不是 widget 测试：面板在播放页内部、依赖大量播放器状态，
/// 装一个真播放器来断言菜单项数量得不偿失；而这里要防的正是「第二份实现」。
void main() {
  final src = File('lib/main.dart').readAsStringSync();

  test('封面四项只在 _openCoverSheet 里各出现一次', () {
    for (final label in <String>[
      '设为该库封面',
      '清除自定义封面',
      '设为该单元库封面',
      '清除单元库封面',
    ]) {
      final hits = RegExp("Text\\('$label'\\)").allMatches(src).length;
      // 确认对话框的标题带「？」，不计入；这里只数菜单项本身。
      expect(hits, 1, reason: '「$label」应只有一处菜单项，实际 $hits');
    }
  });

  test('长按菜单只引用面板，不再自己写封面动作', () {
    final i = src.indexOf('void _showWorkMenu()');
    expect(i, greaterThan(0), reason: '找不到 _showWorkMenu');
    // 长按菜单到下一个方法声明之间。
    final tail = src.substring(i);
    final end = tail.indexOf('\n  // 0.9.29：清除自定义封面前先确认');
    final body = end > 0 ? tail.substring(0, end) : tail;
    expect(body.contains('_openCoverSheet()'), isTrue,
        reason: '长按菜单应通过 _openCoverSheet 进入封面面板');
    for (final direct in <String>[
      '_cropAndApplyCover(',
      '_confirmClearCover(',
    ]) {
      expect(body.contains(direct), isFalse,
          reason: '长按菜单不得直接调用 $direct，必须走统一面板');
    }
  });

  test('面板自身四项动作都在', () {
    final i = src.indexOf('void _openCoverSheet()');
    expect(i, greaterThan(0));
    final tail = src.substring(i);
    final end = tail.indexOf('// G11：长按作品信息区弹出播放菜单');
    final body = end > 0 ? tail.substring(0, end) : tail;
    expect(body.contains('_cropAndApplyCover(w, CoverScope.basic)'), isTrue);
    expect(body.contains('_cropAndApplyCover(w, CoverScope.unit)'), isTrue);
    expect(body.contains('_confirmClearCover(lib)'), isTrue);
    expect(body.contains('_confirmClearCover(lib, scope: CoverScope.unit)'),
        isTrue);
  });
}
