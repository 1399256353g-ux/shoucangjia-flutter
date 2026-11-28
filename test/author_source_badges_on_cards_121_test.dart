import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_grade.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/main.dart'
    show AuthorGridCard, AuthorRankTile, LibMeta;
import 'package:shoucangjia/unit_library.dart';

/// 0.9.373 第一百二十一批：
///
/// owner 2026-11-27 的原话是「多挂载作者挂几个文件夹就贴几个到主页和卡片」。
/// 作者页与播放页早就在传 `basicIds`，而**作者总览卡**与**排行榜行**只传了
/// `fallbackId`——那是「路径解析不出归属时的回落值」，于是同一个作者在这两处
/// 永远只有一条词条。两处的数据其实都在手里：
///
/// ```
/// 作者总览：authorLibs[name]（服务端 /api/authors.json 的 libs）
/// 排行榜：  e['libs']（服务端 lib=all 下发的来源基础库）
/// ```
///
/// 这一批只做「把已有的数据接到已有的入口」，不改任何配色/几何。

BasicLib _b(String id, String name, String rel) => BasicLib(
      id: id,
      name: name,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 2,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 200, height: 240, child: child)),
    );

void main() {
  setUp(AuthorGrade.reset);
  tearDown(AuthorGrade.reset);

  final meta = LibMeta(
    basics: [
      _b('lib-001', '甲库', 'root/甲库'),
      _b('lib-002', '乙库', 'root/乙库'),
    ],
    stats: const {},
  );

  testWidgets('排行榜行：两条来源基础库 → 折叠后给展开键，展开后两条都在', (tester) async {
    await tester.pumpWidget(_host(AuthorRankTile(
      rank: 1,
      rankColor: Colors.amber,
      name: '作者甲',
      avatar: '',
      lib: 'lib-001',
      libs: const ['lib-001', 'lib-002'],
      meta: meta,
      works: 3,
      plays: 10,
      drops: 1,
      score: 10,
    )));

    // 常态折叠：基础库词条收进展开键（owner：「平日里可把基础库等词条隐藏起来」）。
    expect(find.byKey(const ValueKey('badge-expand')), findsOneWidget);
    expect(find.text('甲库'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('badge-expand')));
    await tester.pumpAndSettle();

    expect(find.text('甲库'), findsOneWidget);
    expect(find.text('乙库'), findsOneWidget);
  });

  testWidgets('排行榜行：只有一条来源时折叠为一个展开键，展开后可见', (tester) async {
    await tester.pumpWidget(_host(AuthorRankTile(
      rank: 2,
      rankColor: Colors.blueGrey,
      name: '作者乙',
      avatar: '',
      lib: 'lib-001',
      libs: const ['lib-001'],
      meta: meta,
      works: 1,
      plays: 1,
      drops: 0,
      score: 1,
    )));
    // 常态折叠（「平日里可把基础库等词条隐藏起来」）：一条基础库也收进
    // 末尾的展开键；展开后仍能看见，卡片不会因此变成空的。
    expect(find.byKey(const ValueKey('badge-expand')), findsOneWidget);
    expect(find.text('作者乙'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('badge-expand')));
    await tester.pumpAndSettle();
    expect(find.text('甲库'), findsOneWidget);
  });

  testWidgets('作者总览卡：两条来源基础库同样折叠为展开键，展开后都在', (tester) async {
    await tester.pumpWidget(_host(AuthorGridCard(
      name: '作者丙',
      avatar: '',
      lib: 'lib-001',
      libs: const ['lib-001', 'lib-002'],
      meta: meta,
      stats: const {},
      works: 4,
      subtitle: '播放 9',
    )));

    expect(find.byKey(const ValueKey('badge-expand')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('badge-expand')));
    await tester.pumpAndSettle();
    expect(find.text('甲库'), findsOneWidget);
    expect(find.text('乙库'), findsOneWidget);
  });

  test('两处卡片的来源列表都来自调用方，不是自己扫路径', () {
    final src = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    // 排行榜行：服务端 `lib=all` 的 `libs` 直接透传。
    expect(src.contains("libs: stringsOf(e['libs'])"), isTrue);
    // 作者总览：页面手里的 authorLibs。
    expect(src.contains('libs: authorLibs[e.key] ?? const <String>[]'), isTrue);
    // 两处词条入口都必须把 basicIds 交给 AuthorBadges（这是词条逐条贴的唯一通路）。
    expect('basicIds: libs,'.allMatches(src).length, 2,
        reason: 'AuthorRankTile 与 AuthorGridCard 各一处');
    // `libName` 是构造后从未被读取的死字段（每行还要为它扫一遍库列表），已删。
    expect(src.contains('final String libName;'), isFalse);
  });

  test('排行榜页不再为算 libName 逐行扫注册库列表', () {
    final src = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final start = src.indexOf('class _RankPageState');
    final end = src.indexOf('class LibraryRankPage');
    expect(start, greaterThan(0));
    final body = src.substring(start, end);
    expect(body.contains('String libName(String id)'), isFalse);
    expect(body.contains('List<Map<String, dynamic>> libs'), isFalse,
        reason: '本页唯一读取方是 libName，两者一起删');
  });
}
