import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_controls.dart';

void main() {
  group('P1 §1 互动栏数值', () {
    test('头像/徽标/图标/间距与规格一致', () {
      expect(kRailAvatarSize, 44);
      expect(kRailBadgeSize, 22);
      expect(kRailBadgeOverhang, 8);
      expect(kRailIconSize, 32);
      expect(kRailCountFontSize, 11);
      expect(kRailItemGap, 18);
      expect(kRailRightMargin, 10);
      expect(kRailBottomGap, 12);
      expect(kRailAvatarGap, 20);
      expect(kRailTouchSize, greaterThanOrEqualTo(48));
      expect(kRailAccent, const Color(0xFFFE2C55));
    });

    test('数字格式：0 隐藏、万位紧凑', () {
      expect(formatRailCount(0), '');
      expect(formatRailCount(-3), '');
      expect(formatRailCount(7), '7');
      expect(formatRailCount(9999), '9999');
      expect(formatRailCount(10000), '1万');
      expect(formatRailCount(12345), '1.2万');
      expect(formatRailCount(1234567), '123万');
    });

    testWidgets('四项互动 + 头像徽标，点击回调', (tester) async {
      var like = 0, comment = 0, fav = 0, share = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayerInteractionRail(
              avatar: const ColoredBox(color: Colors.blue),
              liked: true,
              likeCount: 12,
              commentCount: 3,
              favoriteCount: 0,
              onLike: () => like++,
              onComment: () => comment++,
              onFavorite: () => fav++,
              onShare: () => share++,
            ),
          ),
        ),
      ));
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.mode_comment_outlined), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.tap(find.byIcon(Icons.mode_comment_outlined));
      await tester.tap(find.byIcon(Icons.star_border));
      await tester.tap(find.byIcon(Icons.share));
      expect([like, comment, fav, share], [1, 1, 1, 1]);
    });

    testWidgets('点赞激活色为品牌红', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerInteractionRail(
            avatar: const SizedBox(),
            liked: true,
            onLike: () {},
            onComment: () {},
            onFavorite: () {},
            onShare: () {},
          ),
        ),
      ));
      final icon = tester.widget<Icon>(find.byIcon(Icons.favorite));
      expect(icon.color, kRailAccent);
    });
  });

  group('P1 §2 信息区', () {
    test('文案最大宽度 = 屏宽 − 右栏 84 − 左边距 12', () {
      expect(infoAreaMaxWidth(375), 279);
      expect(infoAreaMaxWidth(320), 224);
      expect(infoAreaMaxWidth(0), 0);
      expect(infoAreaMaxWidth(double.nan), 0);
      expect(kInfoLeftMargin, 12);
      expect(kMusicIconSize, 16);
      expect(kMusicIconGap, 6);
      expect(kMusicFontSize, 13);
      expect(kInfoSecondaryColor, const Color(0xE6FFFFFF));
      expect(kMarqueeSpeed, 40);
      expect(kMarqueePause, const Duration(seconds: 2));
      expect(kInfoBottomGap, 12);
    });

    test('跑马灯位移：滚动 40px/s，到末尾停 2s 后重来', () {
      // 文本 140，可视 100 → 距离 40 → 滚动 1s，周期 3s。
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 0, textWidth: 140, viewWidth: 100),
          0);
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 0.5, textWidth: 140, viewWidth: 100),
          -20);
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 1.0, textWidth: 140, viewWidth: 100),
          -40);
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 2.5, textWidth: 140, viewWidth: 100),
          -40);
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 3.0, textWidth: 140, viewWidth: 100),
          0);
      // 不超宽不滚
      expect(
          marqueeOffsetAt(
              elapsedSeconds: 1.5, textWidth: 80, viewWidth: 100),
          0);
      expect(
          marqueeCycleSeconds(textWidth: 140, viewWidth: 100), closeTo(3, 1e-9));
      expect(
          marqueeCycleSeconds(textWidth: 80, viewWidth: 100), 0);
    });

    test('文案行数：超过 2 行才需要展开', () {
      const style = TextStyle(fontSize: 14, height: 1.35);
      expect(captionNeedsExpand('短文案', style, 200), isFalse);
      final long = List.filled(80, '很长的文案').join();
      expect(captionNeedsExpand(long, style, 200), isTrue);
      expect(kCaptionMaxLines, 2);
      expect(kCaptionFontSize, 14);
      expect(kCaptionHeight, 1.35);
    });

    testWidgets('作者/文案/音乐渲染，展开按钮可达', (tester) async {
      const long = '这是一段会超过两行显示范围的文案内容，'
          '用来验证展开按钮会出现并且点击后进入全文模式。';
      var toggled = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: PlayerInfoPanel(
              author: '张三',
              caption: long,
              music: '张三 的原声',
              maxWidth: infoAreaMaxWidth(375),
              onToggleExpand: () => toggled++,
            ),
          ),
        ),
      ));
      expect(find.text('@张三'), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.text('展开'), findsOneWidget);
      await tester.tap(find.text('展开'));
      expect(toggled, 1);
    });

    testWidgets('320 窄屏不溢出', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 640)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: PlayerInfoPanel(
                author: '一个很长很长的作者名字用来测试省略',
                caption: '文案也很长，需要在窄屏下自动省略而不是溢出屏幕边界。',
                music: '一段同样很长很长的音乐名称用于跑马灯测试',
                maxWidth: infoAreaMaxWidth(320),
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('P1 §4 任务栏', () {
    test('间距：默认 28、320 窄屏 20、并夹在最低 16', () {
      expect(taskbarSpacingFor(375), 28);
      expect(taskbarSpacingFor(390), 28);
      expect(taskbarSpacingFor(360), 28);
      expect(taskbarSpacingFor(320), 20);
      expect(taskbarSpacingFor(300), 20);
      expect(taskbarSpacingFor(340), closeTo(24, 1e-9));
      expect(taskbarSpacingFor(double.nan), 28);
      expect(kTaskbarHeight, 56);
      expect(kTaskbarIconSize, 24);
      expect(kTaskbarSidePadding, 16);
      expect(kTaskbarDividerColor, const Color(0x1AFFFFFF));
      expect(kTaskbarInactiveColor, const Color(0xB3FFFFFF));
    });
  });
}
