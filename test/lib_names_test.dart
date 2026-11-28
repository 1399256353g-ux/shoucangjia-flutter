import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/lib_names.dart';
import 'package:shoucangjia/main.dart';

Widget host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('displayLibraryName', () {
    // owner 2026-11-27：多库并列后不存在「当前媒体库」这个状态词，
    // 旧名一律回落到库 id（真实标识），不再造一个假的库状态。
    test('旧版「抖音收藏」回落到库 id', () {
      expect(displayLibraryName('douyin', '抖音收藏'), 'douyin');
      expect(displayLibraryName('douyin', ' 抖音收藏 '), 'douyin');
    });

    test('其它库带同样字样时回落到 id，不展示旧名', () {
      expect(displayLibraryName('lib-008', '抖音收藏'), 'lib-008');
      expect(displayLibraryName('lib-008', '（2）douyin'), '（2）douyin');
    });

    test('正常名称原样保留，空名回落 id', () {
      expect(displayLibraryName('big-05', '(Hidden directory)'),
          '(Hidden directory)');
      expect(displayLibraryName('lib-009', null), 'lib-009');
      expect(displayLibraryName('lib-009', ''), 'lib-009');
    });
  });

  group('librariesWithDisplayNames', () {
    test('替换 name 但不改动原列表', () {
      final src = <Map<String, dynamic>>[
        {'id': 'lib-008', 'name': '(2) douyin'},
        {'id': 'lib-009', 'name': '抖音收藏'},
      ];
      final out = librariesWithDisplayNames(src);
      // `lib-009` 名字带旧名「抖音收藏」→ 回落 id。
      expect(out[0]['name'], '(2) douyin');
      expect(out[1]['name'], 'lib-009');
      // 原列表不能被改。
      expect(src[0]['name'], '(2) douyin');
      expect(src[1]['name'], '抖音收藏');
    });

    test('遗留元数据库 douyin 在入口就被滤掉（不是媒体库）', () {
      // owner 2026-11-28：「当前根本就没有这个媒体库，douyin 现在就是个普通的
      // 单元库而已」。服务端 `/api/libraries` 里那条 `id=douyin`（`dir` 指向
      // 元数据目录、不在库根下）不得当成媒体库出现在爬虫分节/各库排行/诊断。
      final src = <Map<String, dynamic>>[
        {'id': 'douyin', 'name': '抖音收藏'},
        {'id': 'lib-008', 'name': '(2) douyin'},
      ];
      expect(isLegacyMetaLibrary(src[0]), isTrue);
      expect(isLegacyMetaLibrary(src[1]), isFalse);
      final out = librariesWithDisplayNames(src);
      expect(out, hasLength(1));
      expect(out.single['id'], 'lib-008');
      // 原列表不动。
      expect(src, hasLength(2));
    });
  });

  group('词条不再回退旧库名', () {
    testWidgets('UnitBadges 无单元库归属时显示 SECRET', (tester) async {
      // 0.9.317：`fallbackId` 已从 UnitBadges 删除（零读取方）。
      // 无归属一律 SECRET，没有任何「回退显示库名」的路。
      await tester.pumpWidget(host(const UnitBadges(
        meta: null,
        mediaPath: 'a/b/cover.jpg',
      )));
      expect(find.text('SECRET'), findsOneWidget);
      expect(find.text('抖音收藏'), findsNothing);
    });
  });

  test('lib/ 源码中「抖音收藏」只允许出现在注释或 lib_names.dart', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue, reason: '需在 flutterapp 项目根目录运行');
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains(legacyDouyinName)) continue;
        final trimmed = lines[i].trimLeft();
        final allowed = trimmed.startsWith('//') ||
            f.path.replaceAll('\\', '/').endsWith('lib/lib_names.dart');
        expect(allowed, isTrue,
            reason: '${f.path}:${i + 1} 仍把旧库名当文案：${lines[i]}');
      }
    }
  });
}
