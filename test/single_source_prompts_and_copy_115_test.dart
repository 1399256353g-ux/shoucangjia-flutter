import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/error_text.dart';
import 'package:shoucangjia/interval_label.dart';
import 'package:shoucangjia/load_error_view.dart';
import 'package:shoucangjia/toast.dart';
import 'package:shoucangjia/ui_copy.dart';

/// 第一百一十五批（0.9.362）：**同一种提示/同一句话，各页面各写一遍**。
///
/// 这一批抓的不是「两个不同的值」，而是「同一种包装」：
/// 1. `SnackBar` 弹出：五个文件各写一份，行为三处不同（mounted 守卫、
///    失败态红底、空文本）→ `toast.dart`；
/// 2. `'X失败：' + 原因`：全仓 30 余处手拼同一句 → `failureLine`；
/// 3. `LoadErrorView(message: '加载失败：$err')`：14 处各拼一遍 → `loadFailed`；
/// 4. 「N 分钟」：chip 与汇总行各拼一遍 → `minutesLabel`；
/// 5. 「名称不能为空」：注册库与建分类各写一遍 → `kEmptyNameText`；
/// 6. lib/ 里还残留 25 处「大库」（owner 已废除该叫法）→ 注释全部改写。
String codeOf(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

List<File> libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// 去掉注释行：注释里引用旧写法不算「还在实现」。
String codeOnly(String src) => [
      for (final l in src.split('\n'))
        if (!l.trimLeft().startsWith('//')) l
    ].join('\n');

void main() {
  group('1. 界面提示只有 toast.dart 一处出口', () {
    test('失败态底色只定义一次', () {
      expect(kToastErrorBackground, isNotNull);
      final offenders = libFiles()
          .where((f) => !f.path.endsWith('toast.dart'))
          .where((f) => codeOf(f.path).contains('Colors.red.shade700'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '失败底色又各写一份：$offenders');
    });

    test('空提示不弹（否则是一条没有文字的横条）', () {
      // 两个入口都必须在进 SnackBar 之前挡掉空文本。
      final src = codeOnly(codeOf('lib/toast.dart'));
      expect(src.contains('msg.isEmpty'), isTrue);
      expect(RegExp(r'if \([^)]*msg\.isEmpty[^)]*\) return;').allMatches(src).length,
          2,
          reason: 'showToast 与 showToastIn 都要在弹之前挡掉空文本');
    });

    testWidgets('样式：普通提示没有底色', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      ));
      showToastIn(ctx, '普通');
      await tester.pump();
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.backgroundColor, isNull, reason: '普通提示不带上色（历史行为）');
      expect(find.text('普通'), findsOneWidget);
    });

    testWidgets('样式：失败提示用统一红底', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      ));
      // 同一个 messenger 会排队，所以每条形态各起一棵树。
      showToastIn(ctx, '失败', bad: true);
      await tester.pump();
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.backgroundColor, kToastErrorBackground);
      expect(find.text('失败'), findsOneWidget);
    });

    testWidgets('空文本不产生任何提示', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      ));
      showToastIn(ctx, '');
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('页面已销毁时不再弹（不抛 deactivated widget）', (tester) async {
      late _ProbeState probe;
      await tester.pumpWidget(MaterialApp(home: _Probe(onReady: (s) => probe = s)));
      expect(probe.mounted, isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(probe.mounted, isFalse);
      // 已 unmount：showToast 内部守 mounted，必须静默返回。
      expect(() => showToast(probe, '迟到的提示'), returnsNormally);
    });
  });

  group('2. 「X失败：原因」只有 failureLine 一个拼法', () {
    test('拼法就是「动作 + 失败： + 原因」', () {
      expect(failureLine('保存', '磁盘满'), '保存失败：磁盘满');
      expect(failureLine('删除', 'HTTP 500'), '删除失败：HTTP 500');
      // 空动作只留后缀（批量汇总里「已删除 3 个，失败：原因」用得到）。
      expect(failureLine('', '连接失败'), '失败：连接失败');
    });

    test('lib/ 里不再手拼「X失败：」', () {
      final offenders = <String>[];
      for (final f in libFiles()) {
        if (f.path.endsWith('error_text.dart')) continue; // 实现本体
        if (f.path.endsWith('load_error_view.dart')) continue; // 统一的加载失败页
        final src = codeOnly(codeOf(f.path));
        for (final l in src.split('\n')) {
          // 允许的字面量：`failureLine(` 之内不匹配（它没有引号包裹整句），
          // 这里只找「引号里以失败：结尾或以「失败：$」开头的整句话」。
          if (RegExp(r"'[^']{0,12}失败：(?:\$\{?|\')").hasMatch(l)) {
            offenders.add('${f.path}: ${l.trim()}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: '又有地方手拼「X失败：」了（应走 failureLine）：\n${offenders.join('\n')}');
      // 真实路径仍在：调用点不能掉。
      //
      // 第一百二十批（0.9.371）：原来只数 `failureLine(`。那一批把 24 处
      // 「提示一条失败」的调用点换成了 `failureToast(this, 动作, 原因)`——
      // 文案仍由 `failureLine` 拼、但拼在 `toast.dart` 内部，调用点不再出现
      // 这个名字。只数字面量会把「收口更彻底」误判成「绕开了唯一出口」，
      // 所以这里数「产出这句文案的两个入口」，并单独钉住 `failureLine`
      // 本身仍在 `toast.dart` 里被调用（不是被整段复制过去）。
      final all = libFiles().map((f) => codeOf(f.path)).join('\n');
      final uses = RegExp(r'failureLine\(|failureToast\(|failureToastIn\(')
          .allMatches(all)
          .length;
      expect(uses, greaterThanOrEqualTo(50),
          reason: '失败文案的调用点掉到 $uses 处，说明有人绕开了唯一出口');
      expect(
          RegExp(r'failureLine\(action, reason\)')
              .hasMatch(codeOnly(codeOf('lib/toast.dart'))),
          isTrue,
          reason: 'failureToast 必须转发 failureLine，而不是自己拼一遍');
    });
  });

  group('3. 「加载失败：」只由 LoadErrorView 产出', () {
    test('loadFailed 拼出完整文案', () {
      final w = LoadErrorView.loadFailed('连接失败');
      expect(w.message, '加载失败：连接失败');
      expect(w.onRetry, isNull);
    });

    test('带重试的形态把回调透传', () {
      var hit = 0;
      final w = LoadErrorView.loadFailed('请求超时', onRetry: () => hit++);
      expect(w.message, '加载失败：请求超时');
      w.onRetry!();
      expect(hit, 1);
    });

    testWidgets('渲染成一句话（不拆成两段文字）', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: LoadErrorView.loadFailed('连接失败'))));
      expect(find.text('加载失败：连接失败'), findsOneWidget);
    });

    test('调用点不再自己拼「loading 失败：」', () {
      final offenders = libFiles()
          .where((f) => !f.path.endsWith('load_error_view.dart'))
          .where((f) => RegExp(r"message:\s*'加载失败：").hasMatch(codeOf(f.path)))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '又手拼回调用点了：$offenders');
    });
  });

  group('4. 「N 分钟」只有 minutesLabel 一处', () {
    test('格式：数字 + 单位', () {
      expect(minutesLabel(15), '15 分钟');
      expect(minutesLabel(0), '0 分钟');
    });

    test('与频率文案是两个出口，互不顶替', () {
      // `everyMinutesLabel` 是频率（带「每」），`minutesLabel` 是纯时长。
      expect(everyMinutesLabel(15), '每 15 分钟');
      expect(minutesLabel(15), isNot(everyMinutesLabel(15)));
    });

    test('lib/ 里不再有手拼的「分钟」后缀', () {
      final offenders = <String>[];
      for (final f in libFiles()) {
        if (f.path.endsWith('interval_label.dart')) continue; // 实现本体
        final src = codeOnly(codeOf(f.path));
        for (final l in src.split('\n')) {
          if (RegExp(r"'\$?\w+ 分钟'").hasMatch(l)) {
            offenders.add('${f.path}: ${l.trim()}');
          }
        }
      }
      expect(offenders, isEmpty, reason: '「N 分钟」又被手拼：$offenders');
    });
  });

  group('5. 「名称不能为空」只有一份', () {
    test('常量就是那句话', () {
      expect(kEmptyNameText, '名称不能为空');
    });

    test('注册库与建分类都读它，不再各写一份', () {
      // ui_copy.dart 是常量的定义处（那句话本身就该出现在那里）。
      final code = libFiles()
          .where((f) => !f.path.endsWith('ui_copy.dart'))
          .map((f) => codeOnly(codeOf(f.path)))
          .join('\n');
      expect(code.contains("'名称不能为空'"), isFalse,
          reason: '还有字面量没用常量（改措辞会漏）');
      expect(code.contains('kEmptyNameText'), isTrue);
    });
  });

  group('6. lib/ 里不再出现已废除的「大库」', () {
    test('任何 .dart 文件（含注释）都不含「大库」二字', () {
      final offenders = libFiles()
          .where((f) => codeOf(f.path).contains('大库'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: 'owner 已废除该叫法，仍在：$offenders');
    });
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onReady});
  final void Function(_ProbeState) onReady;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onReady(this);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
