/// 第七十一批契约（0.9.293）：**「这条作品属于哪个库」有 18 种写法**。
///
/// 跨库列表（收藏夹 / 搜索 / 推荐 / 作者合并）给每条作品挂 `_lib`。读它
/// 这件事分成两种**语义不同**的用途，此前混在同一个表达式里：
///
/// | 用途 | 写法 | 出错后果 |
/// |---|---|---|
/// | 分组 / 去重键 / 「有没有来源」 | 只取原值 | 兜底后无来源条目与当前库条目并成一组 |
/// | 取鉴权头 / 拼媒体地址 | 必须兜底 | 空 lib → 不带 `Authorization` → 401 白图 |
///
/// 于是同一行代码既做判定又做兜底：改判定就会连带改坏请求头。另有
/// `'${e['_lib']}'` 这种写法，字段缺失时得到**字面量 `"null"`**——比空串
/// 更难发现，`metas['null']` 取不到，静默退化成「无元数据」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/work_lib.dart';

/// 去掉整行注释后再做「有没有第二个实现」的扫描。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('workLibTag：只取原值，绝不兜底（0.9.293）', () {
    test('有标记取标记，无标记/非 Map 都返回空串', () {
      expect(workLibTag({'id': '1', '_lib': 'douyin'}), 'douyin');
      expect(workLibTag({'id': '1'}), '', reason: '没有标记就是空，不猜当前库');
      expect(workLibTag({'id': '1', '_lib': '  '}), '', reason: '空白等同没有');
      expect(workLibTag(null), '');
      expect(workLibTag('not a map'), '');
    });

    test('非字符串标记按字符串处理，不抛异常', () {
      expect(workLibTag({'_lib': 42}), '42');
    });
  });

  group('workLibOf：需要请求库时才兜底（0.9.293）', () {
    test('有标记用标记，忽略 fallback', () {
      expect(workLibOf({'_lib': 'a'}, fallback: 'b'), 'a');
    });

    test('无标记才用 fallback；fallback 也空就返回空串', () {
      expect(workLibOf({'id': '1'}, fallback: 'b'), 'b');
      expect(workLibOf({'id': '1'}), '',
          reason: '不知道该属于哪个库时不替它猜');
      expect(workLibOf({'id': '1'}, fallback: '  '), '');
    });

    test('标记存在但为空白时仍走 fallback', () {
      expect(workLibOf({'_lib': '   '}, fallback: 'b'), 'b');
    });

    test('两边都 trim：带空格的标记不会被当成另一个库', () {
      expect(workLibOf({'_lib': ' a '}, fallback: 'b'), 'a');
      expect(workLibTag({'_lib': ' a '}), 'a');
    });
  });

  group('withWorkLib：写入侧唯一入口（0.9.293）', () {
    test('返回新 Map，不改入参', () {
      final src = <String, dynamic>{'id': '1'};
      final out = withWorkLib(src, 'lib1');
      expect(out['_lib'], 'lib1');
      expect(out['id'], '1');
      expect(src.containsKey('_lib'), isFalse, reason: '不得改入参');
    });

    test('覆盖已有标记并 trim', () {
      final out = withWorkLib({'_lib': 'old', 'id': '1'}, ' new ');
      expect(out['_lib'], 'new');
    });
  });

  group('契约扫描（0.9.293）', () {
    test('main 里不再有「字段缺失得到字面量 null」的插值写法', () {
      final main = _code('lib/main.dart');
      final nullish = RegExp(r"'\\\$\{(e|w|m)\[._lib.\]\}'");
      expect(nullish.hasMatch(main), isFalse);
    });

    test('main / author_merge 不再各自拼 _lib 的兜底', () {
      final main = _code('lib/main.dart');
      final merge = _code('lib/author_merge.dart');
      final inline = RegExp(r"'\$\{(e|w|m)\[._lib.\] \?\? ''\}'");
      for (final src in [main, merge]) {
        expect(inline.hasMatch(src), isFalse);
      }
      // workLibOf / workLibTag / withWorkLib 必须真的被用起来。
      expect('workLibOf('.allMatches(main).length, greaterThanOrEqualTo(4));
      expect(main.contains('workLibTag('), isTrue);
      expect(merge.contains('workLibOf('), isTrue);
    });

    test('写入侧五处 map 展开只剩 withWorkLib（不新增第六份）', () {
      final main = _code('lib/main.dart');
      // 只剩两处 map 字面量：作者合并结果（`'_lib': j.lib`）与把它转发给
      // 网格（`'_lib': workLibTag(e)`，值已由 work_lib 归一）。
      // 只要出现第三处，就说明又手拼了一份写入。
      final writes = RegExp(r"'_lib':").allMatches(main).length;
      expect(writes, 2, reason: '新写一条 `_lib:` 就说明又手拼了一处');
    });
  });
}
