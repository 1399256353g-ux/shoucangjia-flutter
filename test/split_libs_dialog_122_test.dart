/// 0.9.376（第一百二十二批）契约：
///  1. 「拆出基础库」对话框只有一处实现——两个挂载入口此前各写 60 行几乎
///     逐字相同的 `showDialog` + `StatefulBuilder` + `CheckboxListTile`，
///     差别只有 Key 前缀。同一段判定（至少 1 个、不能全选）两份实现意味着
///     将来改一处、另一处会静默放行必然 400 的请求。
///  2. 纯文本确认框（解散合并）不得再手拼——必须走 `confirmAction`。
///
/// 全部判据是源码结构与真实 widget 行为，不涉及任何作者名/目录名。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/split_libs_dialog.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('拆出基础库对话框：唯一实现', () {
    test('两个入口都转发 pickLibsToSplit，不再自己 showDialog', () {
      for (final f in const [
        'lib/author_mount_sheet.dart',
        'lib/unit_author_mount_page.dart',
      ]) {
        final src = _code(f);
        expect(src.contains('pickLibsToSplit('), isTrue,
            reason: '$f 没有走共用的拆出对话框');
        // 「拆出基础库」这句标题只能出现在共用实现里。
        expect(src.contains("'拆出基础库'"), isFalse,
            reason: '$f 又自己写了一份拆出对话框');
        expect(src.contains('split_libs_dialog.dart'), isTrue);
      }
    });

    test('共用实现里「不能全选」的禁用条件只有一处', () {
      final dlg = _code('lib/split_libs_dialog.dart');
      // 两个条件必须同时参与：空选与全选都禁用（全选等于解散，是另一个动作）。
      expect(
          RegExp(r'picked\.isEmpty\s*\|\|\s*picked\.length\s*>=\s*libs\.length')
              .hasMatch(dlg),
          isTrue,
          reason: '确认键的禁用条件必须同时挡「一个都没选」与「全选」');
      // Key 由调用方传入，不能写死某一个入口的前缀。
      expect(dlg.contains(r"'$keyPrefix-split-lib-$lib'"), isTrue);
      expect(dlg.contains(r"'$keyPrefix-split-ok'"), isTrue);
    });

    test('作者页的解散合并走 confirmAction，不再手拼对话框', () {
      final sheet = _code('lib/author_mount_sheet.dart');
      expect(sheet.contains('confirmAction('), isTrue,
          reason: '纯文本确认框有唯一实现，不该再手写一份');
      expect(sheet.contains("const Text('解散合并')"), isFalse,
          reason: '标题应作为 confirmAction 参数传入，而不是自己画一个 AlertDialog');
      // 确认键仍保留（测试/自动化靠它定位）。
      expect(sheet.contains("ValueKey('ams-dissolve-ok')"), isTrue);
    });
  });

  group('pickLibsToSplit 的真实交互', () {
    Future<Set<String>?> run(
      WidgetTester t, {
      required List<String> libs,
      required Future<void> Function(WidgetTester) drive,
    }) async {
      Set<String>? out;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () async {
                  out = await pickLibsToSplit(ctx,
                      libs: libs, labelOf: (l) => '库$l', keyPrefix: 't');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const ValueKey('open')));
      await t.pumpAndSettle();
      await drive(t);
      await t.pumpAndSettle();
      return out;
    }

    testWidgets('面板按传入顺序列出全部基础库', (t) async {
      await run(t, libs: const ['a', 'b', 'c'], drive: (t) async {
        expect(find.byKey(const ValueKey('t-split-lib-a')), findsOneWidget);
        expect(find.byKey(const ValueKey('t-split-lib-c')), findsOneWidget);
        await t.tap(find.text('取消'));
      });
    });

    testWidgets('一个都没选时确认键禁用', (t) async {
      await run(t, libs: const ['a', 'b'], drive: (t) async {
        final btn = t.widget<FilledButton>(find.byKey(const ValueKey('t-split-ok')));
        expect(btn.onPressed, isNull, reason: '空选必须禁用（否则会发一个必然 400 的请求）');
        await t.tap(find.text('取消'));
      });
    });

    testWidgets('全选时确认键同样禁用（全拆走＝解散，是另一个动作）', (t) async {
      await run(t, libs: const ['a', 'b'], drive: (t) async {
        await t.tap(find.byKey(const ValueKey('t-split-lib-a')));
        await t.tap(find.byKey(const ValueKey('t-split-lib-b')));
        await t.pumpAndSettle();
        final btn = t.widget<FilledButton>(find.byKey(const ValueKey('t-split-ok')));
        expect(btn.onPressed, isNull);
        await t.tap(find.text('取消'));
      });
    });

    testWidgets('只选一部分时返回勾选集合，取消返回 null', (t) async {
      final picked = await run(t, libs: const ['a', 'b', 'c'], drive: (t) async {
        await t.tap(find.byKey(const ValueKey('t-split-lib-b')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('t-split-ok')));
      });
      expect(picked, {'b'});

      final cancelled =
          await run(t, libs: const ['a', 'b', 'c'], drive: (t) async {
        await t.tap(find.byKey(const ValueKey('t-split-lib-b')));
        await t.pumpAndSettle();
        await t.tap(find.text('取消'));
      });
      expect(cancelled, isNull, reason: '取消必须与「没勾」区分开');
    });
  });
}
