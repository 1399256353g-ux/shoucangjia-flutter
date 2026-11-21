import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoucangjia/collection_sync_panel.dart';

void main() {
  testWidgets('单元库同步源只显示同名项，勾选写回 /api/settings', (t) async {
    Map<String, dynamic> settings() => {
          'default': 2,
          'collections': [
            {
              'idx': 1,
              'name': '其他',
              'count': 10,
              'sync': true,
              'inIndex': true,
              'account': true,
            },
            {
              'idx': 2,
              'name': '丝',
              'count': 20,
              'sync': true,
              'inIndex': true,
              'account': true,
            },
            {
              'idx': 4,
              'name': '南宁',
              'count': 5,
              'sync': false,
              'account': true,
            },
          ],
        };
    Map<String, dynamic>? posted;
    final client = MockClient((req) async {
      expect(req.url.path, '/api/settings');
      http.Response ok() => http.Response.bytes(
          utf8.encode(jsonEncode(settings())), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
      if (req.method == 'POST') {
        posted = jsonDecode(req.body) as Map<String, dynamic>;
        return ok();
      }
      return ok();
    });

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CollectionSyncPanel(
            base: 'http://nas:8090',
            headers: const {'Authorization': 'Basic x'},
            libId: 'douyin',
            unitName: '(2) 丝',
            unitRel: '(2) douyin/(2) 丝',
            client: client,
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('丝'), findsOneWidget);
    expect(find.text('其他'), findsNothing);
    expect(find.text('南宁'), findsNothing);
    expect(find.textContaining('1 个参与同步'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('unit-sync-2')));
    await t.pumpAndSettle();
    expect(posted, isNotNull);
    final list = (posted!['collections'] as List)
        .cast<Map<String, dynamic>>();
    // 未显示的同步源也要原样写回，不能因为页面只显示一项就丢掉其它项。
    expect(list.length, 3);
    expect(list.firstWhere((e) => e['idx'] == 2)['sync'], isFalse);
  });
}
