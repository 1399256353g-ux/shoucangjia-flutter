import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/lib_refresh_button.dart';
import 'package:shoucangjia/library_refresh.dart';

void main() {
  group('防抖', () {
    test('首次允许，窗口内拒绝，过后允许', () {
      final t0 = DateTime(2026, 11, 23, 19, 0, 0);
      expect(libRefreshAllowed(t0, null), isTrue);
      expect(libRefreshAllowed(t0.add(const Duration(seconds: 2)), t0),
          isFalse);
      expect(libRefreshAllowed(t0.add(const Duration(seconds: 3)), t0), isTrue);
    });

    test('窗口是 3 秒（owner 要求 ≥3s）', () {
      expect(kLibRefreshCooldown.inSeconds, 3);
    });
  });

  group('parseReindexResponse', () {
    test('200 + ok 行 → 成功并带作品数', () {
      final out = parseReindexResponse(
        200,
        {
          'ok': true,
          'libs': [
            {'lib': 'lib-001', 'ok': true, 'works': 42, 'authors': 3}
          ],
        },
        lib: 'lib-001',
      );
      expect(out.ok, isTrue);
      expect(out.works, 42);
      expect(out.error, isEmpty);
      expect(out.message, '已刷新 · 42 个作品');
    });

    test('207 + rolledBack → 失败并把原因原样带出（不假装成功）', () {
      final out = parseReindexResponse(
        207,
        {
          'ok': false,
          'libs': [
            {
              'lib': 'lib-029',
              'ok': false,
              'rolledBack': true,
              'error': '重建结果为 0 作品（旧索引 1 条），已保留旧索引',
            }
          ],
        },
        lib: 'lib-029',
      );
      expect(out.ok, isFalse);
      expect(out.works, isNull);
      expect(out.message, contains('已保留旧索引'));
    });

    test('顶层 error 优先于 HTTP 码出现在提示里', () {
      final out = parseReindexResponse(
        400,
        {'ok': false, 'error': '缺少 lib'},
        lib: 'lib-001',
      );
      expect(out.ok, isFalse);
      expect(out.message, '刷新失败：缺少 lib');
    });

    test('body 不是 Map 时用 HTTP 码兜底，不崩', () {
      final out = parseReindexResponse(500, 'oops', lib: 'lib-001');
      expect(out.ok, isFalse);
      expect(out.error, contains('HTTP 500'));
    });

    test('多库响应里按 lib 取自己那一行', () {
      final out = parseReindexResponse(
        200,
        {
          'ok': true,
          'libs': [
            {'lib': 'lib-002', 'ok': true, 'works': 7},
            {'lib': 'lib-003', 'ok': true, 'works': 9},
          ],
        },
        lib: 'lib-003',
      );
      expect(out.works, 9);
    });
  });

  group('runLibRefresh 编排', () {
    test('顺序固定：重建 → 重拉快照 → 清本库缓存 → 刷新列表', () async {
      final calls = <String>[];
      final out = await runLibRefresh(
        lib: 'lib-001',
        reindex: (body) async {
          calls.add('reindex:${body['lib']}');
          return (status: 200, body: <String, dynamic>{
            'ok': true,
            'libs': [
              {'lib': 'lib-001', 'ok': true, 'works': 12}
            ],
          });
        },
        reloadLibraries: () async => calls.add('reloadLibs'),
        clearLibCovers: () async => calls.add('clearCovers'),
        reloadOpenLists: () async => calls.add('reloadLists'),
      );
      expect(out.ok, isTrue);
      expect(out.works, 12);
      expect(calls,
          ['reindex:lib-001', 'reloadLibs', 'clearCovers', 'reloadLists']);
    });

    test('重建失败即终止：不清缓存、不重拉快照', () async {
      final calls = <String>[];
      final out = await runLibRefresh(
        lib: 'lib-002',
        reindex: (body) async {
          calls.add('reindex');
          return (status: 207, body: <String, dynamic>{
            'ok': false,
            'libs': [
              {'lib': 'lib-002', 'ok': false, 'error': '已保留旧索引'}
            ],
          });
        },
        reloadLibraries: () async => calls.add('reloadLibs'),
        clearLibCovers: () async => calls.add('clearCovers'),
        reloadOpenLists: () async => calls.add('reloadLists'),
      );
      expect(out.ok, isFalse);
      expect(calls, ['reindex']);
    });

    test('后两步异常不影响「已刷新」结论（数据已重建成功）', () async {
      var cleared = false;
      final out = await runLibRefresh(
        lib: 'lib-003',
        reindex: (body) async =>
            (status: 200, body: <String, dynamic>{'ok': true, 'libs': [
              {'lib': 'lib-003', 'ok': true, 'works': 1}
            ]}),
        reloadLibraries: () async => throw StateError('net'),
        clearLibCovers: () async {
          cleared = true;
          throw StateError('cache');
        },
        reloadOpenLists: () async => throw StateError('list'),
      );
      expect(out.ok, isTrue);
      expect(cleared, isTrue);
    });

    test('网络异常转成失败提示，不抛出到 UI', () async {
      final out = await runLibRefresh(
        lib: 'lib-004',
        reindex: (body) async => throw StateError('socket closed'),
        reloadLibraries: () async {},
        clearLibCovers: () async {},
      );
      expect(out.ok, isFalse);
      expect(out.message, contains('socket closed'));
    });

    test('空库 id 直接失败，不发请求', () async {
      var called = false;
      final out = await runLibRefresh(
        lib: '   ',
        reindex: (body) async {
          called = true;
          return (status: 200, body: <String, dynamic>{});
        },
        reloadLibraries: () async {},
        clearLibCovers: () async {},
      );
      expect(called, isFalse);
      expect(out.ok, isFalse);
    });
  });

  group('LibQuickRefreshButton', () {
    testWidgets('点击后转圈并禁用，完成后恢复并弹提示', (tester) async {
      var runs = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibQuickRefreshButton(
            libId: 'lib-001',
            onRefresh: () async {
              runs++;
              await Future<void>.delayed(const Duration(milliseconds: 30));
              return '已刷新 · 3 个作品';
            },
          ),
        ),
      ));
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lib-refresh-lib-001')));
      await tester.pump();
      // 转圈中：图标消失、按钮禁用。
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.onPressed, isNull);
      // 连点不会再发一次请求。
      await tester.tap(find.byType(IconButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(runs, 1);
      expect(find.text('已刷新 · 3 个作品'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('回调抛异常时把错误显示出来，不崩', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibQuickRefreshButton(
            libId: 'lib-009',
            onRefresh: () async => throw StateError('boom'),
          ),
        ),
      ));
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('错误'), findsNothing);
      expect(find.textContaining('boom'), findsOneWidget);
    });

    testWidgets('onRefresh 为空时按钮不可点', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: LibQuickRefreshButton(libId: 'lib-000'),
        ),
      ));
      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.onPressed, isNull);
    });
  });
}
