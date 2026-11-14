import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/main.dart';
import 'package:shoucangjia/watch_progress.dart';

void main() {
  testWidgets('WorkGrid 首屏只渲染一页，滚动到底部后追加', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await WatchProgressStore.ensureLoaded();
    final works = List<Map<String, dynamic>>.generate(
        130,
        (i) => <String, dynamic>{
              'id': 'w$i',
              't': 'v',
              'th': '',
              'ti': '作品 $i',
              'a': '作者',
            });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
            width: 400,
            height: 800,
            child: WorkGrid(works: works, lib: 'douyin')),
      ),
    ));
    await tester.pump();

    SliverChildBuilderDelegate delegate() {
      final grid = tester.widget<GridView>(find.byType(GridView));
      return grid.childrenDelegate as SliverChildBuilderDelegate;
    }

    // 130 条作品首屏只构建一页 60 条
    expect(delegate().childCount, 60);

    await tester.drag(find.byType(GridView), const Offset(0, -20000));
    await tester.pumpAndSettle();

    // 滚到底部后追加下一页，且不会超过总数
    expect(delegate().childCount, greaterThan(60));
    expect(delegate().childCount, lessThanOrEqualTo(130));
  });

  testWidgets('空作品列表显示占位而不是空白', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: WorkGrid(works: [])),
    ));
    expect(find.text('暂无作品'), findsOneWidget);
  });

  testWidgets('骨架屏渲染占位块', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: WorkGridSkeleton(count: 6)),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SkeletonBlock), findsWidgets);
  });
}
