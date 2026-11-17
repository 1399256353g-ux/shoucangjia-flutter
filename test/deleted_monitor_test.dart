import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/deleted_monitor.dart';

void main() {
  test('解析删除监测响应，坏数据不崩', () {
    final r = parseDeletedReport({
      'total': 2,
      'updated': 1794838000,
      'items': [
        {
          'at': '2026-11-17T01:06:37.489Z',
          'a': '作者A',
          'd': '2026-09-12',
          't': '标题A',
          'id': '123',
          'c': '其他',
          'u': 'https://x/1',
          'th': '/media/douyin/a/cover.jpg'
        },
        'bad',
        {'t': '标题B'}
      ]
    });
    expect(r.total, 2);
    expect(r.items.length, 2);
    expect(r.items.first.author, '作者A');
    expect(r.items.first.hasCover, isTrue);
    expect(r.items.last.hasCover, isFalse);
    expect(r.items.first.atLabel, isNot(contains('T')));
  });

  test('非对象与空对象返回空报告', () {
    expect(parseDeletedReport(null).items, isEmpty);
    expect(parseDeletedReport({}).total, 0);
    expect(DeletedReport.empty.updatedLabel, '');
  });
}
