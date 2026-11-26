/// 第七十三批契约（0.9.300）：**「整窗口」冒充「网格可用空间」**。
///
/// 前几批抓的是「同一段代码抄多份」「同一记录两个模型」「同一数字两种说法」
/// 「参数名同、含义不同」——它们都有第二个副本可对照。
///
/// 这一批抓的是另一类静默错误：**两边都算得出一个数，但一边算的是另一件东西**。
///
/// 1. 首屏预热的尺寸来自 `MediaQuery.size`（**整个窗口**），而网格真正拿到的
///    约束是窗口减去 AppBar / 头部 / 筛选条之后的那个矩形。手机竖屏上差
///    100–250dp，等于多预热半屏到一屏的封面/头像——每张都真发一次请求。
///    若一张封面要 401 或要服务端现场抽帧，这一行就是首屏起播时间的一部分。
/// 2. 骨架屏用 `EdgeInsets.all(12)` + 固定 `kWorkGrid`，真实网格用
///    `workGridPadding(context)` + 各自的规格。加载完成那一刻整屏卡片**跳一下**
///    （安全区从无到有、列数从 180 的分辨率到 150 的），不是渐入而是重排。
/// 3. 作者总览的骨架用的是作品网格（3:4、间距 2），而它盖住的页面是
///    `kAuthorGrid`（固定行高 170、间距 10）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_index.dart' show kAuthorGridPagePadding;
import 'package:shoucangjia/grid_spec.dart';
import 'package:shoucangjia/main.dart' show WorkGridSkeleton;

/// 去掉整行注释后再做「有没有第二个来源」的扫描。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 一个类体的源码（从 `class X` 到下一个 `class ` 之前）。
String _classBody(String src, String name) {
  final start = src.indexOf('class $name');
  expect(start, isNonNegative, reason: '找不到 $name');
  final rest = src.substring(start + 1);
  final next = rest.indexOf('\nclass ');
  return next < 0 ? rest : rest.substring(0, next);
}

