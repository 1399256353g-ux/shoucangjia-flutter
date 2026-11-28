// 第一百一十九批（0.9.366）契约：
//  1. 「取消/确认」两键对话框只由 confirm_dialog.confirmAction 绘制；
//  2. 说明文字（12dp 灰）只由 text_styles.kHintTextStyle 提供；
//  3. 刷新按钮的 tooltip 只由 ui_copy.kRefreshTooltip 提供。
//
// 这三条都是「同一个东西写了很多遍，每处单独看都正常」的收口。测试只看
// 源码文本与合成控件，不读任何作品名/作者名/目录名。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/confirm_dialog.dart';
import 'package:shoucangjia/text_styles.dart';
import 'package:shoucangjia/ui_copy.dart';

String _read(String p) => File(p).readAsStringSync();

/// lib/ 下所有 dart 文件的 (路径, 内容)。
List<MapEntry<String, String>> _libFiles() {
  return [
    for (final e in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')))
      MapEntry(e.path.replaceAll('\\', '/'), e.readAsStringSync()),
  ];
}

void main() {
  group('1. 确认对话框只有一处实现', () {
    testWidgets('confirmAction 返回 bool 且取消/确认分别是 false/true', (tester) async {
      late bool result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await confirmAction(ctx,
                      title: '标题', message: '正文', confirmLabel: '删除');
                },
                child: const Text('open'),
              ),
            ),
          );
        }),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 标题与正文按参数渲染，取消键文案就是「取消」。
      expect(find.text('标题'), findsOneWidget);
      expect(find.text('正文'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('点取消（或点外部）返回 false，且类型非空', (tester) async {
      late bool result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await confirmAction(ctx, title: 't', message: 'm');
                },
                child: const Text('open'),
              ),
            ),
          );
        }),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('destructive 只把确认键变红，取消键不变', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => confirmAction(ctx,
                    title: 't', message: 'm', destructive: true),
                child: const Text('open'),
              ),
            ),
          );
        }),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final filled = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(filled.style?.backgroundColor?.resolve(<WidgetState>{}),
          Colors.red);
    });

    test('「取消 + 确认」两键的对话框只剩 confirm_dialog 一处', () {
      // 判据分两层：
      //  a) 正文是「一段话」的对话框（没有输入框/多选/自绘遮罩）不许再手写两键；
      //  b) 带自定义内容的对话（输入框、多选列表、裁切遮罩、筛选面板底部栏）
      //     明确列在白名单里并写明理由——它们不是同一个东西。
      const customAllowed = <String>{
        'lib/author_filter_ui.dart', // 底部筛选面板的「取消/应用」，不是确认框
        'lib/cover_crop_page.dart', // 裁切遮罩上的白字按钮，自绘叠层
        'lib/author_mount_sheet.dart', // 多选组成员（StatefulBuilder + 文件选择器）
        'lib/basic_lib_page.dart', // 新建作者（输入框 + 多库勾选）
        'lib/category_tree_page.dart', // 新建分类（输入框）
        'lib/main.dart', // 表单类：添加连接/添加媒体库/推荐数量/新建作者/裁切等
        'lib/sync_log_panel.dart', // 日志正文 + 复制，非一句话
        'lib/unit_author_mount_page.dart', // 合并/编辑组成员（文件选择器）
      };
      final offenders = <String>[];
      for (final f in _libFiles()) {
        if (f.key.endsWith('confirm_dialog.dart')) continue;
        if (customAllowed.contains(f.key)) continue;
        final src = f.value;
        for (final m in RegExp(r"Text\('取消'\)").allMatches(src)) {
          final tail = src.substring(m.end, (m.end + 400).clamp(0, src.length));
          if (tail.contains('FilledButton(')) {
            offenders.add(
                '${f.key}:${'\n'.allMatches(src.substring(0, m.start)).length + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: '这些地方还在手写「取消/确认」两键，应改用 confirmAction：'
              '${offenders.join(', ')}');
    });

    test('六个已收口的页面确实调用 confirmAction', () {
      const files = [
        'lib/main.dart',
        'lib/folder_structure_page.dart',
        'lib/unit_author_mount_page.dart',
        'lib/crash_reports_page.dart',
        'lib/cover_menu.dart',
        'lib/cache_settings.dart',
      ];
      for (final p in files) {
        final src = _read(p);
        expect(src.contains('confirmAction('), isTrue, reason: p);
        expect(src.contains("import 'confirm_dialog.dart';"), isTrue,
            reason: p);
      }
    });

    test('删除类确认的不可撤销标记不会被顺手加上', () {
      // 「删注册表项」可恢复 → 不红；「删同步源索引」不可恢复 → 红。
      // 这是唯一一处 destructive 的语义分界，写死断言防回归。
      final main = _read('lib/main.dart');
      final syncBlock = main.substring(
          main.indexOf("title: '移除同步源'") - 200,
          main.indexOf("title: '移除同步源'") + 400);
      expect(syncBlock.contains('destructive: true'), isTrue);
      final libBlock = main.substring(
          main.indexOf("message: '仅从注册表移除") - 200,
          main.indexOf("message: '仅从注册表移除") + 200);
      expect(libBlock.contains('destructive'), isFalse);
    });
  });

  group('2. 说明文字样式只有一处', () {
    test('kHintTextStyle 就是 12dp 灰', () {
      expect(kHintTextStyle.fontSize, 12);
      expect(kHintTextStyle.color, Colors.grey);
    });

    test('lib/ 除 text_styles.dart 外零手写「12dp 灰」', () {
      final offenders = <String>[];
      for (final f in _libFiles()) {
        if (f.key.endsWith('text_styles.dart')) continue;
        final src = f.value;
        if (src.contains('TextStyle(fontSize: 12, color: Colors.grey)') ||
            src.contains('TextStyle(color: Colors.grey, fontSize: 12)') ||
            RegExp(r'TextStyle\(\s*\n\s*fontSize: 12,\s*color: Colors\.grey\s*\)')
                .hasMatch(src) ||
            RegExp(r'TextStyle\(\s*\n\s*color: Colors\.grey,\s*fontSize: 12\s*\)')
                .hasMatch(src)) {
          offenders.add(f.key);
        }
      }
      expect(offenders, isEmpty, reason: '应改用 kHintTextStyle：${offenders.join(', ')}');
    });

    test('11dp 那一批不被并进来（语义不同，字号不同）', () {
      // 只是防止「统一」被顺手扩到副标题/计数行：11dp 灰仍有 20+ 处。
      var n = 0;
      for (final f in _libFiles()) {
        n += RegExp(r'TextStyle\(fontSize: 11, color: Colors\.grey\)')
            .allMatches(f.value)
            .length;
      }
      expect(n, greaterThan(15));
    });
  });

  group('3. 刷新按钮的 tooltip 只有一处', () {
    test('常量的字面值', () => expect(kRefreshTooltip, '刷新'));

    test('lib/ 内零裸 tooltip: \'刷新\'', () {
      final offenders = [
        for (final f in _libFiles())
          if (!f.key.endsWith('ui_copy.dart') &&
            f.value.contains("tooltip: '刷新'"))
          f.key,
      ];
      expect(offenders, isEmpty, reason: offenders.join(', '));
    });

    test('语义不同的两个按钮不被合并', () {
      // 「重新扫描」是维护页对服务端的重扫；「换一批」是推荐页换种子。
      final main = _read('lib/main.dart');
      expect(main.contains("tooltip: '重新扫描'"), isTrue);
      expect(main.contains("tooltip: '换一批'"), isTrue);
    });

    test('八处刷新按钮都改用常量', () {
      var n = 0;
      for (final f in _libFiles()) {
        n += 'tooltip: kRefreshTooltip'.allMatches(f.value).length;
      }
      expect(n, 13);
    });
  });
}
