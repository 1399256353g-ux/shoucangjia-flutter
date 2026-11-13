import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/collection_sync.dart';

void main() {
  test('H11 解析账号全部收藏夹：按服务端顺序、过滤墓碑、不加序号', () {
    final rows = parseCollectionSettings({
      'accountCount': 3,
      'collections': [
        {
          'idx': 2,
          'name': '丝',
          'count': 763,
          'sync': true,
          'inIndex': true,
          'account': true,
        },
        {
          'idx': 4,
          'name': '南宁',
          'count': 87,
          'sync': false,
          'inIndex': false,
          'account': true,
        },
        {
          'idx': 8,
          'name': '🦶',
          'count': 12,
          'sync': true,
          'inIndex': false,
          'account': true,
        },
        {
          'idx': 6,
          'name': '已删除',
          'count': 0,
          'deleted': true,
        },
      ],
    });
    expect(rows.map((e) => e.idx), [2, 4, 8]);
    expect(rows.map((e) => e.name), ['丝', '南宁', '🦶']);
    // 名称与账号一致：不出现 "2 丝" / "丝 (2)" 之类的序号
    for (final r in rows) {
      expect(r.name.startsWith('${r.idx} '), isFalse);
      expect(r.name.contains('(${r.idx})'), isFalse);
    }
  });

  test('H11 未勾选不参与同步且主页不显示', () {
    final rows = parseCollectionSettings({
      'collections': [
        {
          'idx': 4,
          'name': '南宁',
          'count': 87,
          'sync': false,
          'inIndex': false,
          'account': true
        },
        {
          'idx': 2,
          'name': '丝',
          'count': 763,
          'sync': true,
          'inIndex': true,
          'account': true
        },
      ],
    });
    expect(rows[0].sync, isFalse);
    expect(rows[0].visible, isFalse);
    expect(rows[0].subtitle, contains('不参与同步'));
    expect(rows[0].subtitle, contains('账号中 · 未下载'));
    expect(rows[0].subtitle, isNot(contains('序号')));
    expect(rows[1].visible, isTrue);
  });

  test('H11 全选/全不选只改勾选状态', () {
    final rows = parseCollectionSettings({
      'collections': [
        {'idx': 1, 'name': '其他', 'count': 10, 'sync': true},
        {'idx': 2, 'name': '丝', 'count': 20, 'sync': false},
      ],
    });
    final none = setAllSync(rows, false);
    expect(none.every((e) => !e.sync), isTrue);
    expect(none.map((e) => e.name), ['其他', '丝']);
    final all = setAllSync(none, true);
    expect(all.every((e) => e.sync), isTrue);
  });

  test('H11 服务端 accountCount 缺省时按账号项统计', () {
    final rows = parseCollectionSettings({
      'collections': [
        {'idx': 1, 'name': 'A', 'account': true, 'sync': true},
        {'idx': 2, 'name': 'B', 'sync': true},
      ],
    });
    expect(rows.where((e) => e.account).length, 1);
    expect(rows.length, 2);
  });
}
