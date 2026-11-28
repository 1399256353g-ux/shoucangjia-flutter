import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_author_groups.dart';
import 'package:shoucangjia/unit_author_mount_page.dart';
import 'package:shoucangjia/unit_library.dart';

/// owner 2026-11-28：
/// > 「挂载还是不行，原来的那些设置逻辑特别混乱啊根本没法用，删掉啊还留着干嘛」
///
/// 旧的目录树那套（合并 / 拆出成员 / 编辑成员三个对话框 + `AuthorFilePicker`）
/// 已整体删除。本页只剩两件事：勾基础库建目录、对跨基础库的组拆出/解散。
///
/// 判据只用请求路径/请求体与界面结构性文本，不涉及任何真实作者名或目录内容。

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
        BasicLib(
            id: 'lib-2',
            name: 'B2',
            rel: '(1) A/y',
            bigId: '',
            authors: 1,
            works: 3),
      ],
      children: const [],
    );

Widget host(http.Client client) => MaterialApp(
      home: UnitAuthorMountPage(
        unit: unit(),
        base: 'http://nas:8090',
        headers: const {'Authorization': 'Basic test'},
        client: client,
      ),
    );

http.Response res(Object body, int code) => http.Response.bytes(
      utf8.encode(body is String ? body : jsonEncode(body)),
      code,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  testWidgets('首屏只请求分组表（目录树那两个请求已删）', (t) async {
    final seen = <String>[];
    final client = MockClient((req) async {
      seen.add(req.url.path);
      expect(req.url.queryParameters['unit'], '(1) A');
      return res({'ok': true, 'unit': '(1) A', 'groups': [], 'auto': []}, 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(seen, ['/api/unit-author-groups.json'],
        reason: '旧实现还多取作者卡与全部目录喂目录树；树删了，请求也删了');
    expect(find.textContaining('选基础库'), findsOneWidget);
    expect(find.textContaining('跨基础库合并 0'), findsOneWidget);
  });

  testWidgets('列出直属单元库下的基础库，可勾选', (t) async {
    final client = MockClient((req) async {
      return res({'ok': true, 'unit': '(1) A', 'groups': [], 'auto': []}, 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('uag-scope-lib-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('uag-scope-lib-2')), findsOneWidget);
    // 一个都没勾时不出现建目录按钮。
    expect(find.byKey(const ValueKey('uag-create-dirs')), findsNothing);

    await t.tap(find.byKey(const ValueKey('uag-scope-lib-1')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('uag-create-dirs')), findsOneWidget);
  });

  testWidgets('建目录：只对勾选的基础库发 create，单位是基础库', (t) async {
    final posts = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        posts.add(jsonDecode(req.body) as Map<String, dynamic>);
        return res({'ok': true}, 200);
      }
      return res({'ok': true, 'unit': '(1) A', 'groups': [], 'auto': []}, 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('uag-scope-lib-1')));
    await t.tap(find.byKey(const ValueKey('uag-scope-lib-2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uag-create-dirs')));
    await t.pumpAndSettle();

    await t.enterText(
        find.byKey(const ValueKey('uag-create-dir-name')), '某人');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uag-create-dir-ok')));
    await t.pumpAndSettle();

    expect(posts.length, 2);
    expect(posts[0], {'lib': 'lib-1', 'name': '@某人'});
    expect(posts[1], {'lib': 'lib-2', 'name': '@某人'});
  });

  testWidgets('跨基础库的组：显示基础库个数，可拆出', (t) async {
    final posts = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        posts.add(jsonDecode(req.body) as Map<String, dynamic>);
        return res({'ok': true, 'unit': '(1) A'}, 200);
      }
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
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    // 副标题走 `g.summary`（`authorMergeSummary` 唯一出口），不再自拼
    // 「N 个基础库 · N 个目录」——那正是契约禁止的手写插值。
    expect(find.textContaining('合并 2 个文件夹'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('uag-split-mg_1')));
    await t.pumpAndSettle();
    // 候选是基础库，不是作者目录。
    expect(find.byKey(const ValueKey('uag-split-lib-lib-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('uag-split-lib-lib-2')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('uag-split-lib-lib-2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uag-split-ok')));
    await t.pumpAndSettle();

    expect(posts.length, 1);
    expect(posts.first['action'], 'split');
    expect(posts.first['groupId'], 'mg_1');
    expect(posts.first['files'], [
      {'lib': 'lib-2', 'authorDir': '@a'}
    ]);
  });

  testWidgets('只勾一个基础库时拆出按钮禁用（全部拆走等于解散）', (t) async {
    final client = MockClient((req) async {
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
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('uag-split-mg_1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('uag-split-lib-lib-1')));
    await t.tap(find.byKey(const ValueKey('uag-split-lib-lib-2')));
    await t.pumpAndSettle();

    final btn = t.widget<FilledButton>(
        find.byKey(const ValueKey('uag-split-ok')));
    expect(btn.onPressed, isNull, reason: '全选等于解散，服务端也会 400');
  });

  testWidgets('GET 失败显示错误块与重试按钮', (t) async {
    final client = MockClient((req) async {
      return res({'ok': false, 'error': '单元库目录不存在'}, 400);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(find.textContaining('单元库目录不存在'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('自动合并组可「固定为手动组」，发 merge', (t) async {
    final posts = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.method == 'POST') {
        posts.add(jsonDecode(req.body) as Map<String, dynamic>);
        return res({'ok': true, 'unit': '(1) A', 'groupId': 'mg_new'}, 200);
      }
      return res({
        'ok': true,
        'unit': '(1) A',
        'groups': [],
        'auto': [
          {
            'id': 'ag_1',
            'name': '乙',
            'auto': true,
            'files': [
              {'lib': 'lib-1', 'authorDir': '@b'},
              {'lib': 'lib-2', 'authorDir': '@b'},
            ],
          }
        ],
      }, 200);
    });
    await t.pumpWidget(host(client));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('uag-auto-ag_1')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('uag-pin-ag_1')));
    await t.pumpAndSettle();

    expect(posts.length, 1);
    expect(posts.first['action'], 'merge');
    expect(posts.first['unit'], '(1) A');
    expect(posts.first['files'], [
      {'lib': 'lib-1', 'authorDir': '@b'},
      {'lib': 'lib-2', 'authorDir': '@b'},
    ]);
  });

  test('旧的目录树那套源码已整体删除（不是藏起来）', () {
    // owner：「原来的那些设置逻辑特别混乱啊根本没法用，删掉啊还留着干嘛」。
    // 这条钉在源码文本上：旧控件与三个旧对话框不许以任何形式复活。
    final src = File('lib/unit_author_mount_page.dart').readAsStringSync();
    for (final gone in const [
      'AuthorFilePicker',
      "'uag-pick'",
      "'uag-setfiles'",
      '合并作者',
      '_openMerge',
      '_openSetFiles',
      '_labelOf',
      'allFiles',
    ]) {
      expect(src.contains(gone), isFalse, reason: '旧逻辑残留：$gone');
    }
    // `uag-split-ok` 保留：它是**新**的基础库拆出确认键，与旧目录树无关。
    expect(src.contains('uag-split-lib-'), isTrue);
    expect(src.contains("'uag-scope-"), isTrue);
  });
}
