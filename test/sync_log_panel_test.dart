import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoucangjia/sync_log_panel.dart';

Map<String, dynamic> logsResponse() => {
      'ok': true,
      'keptDays': 7,
      'total': 2,
      'runs': [
        {
          'id': 'r-1',
          'at': 1795427100000,
          'ended': 1795427102400,
          'lib': 'douyin',
          'unit': '(1) A/(2) B',
          'mode': 'quick',
          'script': 'sync.sh',
          'ok': 3,
          'fail': 1,
          'deleted': 1,
          'ms': 2400,
          'exit': 0,
          'running': false,
          'itemsTotal': 3,
          'items': [
            {'id': 'w1', 't': '作品一', 'a': '作者一', 'st': 'landed'},
            {'id': 'w2', 't': '作品二', 'st': 'failed', 'why': 'fetch'},
            {'id': 'w3', 't': '作品三', 'st': 'deleted'},
          ],
        },
        {
          'id': 'r-2',
          'at': 1795327100000,
          'mode': 'full',
          'ok': 12,
          'fail': 0,
          'deleted': 0,
          'ms': 61000,
          'exit': 0,
          'items': <dynamic>[],
        },
      ],
    };

Widget host(http.Client client) => MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          SyncLogPanel(
            base: 'http://nas:8090',
            headers: const {'Authorization': 'Basic x'},
            libId: 'douyin',
            client: client,
          ),
        ]),
      ),
    );

void main() {
  testWidgets('同步日志：展示轮次摘要，展开后失败项可单条重试', (t) async {
    final calls = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.url.path == '/api/sync/logs') {
        expect(req.url.queryParameters['lib'], 'douyin');
        return http.Response(jsonEncode(logsResponse()), 200,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }
      if (req.url.path == '/api/sync/retry') {
        calls.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(
            jsonEncode({'ok': true, 'retried': 1, 'retryRunId': 'r-9'}), 200,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('not found', 404);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(find.text('同步日志'), findsOneWidget);
    expect(find.textContaining('保留 7 天'), findsOneWidget);
    expect(find.textContaining('成功 3'), findsOneWidget);
    expect(find.textContaining('全量'), findsOneWidget);

    // 展开第一轮
    await t.tap(find.textContaining('成功 3'));
    await t.pumpAndSettle();
    expect(find.text('作品一'), findsOneWidget);
    expect(find.textContaining('抓取失败 · w2'), findsOneWidget);
    expect(find.textContaining('全部重试（1）'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('sync-item-retry-r-1-w2')));
    await t.pumpAndSettle();
    expect(calls.length, 1);
    expect(calls.first['runId'], 'r-1');
    expect(calls.first['ids'], ['w2']);
    expect(find.textContaining('已开始重试 1 条'), findsOneWidget);
  });

  testWidgets('同步日志：重试失败展示服务端错误', (t) async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/sync/logs') {
        return http.Response(jsonEncode(logsResponse()), 200,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }
      if (req.url.path == '/api/sync/retry') {
        return http.Response(
            jsonEncode({'ok': false, 'error': '缺少 ids'}), 400,
            headers: const {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('not found', 404);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('成功 3'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('sync-retry-all-r-1')));
    await t.pumpAndSettle();
    expect(find.textContaining('重试失败：缺少 ids'), findsOneWidget);
  });

  testWidgets('同步日志：读取失败有提示且可重试', (t) async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      if (calls == 1) return http.Response('boom', 500);
      return http.Response(jsonEncode(logsResponse()), 200,
          headers: const {'content-type': 'application/json; charset=utf-8'});
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();
    expect(find.textContaining('同步日志读取失败'), findsOneWidget);
    await t.tap(find.text('重试'));
    await t.pumpAndSettle();
    expect(find.textContaining('成功 3'), findsOneWidget);
  });
}
