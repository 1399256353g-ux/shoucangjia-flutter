import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/loading_view.dart';
import 'package:shoucangjia/registry_lib_id.dart';
import 'package:shoucangjia/toast.dart';

/// 第一百一十六批（0.9.363）：**同一种包装的第二份实现**。
///
/// 0.9.362 只把「提示」在五个文件里的写法收进了 `toast.dart`，另外 **62 处**
/// 仍各自 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(...)))`。
/// 形态一致所以没坏，但它是同一件事的第二份实现：改提示的统一行为要改 62 处。
///
/// 同一批里还有两件同型的事：
/// - 转圈在 `lib/` 里 41 处，两种形态各写各的 → `loading_view.dart`；
/// - 新建注册库的 id 规则（字符集 + 长度 + 提示）只在 `_add` 里写了一份，
///   与服务端 `libIdOk()` 是同一条规则却两份代码 → `registry_lib_id.dart`。
String codeOf(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

List<File> libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// 去掉注释行：注释里引用旧写法（说明「曾经如此」）不算「还在实现」。
String codeOnly(String src) => [
      for (final l in src.split('\n'))
        if (!l.trimLeft().startsWith('//')) l
    ].join('\n');

void main() {
  group('1. 提示只有一个出口', () {
    test('lib/ 内除 toast.dart 外没有 showSnackBar', () {
      final offenders = libFiles()
          .where((f) => !f.path.endsWith('toast.dart'))
          .where((f) => codeOnly(codeOf(f.path)).contains('showSnackBar'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty,
          reason: '提示又出现了第二份实现（应走 showToast/showToastIn）：'
              '$offenders');
    });

    test('lib/ 内除 toast.dart 外没有裸 SnackBar 构造', () {
      // 直接 `SnackBar(...)` 与 `showSnackBar` 是同一件事的两种写法；
      // 只查后者会漏掉 `messenger.showSnackBar(SnackBar(...))` 之外的分支。
      final offenders = libFiles()
          .where((f) => !f.path.endsWith('toast.dart'))
          .where((f) => RegExp(r'\bSnackBar\s*\(')
              .hasMatch(codeOnly(codeOf(f.path))))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '还有地方自己构造 SnackBar：$offenders');
    });

    test('两个入口都在 toast.dart，且都挡空文本', () {
      final src = codeOnly(codeOf('lib/toast.dart'));
      expect(src.contains('void showToast('), isTrue);
      expect(src.contains('void showToastIn('), isTrue);
      expect(
          RegExp(r'if \(!state\.mounted \|\| msg\.isEmpty\) return;')
              .hasMatch(src),
          isTrue,
          reason: 'state 入口必须同时守 mounted 与空文本');
      expect(RegExp(r'if \(msg\.isEmpty\) return;').hasMatch(src), isTrue,
          reason: 'context 入口必须挡空文本');
    });

    test('replace 走 hideCurrentSnackBar（连续操作不排队十条）', () {
      final src = codeOnly(codeOf('lib/toast.dart'));
      expect(src.contains('if (replace) messenger.hideCurrentSnackBar();'), isTrue,
          reason: 'replace 语义应在唯一出口实现，而不是各页面自己写级联');
    });

    test('原先自己写级联的页面改成 replace: true', () {
      // 六个 `..hideCurrentSnackBar()..showSnackBar(...)` 调用点：改成
      // `replace: true` 后语义不变，但形态只剩一处。
      var cascade = 0;
      for (final f in libFiles()) {
        cascade += RegExp(r'\.\.hideCurrentSnackBar\(\)')
            .allMatches(codeOnly(codeOf(f.path)))
            .length;
      }
      expect(cascade, 0, reason: '还有页面自己写 hideCurrentSnackBar 级联');
      final replaceCalls = libFiles()
          .map((f) => codeOnly(codeOf(f.path)))
          .join('\n')
          .split('replace: true')
          .length;
      expect(replaceCalls, greaterThan(1), reason: 'replace 语义应至少被用上');
    });

    testWidgets('replace 不把队列堆起来', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
        ),
      ));
      showToastIn(ctx, '第一条', replace: true);
      await tester.pump();
      showToastIn(ctx, '第二条', replace: true);
      await tester.pump();
      expect(find.text('第二条'), findsOneWidget);
      expect(find.text('第一条'), findsNothing, reason: '前一条应被替换掉');
    });

    testWidgets('自定义时长只作用于这一条', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
        ),
      ));
      showToastIn(ctx, '短提示', duration: const Duration(milliseconds: 900));
      await tester.pump();
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, const Duration(milliseconds: 900));
    });
  });

  group('2. 加载占位只有一个出口', () {
    test('lib/ 内不再自己写 Center(child: CircularProgressIndicator())', () {
      final offenders = libFiles()
          .where((f) => !f.path.endsWith('loading_view.dart'))
          .where((f) => codeOnly(codeOf(f.path))
              .contains('Center(child: CircularProgressIndicator())'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '整页转圈又各写一份：$offenders');
    });

    test('lib/ 内不再自己写 strokeWidth: 2 的细圈', () {
      final offenders = libFiles()
          .where((f) => !f.path.endsWith('loading_view.dart'))
          .where((f) => RegExp(r'CircularProgressIndicator\([^)]*strokeWidth')
              .hasMatch(codeOnly(codeOf(f.path))))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '行内细圈又各写一份：$offenders');
    });

    test('细圈线宽只定义一次', () {
      expect(kInlineSpinnerStroke, 2);
      final defs = libFiles()
          .where((f) =>
              codeOnly(codeOf(f.path)).contains('kInlineSpinnerStroke ='))
          .map((f) => f.path)
          .toList();
      expect(defs, ['lib/loading_view.dart'],
          reason: '线宽常量应只在 loading_view.dart 定义');
    });

    testWidgets('LoadingView 渲染一个居中转圈', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: LoadingView())));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final center = tester.widget<Center>(find.byType(Center).first);
      expect(center.child, isA<CircularProgressIndicator>());
    });

    testWidgets('InlineSpinner 是细圈，颜色可覆盖', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: InlineSpinner(color: const Color(0xFF102030)))));
      final p = tester
          .widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(p.strokeWidth, kInlineSpinnerStroke);
      expect(p.color, const Color(0xFF102030));
    });
  });

  group('3. 注册库 id 规则与服务端同一条', () {
    test('合法：小写字母/数字开头，余下可含下划线与连字符', () {
      expect(registryLibIdError('douyin'), isNull);
      expect(registryLibIdError('my-lib_2'), isNull);
      expect(registryLibIdError('a'), isNull);
    });

    test('长度边界：32 位可以通过，33 位不行', () {
      final ok = 'a' * kRegistryLibIdMaxLength;
      expect(ok.length, 32);
      expect(registryLibIdError(ok), isNull);
      expect(registryLibIdError('a' * (kRegistryLibIdMaxLength + 1)),
          kRegistryLibIdFormatText);
    });

    test('归一化先于校验：空格与大写都能通过', () {
      expect(normalizeRegistryLibId('  My-Lib  '), 'my-lib');
      expect(registryLibIdError('  My-Lib  '), isNull,
          reason: '服务端只认小写，客户端要先归一化再判定');
      expect(registryLibIdError('MY_LIB'), isNull);
    });

    test('非法：空串、首字符是符号、中文、含点或斜杠', () {
      for (final bad in ['', '  ', '-lib', '_lib', '库', 'a.b', 'a/b', 'a b']) {
        expect(registryLibIdError(bad), kRegistryLibIdFormatText,
            reason: '应拒绝：`$bad`');
      }
    });

    test('规则正则与提示只在 registry_lib_id.dart 出现', () {
      final others = libFiles()
          .where((f) => !f.path.endsWith('registry_lib_id.dart'))
          .where((f) {
        final src = codeOnly(codeOf(f.path));
        return src.contains(r'[a-z0-9][a-z0-9_-]{0,31}') ||
            src.contains(kRegistryLibIdFormatText);
      }).map((f) => f.path).toList();
      expect(others, isEmpty, reason: '库 id 规则/提示又写了一份：$others');
    });

    test('新建库调用点问同一句，不再自己写 RegExp', () {
      final main = codeOnly(codeOf('lib/main.dart'));
      expect(main.contains('registryLibIdError(lid)'), isTrue);
      final start = main.indexOf('Future<void> _add() async {');
      expect(start, greaterThan(0));
      final body = main.substring(start, start + 4000);
      expect(RegExp(r'RegExp\(').hasMatch(body), isFalse,
          reason: '_add 里不该再有自己写的 id 正则');
    });
  });
}
