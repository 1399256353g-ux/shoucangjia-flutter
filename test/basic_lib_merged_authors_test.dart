import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/basic_lib_page.dart';

/// owner 2026-11-28：「作者没有真正在 app 中合并」。
///
/// 基础库页以前读 `/api/lib/<本库>/index.json`，只含本库作者，同名作者在
/// 兄弟基础库也有目录时被拆成多张卡。合并信息只在单元库范围
/// （`/api/unit/authors.json?unit=`）。这里锁定「转成同形 + 只留本库的」。
void main() {
  List<int> body() => utf8.encode(jsonEncode({
        'ok': true,
        'unit': '(2) AV',
        'cards': [
          {
            'name': '同一个作者',
            'works': 9,
            'av': '/media/lib-001/x.jpg',
            'bio': 'b',
            'files': [
              {'lib': 'lib-001', 'authorDir': '@同一个作者'},
              {'lib': 'lib-002', 'authorDir': '@同一个作者'},
              {'lib': 'lib-003', 'authorDir': '@同一个作者'},
            ],
          },
          {
            'name': '只在别库',
            'works': 3,
            'files': [
              {'lib': 'lib-002', 'authorDir': '@只在别库'},
            ],
          },
          {
            'name': '只在本库',
            'works': 2,
            'files': [
              {'lib': 'lib-001', 'authorDir': '@只在本库'},
            ],
          },
        ],
      }));

  test('同一作者跨 3 个库 → 本库页只出现一条，作品数是合计', () {
    final m = mergedAuthorsInLibForTest(body(), 'lib-001');
    expect(m, isNotNull);
    final authors = (m!['authors'] as List).cast<Map>();
    final names = authors.map((e) => e['name']).toList();
    expect(names, contains('同一个作者'));
    expect(names, contains('只在本库'));
    // 不在本库的作者不得出现。
    expect(names, isNot(contains('只在别库')));
    final merged = authors.firstWhere((e) => e['name'] == '同一个作者');
    expect(merged['works'], 9);
    expect(merged['_fileCount'], 3);
    expect(merged['_merged'], isTrue);
  });

  test('坏响应返回 null（调用方回退单库索引）', () {
    expect(mergedAuthorsInLibForTest(utf8.encode('not json'), 'lib-001'), isNull);
    expect(mergedAuthorsInLibForTest(utf8.encode('{"ok":true}'), 'lib-001'),
        isNull);
  });

  test('本库没有任何目录 → 空列表，不是 null', () {
    final m = mergedAuthorsInLibForTest(body(), 'lib-999');
    expect(m, isNotNull);
    expect((m!['authors'] as List), isEmpty);
  });
}
