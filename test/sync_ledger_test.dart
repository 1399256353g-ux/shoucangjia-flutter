import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/sync_ledger.dart';

Map<String, dynamic> runJson({
  String id = 'r-1',
  int at = 1795427100000,
  String mode = 'quick',
  int ok = 3,
  int fail = 1,
  int deleted = 0,
  int ms = 2400,
  List<Map<String, dynamic>> items = const [],
}) =>
    {
      'id': id,
      'at': at,
      'ended': at + ms,
      'lib': 'douyin',
      'unit': '(1) A/(2) B',
      'mode': mode,
      'script': 'sync.sh',
      'ok': ok,
      'fail': fail,
      'deleted': deleted,
      'total': 1618,
      'ms': ms,
      'exit': 0,
      'running': false,
      'items': items,
      'itemsTotal': items.length,
    };

void main() {
  test('解析同步日志：坏数据不崩、字段归一', () {
    final log = parseSyncLog({
      'ok': true,
      'keptDays': 7,
      'total': 2,
      'runs': [
        runJson(items: [
          {'id': 'w1', 't': '作品1', 'a': '作者1', 'st': 'landed'},
          {'id': 'w2', 'st': 'failed', 'why': 'fetch', 'local': ''},
        ]),
        'bad',
        {'id': 'r-2', 'mode': 'full', 'ok': 10, 'fail': 0},
      ],
    });
    expect(log.runs.length, 2);
    expect(log.keptDays, 7);
    expect(log.total, 2);
    final r = log.runs.first;
    expect(r.modeLabel, '快检');
    expect(r.ok, 3);
    expect(r.items.length, 2);
    expect(r.items.first.stateLabel, '已落地');
    expect(r.items.last.stateLabel, '抓取失败');
    expect(r.failedIds, ['w2']);
    expect(r.hasFail, isTrue);
    expect(r.summary, contains('成功 3'));
    expect(r.summary, contains('失败 1'));
  });

  test('空/非对象返回空日志', () {
    expect(parseSyncLog(null).isEmpty, isTrue);
    expect(parseSyncLog({}).runs, isEmpty);
  });

  test('失败 id 去重且跳过空 id；无失败项时 hasFail 依赖计数', () {
    final log = parseSyncLog({
      'runs': [
        runJson(ok: 0, fail: 2, items: [
          {'id': 'w1', 'st': 'failed'},
          {'id': 'w1', 'st': 'failed'},
          {'id': '', 'st': 'failed'},
        ]),
        runJson(id: 'r-2', ok: 5, fail: 0, items: []),
      ],
    });
    expect(log.runs.first.failedIds, ['w1']);
    expect(log.runs.last.hasFail, isFalse);
    expect(log.runs.last.failedIds, isEmpty);
  });

  test('时长与时间标签', () {
    expect(syncDurationLabel(0), '—');
    expect(syncDurationLabel(820), '820ms');
    expect(syncDurationLabel(2400), '2.4s');
    expect(syncDurationLabel(65000), '1m 05s');
    expect(syncTimeLabel(0), '—');
    expect(syncTimeLabel(1795427100000), matches(RegExp(r'^\d\d-\d\d \d\d:\d\d$')));
  });

  test('请求地址与重试请求体', () {
    final u = syncLogsUri('http://nas:8090', lib: 'douyin', limit: 30);
    expect(u.path, '/api/sync/logs');
    expect(u.queryParameters['lib'], 'douyin');
    expect(u.queryParameters['limit'], '30');
    final u2 = syncLogsUri('http://nas:8090/', limit: 5);
    expect(u2.toString(), 'http://nas:8090/api/sync/logs?limit=5');
    expect(syncRetryUri('http://nas:8090').path, '/api/sync/retry');

    final body = syncRetryBody(runId: 'r-1', ids: [' a ', 'a', '', 'b']);
    expect(body['runId'], 'r-1');
    expect(body['ids'], ['a', 'b']);
    final body2 = syncRetryBody(ids: ['x']);
    expect(body2.containsKey('runId'), isFalse);
  });

  test('重试结果文案', () {
    expect(
        syncRetryResultLabel(
            200, {'ok': true, 'retried': 2, 'retryRunId': 'r-9'}),
        contains('已开始重试 2 条'));
    expect(syncRetryResultLabel(400, {'ok': false, 'error': '缺少 ids'}),
        contains('缺少 ids'));
    expect(syncRetryResultLabel(500, null), contains('HTTP 500'));
  });
}
