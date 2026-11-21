import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/basic_lib_page.dart';
import 'package:shoucangjia/library_tree.dart';

BasicLib _basic() => const BasicLib(
      id: 'lib-001',
      name: '测试库',
      rel: 'A/B',
      bigId: 'big-01',
      authors: 3,
      works: 10,
    );

Widget _host() => MaterialApp(
      home: BasicLibPage(
        basic: _basic(),
        urlOf: (path, {lib}) => Uri.parse('http://127.0.0.1:1$path'),
        headersOf: ([lib]) => const {},
        mediaUrlOf: (path, {lib}) => 'http://127.0.0.1:1$path',
        onOpenAuthor: (_) {},
      ),
    );

void main() {
  group('页面结构（owner 2026-11-19）', () {
    testWidgets('Tab 顺序：作品在前、作者在后，进入默认停在作品页', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();

      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.tabs.length, 2);
      expect((bar.tabs[0] as Tab).text, startsWith('作品'));
      expect((bar.tabs[1] as Tab).text, startsWith('作者'));
      expect(bar.controller!.index, 0, reason: '默认页应是作品');
      expect(find.byKey(const ValueKey('basic-tab-works')), findsOneWidget);
      expect(find.byKey(const ValueKey('basic-tab-authors')), findsOneWidget);

      // 点「作者」能切过去（索引 1），再回作品。
      await tester.tap(find.byKey(const ValueKey('basic-tab-authors')));
      await tester.pump();
      expect(bar.controller!.index, 1);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('作者卡片头像选择', () {
    test('有 av 时用 av', () {
      expect(
          pickAuthorAvatar(
              av: '/media/lib-01/av/me.jpg',
              fallback: '/media/lib-01/a/th.jpg'),
          '/media/lib-01/av/me.jpg');
    });

    test('av 为空时用兜底图（该作者作品首图）', () {
      expect(
          pickAuthorAvatar(av: '', fallback: '/media/lib-01/a/th.jpg'),
          '/media/lib-01/a/th.jpg');
      expect(pickAuthorAvatar(av: '   ', fallback: ' /media/x.jpg '),
          '/media/x.jpg');
    });

    test('都没有时为空（调用方回退首字占位）', () {
      expect(pickAuthorAvatar(), '');
      expect(pickAuthorAvatar(av: ' ', fallback: ''), '');
    });

    test('手动设置头像优先于爬虫与自动生成', () {
      expect(
          pickAuthorAvatar(
              manual: '/media/lib-01/av/manual.jpg',
              av: '/media/lib-01/av/crawler.jpg',
              fallback: '/media/lib-01/a/th.jpg'),
          '/media/lib-01/av/manual.jpg');
    });

    test('清除手动设置后回落到爬虫头像，再回落到自动生成', () {
      expect(
          pickAuthorAvatar(
              av: '/media/lib-01/av/crawler.jpg',
              fallback: '/media/lib-01/a/th.jpg'),
          '/media/lib-01/av/crawler.jpg');
      expect(
          pickAuthorAvatar(fallback: '/media/lib-01/a/th.jpg'),
          '/media/lib-01/a/th.jpg');
    });
  });
}
