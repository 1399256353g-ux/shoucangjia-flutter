import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_grade.dart';
import 'package:shoucangjia/main.dart';

Widget host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

Widget hostFull(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(AuthorGrade.reset);
  tearDown(AuthorGrade.reset);

  group('AuthorGrade.fromStats', () {
    test('与 gradeFor 同一口径（播放/水滴/作品加权）', () {
      expect(AuthorGrade.fromStats({'p': 100, 'dr': 0}, works: 0),
          AuthorGrade.gradeFor(plays: 100, drops: 0, works: 0));
      expect(AuthorGrade.fromStats({'p': 0, 'dr': 50}, works: 0), 'B');
      expect(
          AuthorGrade.fromStats({'p': 122900, 'dr': 7}, works: 3),
          AuthorGrade.gradeFor(plays: 122900, drops: 7, works: 3));
    });

    test('统计缺失/非 Map 时按 0 计，只用作品数权重', () {
      expect(AuthorGrade.fromStats(null, works: 0), 'D');
      expect(AuthorGrade.fromStats(const [], works: 0), 'D');
      expect(AuthorGrade.fromStats(null, works: 60), 'C');
      expect(AuthorGrade.fromStats({'p': '300'}, works: 0), 'C');
    });
  });

  group('作者卡组件', () {
    testWidgets('AuthorAvatar 空头像显示首字母，尺寸规格统一', (tester) async {
      await tester.pumpWidget(host(
        const AuthorAvatar(name: 'Alice', mediaPath: '', size: 58),
      ));
      expect(find.text('A'), findsOneWidget);
      expect(tester.getSize(find.byType(AuthorAvatar)), const Size(58, 58));

      await tester.pumpWidget(host(
        const AuthorAvatar(
            name: 'Bob', mediaPath: '', size: AuthorAvatar.rankSize),
      ));
      expect(find.text('B'), findsOneWidget);
      expect(tester.getSize(find.byType(AuthorAvatar)),
          const Size(AuthorAvatar.rankSize, AuthorAvatar.rankSize));
    });

    testWidgets('AuthorGridCard 显示名称/统计/作品数与等级词条', (tester) async {
      await tester.pumpWidget(host(AuthorGridCard(
        name: '作者甲',
        avatar: '',
        lib: 'lib-001',
        meta: null,
        stats: const {'p': 100, 'dr': 0},
        works: 7,
        subtitle: '播放 100',
      )));
      expect(find.text('作者甲'), findsOneWidget);
      expect(find.text('播放 100'), findsOneWidget);
      expect(find.text('7 作品'), findsOneWidget);
      expect(find.text('作'), findsOneWidget); // 头像首字母
      // 等级走 AuthorGrade：p=100 + 7×2 → C
      expect(find.text('C'), findsOneWidget);
      expect(find.text('SECRET'), findsOneWidget);
    });

    testWidgets('AuthorGridCard 显式 stats 覆盖 meta 统计', (tester) async {
      final meta = LibMeta(basics: const [], stats: const {
        '作者乙': {'p': 0, 'dr': 0},
      });
      await tester.pumpWidget(host(AuthorGridCard(
        name: '作者乙',
        avatar: '',
        lib: 'lib-001',
        meta: meta,
        stats: const {'p': 9000, 'dr': 0}, // 跨库合并后的统计
        works: 1,
        subtitle: '播放 9000',
      )));
      expect(find.text('S'), findsOneWidget);
      expect(find.text('D'), findsNothing);
    });

    testWidgets('AuthorRankTile 显示排名/指标/分数与等级', (tester) async {
      await tester.pumpWidget(hostFull(
        AuthorRankTile(
          rank: 1,
          rankColor: Colors.amber,
          name: '作者丙',
          avatar: '',
          lib: 'lib-001',
          meta: LibMeta(basics: const [], stats: const {
            '作者丙': {'p': 2000, 'dr': 4},
          }),
          works: 3,
          plays: 2000,
          drops: 4,
          metric: 'drop',
          score: 4,
          onTap: () {},
        ),
      ));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('作者丙'), findsOneWidget);
      expect(find.text('播放 2000 · 水滴 4 · 作品 3'), findsOneWidget);
      // 数值类型在数字**前面**且单独一行，数字本身不带 emoji（owner 2026-11-27）：
      // 此前是 `💧 4`，宽度和纯数字不同，整列数字对不齐。
      expect(find.text('小水滴'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      // score = 2000 + 40 + 6 → A
      expect(find.text('A'), findsWidgets);
      expect(find.text('SECRET'), findsOneWidget);
    });
  });
}
