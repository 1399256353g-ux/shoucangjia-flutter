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
        {'id': 'douyin', 'name': '抖音收藏', 'count': 1502},
        {'id': 'lib-008', 'name': '(2) douyin'},
      ];
      final out = librariesWithDisplayNames(src);
      expect(out[0]['name'], 'douyin');
      expect(out[0]['count'], 1502);
      expect(out[1]['name'], '(2) douyin');
      expect(src[0]['name'], '抖音收藏');
    });
  });

  group('词条不再回退旧库名', () {
    testWidgets('UnitBadges 无单元库归属时显示 SECRET', (tester) async {
      await tester.pumpWidget(host(const UnitBadges(
        meta: null,
        mediaPath: 'a/b/cover.jpg',
        fallbackId: 'douyin',
        fallbackName: '抖音收藏',
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