void main() {
  group('首屏预热的尺寸来自网格自己，不是整窗口（0.9.300）', () {
    test('骨架屏默认内边距 = 真实网格的同一个出口', () {
      // 默认值必须是 `null`（运行时读 workGridPadding），不能是字面量。
      final body = _classBody(_code('lib/main.dart'), 'WorkGridSkeleton');
      expect(body.contains('this.padding,'), isTrue,
          reason: 'padding 必须可为空，空时读 workGridPadding(context)');
      expect(body.contains('padding ?? workGridPadding(context)'), isTrue,
          reason: '骨架屏与真实网格必须同一个内边距来源');
      expect(body.contains('EdgeInsets.all('), isFalse,
          reason: '骨架屏不得自己挑内边距');
    });

    test('骨架屏的网格规格可传，默认作品网格', () {
      final body = _classBody(_code('lib/main.dart'), 'WorkGridSkeleton');
      expect(body.contains('this.grid = kWorkGrid'), isTrue);
      expect(body.contains('gridDelegate: grid.delegate'), isTrue,
          reason: '骨架屏必须转发传入的规格，不能写死 kWorkGrid');
    });

    test('作者总览的骨架用作者网格 + 作者页内边距', () {
      final main = _code('lib/main.dart');
      // 骨架调用点必须带 kAuthorGrid，否则加载完成时列数/行高一起变。
      expect(
          RegExp(r'WorkGridSkeleton\(\s*count: 18,\s*grid: kAuthorGrid,')
              .hasMatch(main.replaceAll('\n', ' ')),
          isTrue,
          reason: '作者总览的骨架必须模仿 kAuthorGrid');
    });

    test('四个预热入口都不再拿窗口尺寸当网格可用空间', () {
      // 作品网格（main）、基础库作品网格、作者总览、基础库作者 tab、
      // 排行榜：全部改读自己的 LayoutBuilder 结果。
      final main = _code('lib/main.dart');
      final page = _code('lib/basic_lib_page.dart');
      // 预热函数体里不得再出现 `viewport: mq.size` / `mq.size.height`。
      expect(RegExp(r'viewport:\s*mq\.size\b').hasMatch(main), isFalse,
          reason: 'main 的预热不得再拿整窗口当网格尺寸');
      expect(RegExp(r'viewport:\s*mq\.size\b').hasMatch(page), isFalse,
          reason: '基础库页的预热不得再拿整窗口当网格尺寸');
      expect(RegExp(r'viewportHeight:\s*mq\.size\.height').hasMatch(main), isFalse,
          reason: '排行榜的单行预热不得再拿整窗口高度');
      // 三处都要读到自己的尺寸字段。
      for (final f in <String>['_gridViewport', '_listViewportHeight']) {
        expect(main.contains(f), isTrue, reason: 'main 缺 $f');
      }
      for (final f in <String>['_worksViewport', '_authorsViewport']) {
        expect(page.contains(f), isTrue, reason: 'basic_lib_page 缺 $f');
      }
    });

    test('预热在尺寸未知时先不发（不拿窗口顶替一次）', () {
      final main = _code('lib/main.dart');
      final page = _code('lib/basic_lib_page.dart');
      // 早退守卫：尺寸为 null 直接 return，且不能在此时记「已预热」。
      expect(RegExp(r'if \(_gridViewport == null\) return;').hasMatch(main)
              || RegExp(r'final viewport = _gridViewport;\s*if \(viewport == null\) return;')
                  .hasMatch(main),
          isTrue,
          reason: 'main 的预热必须等网格尺寸到手');
      expect(
          RegExp(r'final viewport = _worksViewport;\s*if \(viewport == null\) return;')
              .hasMatch(page),
          isTrue,
          reason: '基础库作品预热必须等网格尺寸到手');
      expect(
          RegExp(r'final viewport = _authorsViewport;\s*if \(viewport == null\) return;')
              .hasMatch(page),
          isTrue,
          reason: '基础库作者预热必须等网格尺寸到手');
    });

    test('网格用 LayoutBuilder 上报自己的约束（唯一来源）', () {
      final main = _code('lib/main.dart');
      final page = _code('lib/basic_lib_page.dart');
      // main：作品网格 + 作者总览 + 排行榜三处。
      expect(
          RegExp(r'_gridViewport = (cons\.biggest|size)').allMatches(main).length,
          greaterThanOrEqualTo(2),
          reason: '作品网格与作者总览都要上报自己的尺寸');
      expect(main.contains('_listViewportHeight = cons.maxHeight'), isTrue,
          reason: '排行榜列表要上报自己的高度');
      expect(page.contains('_worksViewport = cons.biggest'), isTrue);
      expect(page.contains('_authorsViewport = cons.biggest'), isTrue);
      // 布局阶段只写字段、不 setState（否则 build 里又触发 build）。
      final mainGrid = _classBody(main, '_WorkGridState');
      expect(mainGrid.contains('_gridViewport = size'), isTrue);
      expect(
          RegExp(r'_gridViewport = [^;]+;\s*setState')
              .hasMatch(mainGrid.replaceAll(RegExp(r'\n\s*'), ' ')),
          isFalse,
          reason: '布局阶段不得 setState');
    });
  });

  group('骨架屏与真实网格排布一致（真实 MediaQuery，0.9.300）', () {
    testWidgets('骨架屏的 padding 与安全区同源，不是 all(12)', (tester) async {
      // 手机竖屏：状态栏 32、手势条 20。真实网格拿 workGridPadding → 上下带入，
      // 左右 0；旧骨架屏给 all(12)，四边都错。
      const mq = MediaQueryData(
        size: Size(360, 720),
        devicePixelRatio: 3,
        padding: EdgeInsets.only(top: 32, bottom: 20),
      );
      await tester.pumpWidget(const MediaQuery(
        data: mq,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 360,
            height: 600,
            child: WorkGridSkeleton(count: 6),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      final grid = tester.widget<GridView>(find.byType(GridView).first);
      expect(grid.padding, workGridPadding(tester.element(find.byType(GridView).first)),
          reason: '骨架屏与真实网格必须取同一个内边距');
      expect(grid.padding, const EdgeInsets.only(top: 32, bottom: 20),
          reason: '安全区必须带进骨架屏（旧写法是 all(12)）');
    });

    testWidgets('传了作者网格规格时骨架跟随它（列数/行高一致）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WorkGridSkeleton(
                count: 6, grid: kAuthorGrid, padding: kAuthorGridPagePadding)),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      final grid = tester.widget<GridView>(find.byType(GridView).first);
      final d = grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
      expect(d.maxCrossAxisExtent, kAuthorGrid.maxCrossAxisExtent);
      expect(d.mainAxisExtent, kAuthorGrid.mainAxisExtent);
      expect(grid.padding, kAuthorGridPagePadding);
    });
  });
}
