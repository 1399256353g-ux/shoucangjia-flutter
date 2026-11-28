import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_upload.dart';
import 'package:shoucangjia/toast.dart';

/// 第一百二十批（0.9.371）：**「这是一次失败」没有写进函数名，所以没人传**。
///
/// `toast.dart` 从 0.9.362 起就有 `bad: true` 这个参数，但全仓只有挂载面板
/// 两处在用。其余 24 处「确定失败了」的提示——上传封面失败、保存同步源失败、
/// 批量删除失败、读取目录失败——调的都是 `showToast(this, failureLine(...))`，
/// 走默认底色：界面上和「已保存」是同一根灰条。
///
/// 这不是「谁忘了传参数」这么简单：`showToast` 的签名里 `bad` 与 `msg` 平级，
/// 调用点没有任何提示说「这句是失败」。所以修法不是逐处补 `bad: true`，
/// 而是给「失败提示」一个**自己的入口**（`failureToast`）——文案由
/// `failureLine` 拼、红底由同一个函数给，两者不可能再分叉。
///
/// 同批第二件：`unit_library_view.dart` 里三个 State 各写了一份逐字相同的
/// `_pickCover`（媒体库 / 单元库 / 基础库卡片），三份都只弹 `r.message`，
/// `CoverUploadResult.ok` 谁都没读。收成 `pickCoverWithToast` 一处。
String codeOf(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

List<File> libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String relPath(File f) => f.path.replaceAll('\\', '/');

String codeOnly(String src) => [
      for (final l in src.split('\n'))
        if (!l.trimLeft().startsWith('//')) l
    ].join('\n');

/// 一个用于 `showToast(state, …)` 的宿主 State。
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SizedBox.expand());
}

Future<_HostState> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: _Host()));
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  group('1. failureToast 是失败提示的唯一入口', () {
    testWidgets('文案是「动作失败：原因」，且一定是红底', (tester) async {
      final host = await _pumpHost(tester);
      failureToast(host, '保存', '磁盘满');
      await tester.pump();

      expect(find.text('保存失败：磁盘满'), findsOneWidget);
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.backgroundColor, kToastErrorBackground,
          reason: '失败提示必须与成功提示区分底色，不能靠调用点自己记得传 bad');
    });

    testWidgets('普通提示仍无底色（两个入口不互相影响）', (tester) async {
      final host = await _pumpHost(tester);
      showToast(host, '已保存');
      await tester.pump();
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.backgroundColor, isNull);
    });

    testWidgets('replace 语义透传', (tester) async {
      final host = await _pumpHost(tester);
      failureToast(host, '读取', '第一条', replace: true);
      await tester.pump();
      failureToast(host, '读取', '第二条', replace: true);
      await tester.pump();
      expect(find.text('读取失败：第二条'), findsOneWidget);
      expect(find.text('读取失败：第一条'), findsNothing);
    });

    test('failureToast 转发 failureLine，不自己拼一遍', () {
      final src = codeOnly(codeOf('lib/toast.dart'));
      expect(src.contains('failureLine(action, reason)'), isTrue,
          reason: '文案只能由 failureLine 产出');
      expect(RegExp(r"'\$\{action\}失败").hasMatch(src), isFalse,
          reason: 'failureToast 里又手拼了一遍「失败：」');
    });
  });

  group('2. lib/ 里「确定失败了」的提示不再走默认底色', () {
    test('没有 showToast/_toast 直接包 failureLine 的调用点', () {
      // 例外：句子中间夹「失败：」的汇总提示（「已删除 3 个，失败：原因」）
      // 主体是「删了几个」，不是一次失败，仍由 failureLine 拼、不染红底。
      final offenders = <String>[];
      for (final f in libFiles()) {
        if (relPath(f).endsWith('toast.dart') ||
            relPath(f).endsWith('error_text.dart')) {
          continue;
        }
        final src = codeOnly(codeOf(f.path));
        for (final l in src.split('\n')) {
          if (RegExp(r"(showToast|showToastIn|_toast)\([^)]*failureLine\(")
              .hasMatch(l)) {
            offenders.add('${relPath(f)}: ${l.trim()}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: '失败提示要染红底，应走 failureToast/failureToastIn：\n'
              '${offenders.join('\n')}');
    });

    test('失败入口确实被大面积使用（不是只剩定义）', () {
      var uses = 0;
      for (final f in libFiles()) {
        uses += RegExp(r'failureToast(In)?\(')
            .allMatches(codeOf(f.path))
            .length;
      }
      // 减掉 toast.dart 里的定义与转发本身。
      expect(uses, greaterThan(20),
          reason: 'failureToast 调用点只有 $uses 处，说明收口被回退了');
    });
  });

  group('3. 封面结果提示读 ok，且只有一处实现', () {
    testWidgets('pickCoverWithToast 失败染红', (tester) async {
      final host = await _pumpHost(tester);
      await pickCoverWithToast(host,
          ({required String libId, String unitRel = ''}) async {
        return const CoverUploadResult(false, '上传失败：图片过大');
      }, 'lib-1', '');
      await tester.pump();
      expect(find.text('上传失败：图片过大'), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
          kToastErrorBackground);
    });

    testWidgets('pickCoverWithToast 成功不染红', (tester) async {
      final host = await _pumpHost(tester);
      await pickCoverWithToast(host,
          ({required String libId, String unitRel = ''}) async {
        return const CoverUploadResult(true, '封面已更新');
      }, 'lib-1', '');
      await tester.pump();
      expect(find.text('封面已更新'), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
          isNull);
    });

    test('host 为 null uploader 时静默返回，不抛异常', () async {
      // 只读视图（没有注入上传能力）点封面按钮不该崩。
      expect(
          () => pickCoverWithToast(_NeverMounted(), null, 'lib-1', ''),
          returnsNormally);
    });

    test('lib/ 里不再有三份逐字相同的 _pickCover', () {
      // 三个 State 各写一遍这段（含注释共 8 行）是这批的结构问题：
      // 三份里任何一份漏判 `r.ok`，那个入口的失败提示就永远是灰条。
      final src = codeOnly(codeOf('lib/unit_library_view.dart'));
      final copies = RegExp(r'widget\.coverUploader;').allMatches(src).length;
      expect(copies, 0,
          reason: 'unit_library_view 里还有 $copies 处直接读 coverUploader，'
              '应走 pickCoverWithToast');
      final calls = RegExp(r'pickCoverWithToast\(').allMatches(src).length;
      expect(calls, 3, reason: '三个卡片入口都要接到同一个实现');
    });
  });
}

/// 一个永远不会 mounted 的 State，用来验证「只读视图」路径。
class _NeverMounted extends State<StatefulWidget> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
