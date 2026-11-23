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

  test('新版字段 lib 与同步批次分组/去重', () {
    final r = parseDeletedReport({
      'total': 3,
      'updated': 1795215450,
      'items': [
        {
          'at': '2026-11-20T22:57:30.889Z',
          'a': '作者A',
          'id': '1',
          't': 'A',
          'lib': '(2) douyin',
        },
        {
          'at': '2026-11-20T22:57:31.001Z',
          'a': '作者B',
          'id': '2',
          't': 'B',
          'lib': '(2) douyin',
        },
        // 同一轮同步里同一作品重复写入 → 去重
        {
          'at': '2026-11-20T22:57:31.002Z',
          'a': '作者A',
          'id': '1',
          't': 'A',
          'lib': '(2) douyin',
        },
      ],
    });
    expect(r.items.length, 2);
    expect(r.items.first.libName, '(2) douyin');
    expect(r.items.first.foundLabel, contains('同步发现'));
    final groups = groupDeletedBySync(r.items);
    expect(groups.length, 1);
    expect(groups.first.items.length, 2);
    expect(groups.first.label, isNotEmpty);
    expect(r.lastDiscoveryLabel, isNotEmpty);
  });

  test('兼容顶层数组与 records/deleted 键', () {
    final arr = parseDeletedReport([
      {'at': '2026-11-20T22:57:30Z', 't': 'A', 'id': '1'}
    ]);
    expect(arr.total, 1);
    expect(arr.items.length, 1);
    final rec = parseDeletedReport({
      'records': [
        {'at': '2026-11-20T22:57:30Z', 't': 'B', 'id': '2'}
      ]
    });
    expect(rec.items.single.title, 'B');
  });

  test('三态：只有曾落地的才算已删除，未落地判抓取失败', () {
    final r = parseDeletedReport({
      'total': 4,
      'items': [
        {
          'at': '2026-11-20T22:57:30Z',
          'id': '1',
          't': 'A',
          'st': 'deleted',
          'lib': '(2) douyin',
          'libId': 'lib-008',
        },
        {'at': '2026-11-20T22:57:31Z', 'id': '2', 't': 'B', 'st': 'failed'},
        {'at': '2026-11-20T22:57:32Z', 'id': '3', 't': 'C', 'st': 'landed'},
        // 旧服务端没有 st → 按已删除（历史行为）
        {'at': '2026-11-20T22:57:33Z', 'id': '4', 't': 'D'},
      ],
    });
    expect(r.items[0].state, DeletedState.deleted);
    expect(r.items[0].libId, 'lib-008');
    expect(r.items[1].state, DeletedState.failed);
    expect(r.items[2].state, DeletedState.landed);
    expect(r.items[3].state, DeletedState.deleted);

    final stats = DeletedStats.of(r.items);
    expect(stats.deleted, 2); // 只有 st=deleted + 旧数据兜底
    expect(stats.failed, 1);
    expect(stats.landed, 1);
    expect(stats.total, 4);
    expect(stats.label, contains('已删除 2'));
    expect(stats.label, contains('抓取失败 1（可重试）'));
    expect(stats.label, contains('已落地 1'));
    expect(deletedStateLabel(DeletedState.failed), '抓取失败');
  });

  test('作品跳转地址：带 libId 与 id，缺 base/id 返回 null', () {
    const e = DeletedEntry(
      at: '',
      author: 'A',
      date: '',
      title: 'T',
      workId: '7300000000000000000',
      collection: '',
      link: 'https://x/1',
      cover: '',
      libId: 'lib-008',
    );
    final u = deletedWorkUri('http://nas:8090', e)!;
    expect(u.path, '/api/work.json');
    expect(u.queryParameters['id'], '7300000000000000000');
    expect(u.queryParameters['lib'], 'lib-008');
    expect(deletedWorkUri('', e), isNull);
    expect(
        deletedWorkUri(
            'http://nas:8090',
            const DeletedEntry(
              at: '',
              author: '',
              date: '',
              title: '',
              workId: '',
              collection: '',
              link: '',
              cover: '',
            )),
        isNull);
    final noLib = deletedWorkUri('http://nas:8090', e.copyWith(libId: ''))!;
    expect(noLib.queryParameters.containsKey('lib'), isFalse);
    expect(kDeletedNotLocalMessage, '仅在收藏列表出现过，未同步到本地');
  });
}
