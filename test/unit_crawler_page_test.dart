import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoucangjia/unit_crawler_page.dart';
import 'package:shoucangjia/unit_library.dart';

UnitLibrary unit() => UnitLibrary(
      node: const LibNode(id: 'big-01', rel: '(1) A', name: '(1) A'),
      basics: const [],
      children: const [],
    );

Map<String, dynamic> state({List<Map<String, dynamic>> scripts = const []}) => {
      'ok': true,
      'path': '/root/(1) A',
      'crawler': {
        'enabled': false,
        'schedule': '04:10',
        'intervalMin': 0,
        'note': '',
        'script': 'sync.sh',
      },
      'scripts': scripts,
      'hasScript': scripts.any((s) => s['name'] == 'sync.sh'),
      'running': null,
    };

Widget host(http.Client client) => MaterialApp(
      home: UnitCrawlerPage(
        unit: unit(),
        base: 'http://nas:8090',
        headers: const {'Authorization': 'Basic x'},
        client: client,
      ),
    );

void main() {
  testWidgets('无脚本时同步设置置灰并提示 J17', (t) async {
    final client = MockClient((req) async {
      expect(req.url.path, '/api/unit/crawler');
      expect(req.url.queryParameters['unit'], 'big-01');
      expect(req.url.queryParameters['rel'], '(1) A');
      return http.Response(jsonEncode(state()), 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(find.textContaining('J17'), findsOneWidget);
    expect(find.textContaining('无爬虫脚本，同步设置不可用'), findsOneWidget);
    expect(find.byKey(const ValueKey('unit-crawler-script')), findsNothing);
    final sw = t.widget<SwitchListTile>(
        find.byKey(const ValueKey('unit-crawler-enabled')));
    expect(sw.onChanged, isNull);
    await t.drag(find.byType(ListView), const Offset(0, -400));
    await t.pumpAndSettle();
    final run = t.widget<FilledButton>(
        find.byKey(const ValueKey('unit-crawler-run')));
    expect(run.onPressed, isNull);
  });

  testWidgets('有脚本时可保存并选择脚本', (t) async {
    var posts = 0;
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        posts++;
        return http.Response(jsonEncode(state(scripts: [
          {'name': 'sync.sh', 'size': 12}
        ])), 200);
      }
      return http.Response(
          jsonEncode(state(scripts: [
            {'name': 'sync.sh', 'size': 12}
          ])),
          200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(find.textContaining('已配置脚本：sync.sh'), findsOneWidget);
    final sw = t.widget<SwitchListTile>(
        find.byKey(const ValueKey('unit-crawler-enabled')));
    expect(sw.onChanged, isNotNull);
    await t.tap(find.byKey(const ValueKey('unit-crawler-enabled')));
    await t.pumpAndSettle();
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(posts, 1);
    expect(find.text('单元库爬虫配置已保存'), findsOneWidget);
  });
}
