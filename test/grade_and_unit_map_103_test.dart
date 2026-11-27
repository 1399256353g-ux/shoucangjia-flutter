import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_filter.dart';
import 'package:shoucangjia/author_grade.dart';
import 'package:shoucangjia/work_forms.dart';

/// 第一百零三批（0.9.348）契约。
///
/// 本批抓的都是「同一句判定散成好几份，各自都能跑」：
///  1. 等级清单在筛选面板（两处）与筛选摘要里各写一份字面量；
///  2. `basicToUnit[id] ?? ''` 在 `main.dart` 里散着六份，回落到空串/`secret`
///     两种口径并存；
///  3. 筛选面板里「这个旧分组已被单元库接管」的判定写了两遍（其中一遍还是
///     在循环条件里建集合）。
///
/// 只读 `lib/` 源码文本与纯函数，不涉及任何真实目录名/文件名。
void main() {
  String code(String p) => File(p)
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

  String libAll() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.readAsStringSync().replaceAll('\r\n', '\n'))
      .join('\n');

  group('1. 等级清单只有一处定义', () {
    test('AuthorGrade.gradesDescending 是 grades 的倒序（不另存一份）', () {
      expect(AuthorGrade.gradesDescending, <String>['S', 'A', 'B', 'C', 'D']);
      expect(AuthorGrade.gradesDescending.toSet(), AuthorGrade.grades.toSet());
      expect(AuthorGrade.gradesDescending.first, AuthorGrade.grades.last);
    });

    test('筛选面板两处与摘要一处都用同一个出口', () {
      final all = libAll();
      // 字面量只允许出现在 `author_grade.dart` 的注释里（说明历史缺陷）。
      final literal = RegExp(r"""['"]S['"]\s*,\s*['"]A['"]\s*,\s*['"]B["']""");
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f
            .readAsStringSync()
            .replaceAll('\r\n', '\n')
            .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '');
        if (literal.hasMatch(src)) offenders.add(f.path);
      }
      expect(offenders, isEmpty, reason: '等级字面量必须收进 AuthorGrade：$offenders');
      expect(all.contains('gradesDescending'), isTrue);
      // 两处面板 + 一处摘要都引用它。
      expect(RegExp(r'grades:\s*AuthorGrade\.gradesDescending').allMatches(all).length,
          2);
      expect(all.contains('AuthorGrade.gradesDescending.where(grades.contains)'),
          isTrue);
    });

    test('摘要里的等级顺序与面板一致（S 在前）', () {
      final st = AuthorFilterState(grades: {'S', 'A', 'C'});
      final text = st.summary();
      expect(text.contains('等级 S/A/C'), isTrue, reason: text);
    });
  });

  group('2. 基础库 → 单元库归属只有一处查询', () {
    test('unitOfBasic 查不到返回空串，查得到返回单元库 id（不猜）', () {
      final main = code('lib/main.dart');
      expect(main.contains('String unitOfBasic(String basicId) =>'), isTrue);
      expect(main.contains('topIdForBasic(String basicId) => topIdFor(unitOfBasic(basicId))'),
          isTrue);
    });

    test('main.dart 里不再直接下标 basicToUnit', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f
            .readAsStringSync()
            .replaceAll('\r\n', '\n')
            .replaceAll(RegExp(r'^\s*///.*$', multiLine: true), '');
        // 唯一允许的实现处是 author_filter_options 的纯函数。
        if (src.contains('basicToUnit[') &&
            !f.path.endsWith('author_filter_options.dart')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '基础库→单元库归属必须走一个出口：$offenders');
    });

    test('回落 secret 的口径在调用点显式写出来，不再藏在 ?? 里', () {
      final main = code('lib/main.dart');
      final start = main.indexOf('String unitIdFor(String mediaPath) {');
      final end = main.indexOf('String unitNameOf(String id) {');
      expect(start, greaterThan(0));
      final body = main.substring(start, end);
      expect(body.contains("unit.isEmpty ? 'secret' : unit"), isTrue);
      expect(body.contains('basicToUnit['), isFalse);
    });
  });

  group('3. 筛选面板「已被单元库接管」只有一处判定', () {
    test('_takenOver 只算一次，迁移与画 chip 共用', () {
      final ui = code('lib/author_filter_ui.dart');
      expect(ui.contains('Set<String> _takenOver = const <String>{};'), isTrue);
      // 循环条件里不再建集合（旧写法 O(n²) 且第二份判定）。
      expect(ui.contains('{for (final u in widget.units) u.id}.contains('), isFalse);
      expect(RegExp(r'_takenOver\.contains\(').allMatches(ui).length, 2);
      // 集合只在 initState / didUpdateWidget 两处重算（一个入口函数）。
      expect(RegExp(r'_takenOver = _unitIds\(\);').allMatches(ui).length, 2);
    });

    test('面板开着时新到达的单元库仍会迁移（didUpdateWidget 重跑）', () {
      final ui = code('lib/author_filter_ui.dart');
      final start = ui.indexOf('void didUpdateWidget(');
      expect(start, greaterThan(0));
      final body = ui.substring(start, start + 400);
      expect(body.contains('_migrateLegacyBigs(f)'), isTrue);
    });
  });

  group('4. 等级入口文案不再承诺不存在的可写项', () {
    test('设置页「作者等级」副标题说明只读', () {
      final main = code('lib/main.dart');
      expect(main.contains('门槛可调'), isFalse,
          reason: '等级页没有任何可写控件，入口不能承诺「可调」');
      expect(main.contains('由服务端统一管理，此处只读'), isTrue);
    });
  });

  group('5. 作品类型筛选仍按 workFilterOrder（顺序不因本轮变化）', () {
    test('类型 chip 顺序仍来自唯一常量', () {
      final ui = code('lib/author_filter_ui.dart');
      expect(ui.contains('for (final t in workFilterOrder)'), isTrue);
      expect(workFilterOrder.toSet().length, workFilterOrder.length);
    });
  });
}
