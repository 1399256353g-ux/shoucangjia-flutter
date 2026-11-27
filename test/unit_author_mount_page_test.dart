import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_author_groups.dart';
import 'package:shoucangjia/unit_author_mount_page.dart';
import 'package:shoucangjia/unit_library.dart';

// A1：挂载面板的接线测试。判据只用请求路径/请求体与界面结构性文本，
// 不涉及任何真实作者名或目录内容。

UnitLibrary unit() => UnitLibrary(
      node: const LibNode(id: 'node:(1) A', rel: '(1) A', name: '(1) A'),
      basics: const [
        BasicLib(
            id: 'lib-1',
            name: 'B1',
            rel: '(1) A/x',
            bigId: '',
            authors: 2,
            works: 9),
      ],
      children: const [],
    );

Widget host(http.Client client) => MaterialApp(
      home: UnitAuthorMountPage(
        unit: unit(),
        base: 'http://nas:8090',
        headers: const {'Authorization': 'Basic ***'},
        client: client,
      ),
    );

/// `http.Response(String)` 按 latin1 编码，中文会变成「Contains invalid
/// characters」。测试一律用字节构造（服务端输出的就是 UTF-8）。
http.Response res(Object body, int code) => http.Response.bytes(
      utf8.encode(body is String ? body : jsonEncode(body)),
      code,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  testWidgets('首屏同时请求分组、作者卡与全部目录，三个地址都带 unit', (t) async {
    final seen = <String>[];
    final client = MockClient((req) async {
      seen.add(req.url.path);
      expect(req.url.queryParameters['unit'], '(1) A');
      if (req.url.path == '/api/unit-author-groups.json') {
        return res(
            {'ok': true, 'unit': '(1) A', 'groups': [], 'auto': []}, 200);
      }
      if (req.url.path == '/api/unit/authors') {
        // 候选池：该单元库下全部作者目录（owner 2026-11-27）。
        return res({
          'ok': true,
          'unit': '(1) A',
          'basics': [],
          'items': [],
          'autoGroups': [],
          'groups': [],
        }, 200);
      }
      expect(req.url.path, '/api/unit/authors.json');
      return res({'ok': true, 'unit': '(1) A', 'cards': []}, 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(seen, [
      '/api/unit-author-groups.json',
      '/api/unit/authors.json',
      '/api/unit/authors',
    ]);
    expect(find.textContaining('已挂载的手动组 0'), findsOneWidget);
    expect(find.textContaining('可自动合并 0'), findsOneWidget);
  });

  testWidgets('手动组列出成员数，派生组给「固定为手动组」按钮', (t) async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/unit-author-groups.json') {
        return res({
          'ok': true,
          'unit': '(1) A',
          'groups': [
            {
              'id': 'mg_1',
              'name': '组一',
              'files': [
                {'lib': 'lib-1', 'authorDir': '@a'},
                {'lib': 'lib-2', 'authorDir': '@a'},
              ],
              'works': 4,
            }
          ],
          'auto': [
            {
              'id': 'ag_1',
              'name': '组二',
              'files': [
                {'lib': 'lib-1', 'authorDir': '@b'},
                {'lib': 'lib-2', 'authorDir': '@b'},
              ],
              'auto': true,
            }
          ],
        }, 200);
      }
      return res({'ok': true, 'unit': '(1) A', 'cards': []}, 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(find.textContaining('已挂载的手动组 1'), findsOneWidget);
    expect(find.textContaining('可自动合并 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('uag-group-mg_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('uag-auto-ag_1')), findsOneWidget);
    expect(find.text('固定为手动组'), findsOneWidget);
    expect(find.textContaining('2 个文件夹'), findsWidgets);
  });

  testWidgets('派生组里的成员被手动组占用后不再重复出现', (t) async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/unit-author-groups.json') {
        return res({
          'ok': true,
          'unit': '(1) A',
          'groups': [
            {
              'id': 'mg_1',
              'name': '组一',
              'files': [
                {'lib': 'lib-1', 'authorDir': '@a'},
                {'lib': 'lib-2', 'authorDir': '@a'},
              ],
            }
          ],
          'auto': [
            {
              'id': 'ag_1',
              'name': '组一',
              'auto': true,
              'files': [
                {'lib': 'lib-1', 'authorDir': '@a'},
                {'lib': 'lib-2', 'authorDir': '@a'},
              ],
            }
          ],
        }, 200);
      }
      return res({'ok': true, 'cards': []}, 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('uag-auto-ag_1')), findsNothing,
        reason: '两个成员都已被手动组占用，派生组只剩 0 个可合并成员');
  });

  testWidgets('GET 失败显示错误块与重试按钮', (t) async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      if (req.url.path == '/api/unit-author-groups.json') {
        return res({'ok': false, 'error': '单元库目录不存在'}, 400);
      }
      return res({'ok': true, 'cards': []}, 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(find.textContaining('单元库目录不存在'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(calls, greaterThanOrEqualTo(1));
  });

  testWidgets('合并请求体：action=merge、unit 用 rel、files 为勾选项', (t) async {
    final posts = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        posts.add(jsonDecode(req.body) as Map<String, dynamic>);
        return res({'ok': true, 'unit': '(1) A', 'groupId': 'mg_new'}, 200);
      }
      if (req.url.path == '/api/unit-author-groups.json') {
        return res(
            {'ok': true, 'unit': '(1) A', 'groups': [], 'auto': []}, 200);
      }
      // 两张作者卡：a 与 b，位于两个基础库。
      return res({
        'ok': true,
        'unit': '(1) A',
        'cards': [
          {
            'groupId': '',
            'name': '甲',
            'files': [
              {'lib': 'lib-1', 'authorDir': '@a'}
            ],
          },
          {
            'groupId': '',
            'name': '乙',
            'files': [
              {'lib': 'lib-2', 'authorDir': '@b'}
            ],
          },
        ],
      }, 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    // 勾选第一张卡（它的 key 由 lib|authorDir 组成）。
    await t.tap(find.byKey(const ValueKey('uag-pick-lib-1|@a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uag-merge-ok')));
    await t.pumpAndSettle();

    expect(posts.length, 1);
    expect(posts.first['action'], 'merge');
    expect(posts.first['unit'], '(1) A');
    expect(posts.first['files'], [
      {'lib': 'lib-1', 'authorDir': '@a'}
    ]);
    expect(posts.first.containsKey('groupId'), isFalse);
  });

  testWidgets('编辑成员：预勾原成员，取消一个勾选后发 setFiles（带 groupId）', (t) async {
    final posts = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        posts.add(jsonDecode(req.body) as Map<String, dynamic>);
        return res({'ok': true, 'unit': '(1) A'}, 200);
      }
      if (req.url.path == '/api/unit-author-groups.json') {
        return res({
          'ok': true,
          'unit': '(1) A',
          'groups': [
            {
              'id': 'mg_1',
              'name': '组一',
              'files': [
                {'lib': 'lib-1', 'authorDir': '@a'},
                {'lib': 'lib-2', 'authorDir': '@a'},
              ],
            }
          ],
          'auto': [],
        }, 200);
      }
      return res({'ok': true, 'unit': '(1) A', 'cards': []}, 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    // 打开组菜单 → 编辑成员。
    await t.tap(find.descendant(
        of: find.byKey(const ValueKey('uag-group-mg_1')),
        matching: find.byType(PopupMenuButton<UnitAuthorAction>)));
    await t.pumpAndSettle();
    await t.tap(find.text('编辑成员'));
    await t.pumpAndSettle();

    // 两个原成员都应已勾选（预勾是 setFiles 与 merge 的关键区别）。
    final first = t.widget<CheckboxListTile>(
        find.byKey(const ValueKey('uag-setfiles-lib-1|@a')));
    final second = t.widget<CheckboxListTile>(
        find.byKey(const ValueKey('uag-setfiles-lib-2|@a')));
    expect(first.value, isTrue);
    expect(second.value, isTrue);

    await t.tap(find.byKey(const ValueKey('uag-setfiles-lib-2|@a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uag-setfiles-ok')));
    await t.pumpAndSettle();

    expect(posts.length, 1);
    expect(posts.first['action'], 'setFiles');
    expect(posts.first['groupId'], 'mg_1');
    expect(posts.first['files'], [
      {'lib': 'lib-1', 'authorDir': '@a'}
    ]);
  });
}
