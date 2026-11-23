import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_controls.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('倍速文案', () {
    test('一位/两位小数，末尾 0 只留一位', () {
      expect(speedLabel(1.0), '1.0x');
      expect(speedLabel(1.25), '1.25x');
      expect(speedLabel(0.75), '0.75x');
      expect(speedLabel(2.0), '2.0x');
    });
  });

  group('剧集入口', () {
    testWidgets('显示 1/12，触达区 ≥44dp，点击回调', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(TaskbarEpisodeButton(
        current: 1,
        total: 12,
        onPressed: () => taps++,
      )));
      expect(find.text('1/12'), findsOneWidget);
      final size = tester.getSize(find.byKey(const Key('taskbar-episodes')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(const Key('taskbar-episodes')));
      expect(taps, 1);
    });

    testWidgets('窄屏宽度也夹到 44dp', (tester) async {
      await tester.pumpWidget(host(TaskbarEpisodeButton(
        current: 3,
        total: 9,
        width: 20,
        onPressed: () {},
      )));
      final size = tester.getSize(find.byKey(const Key('taskbar-episodes')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(find.text('3/9'), findsOneWidget);
    });
  });

  group('播放设置入口', () {
    testWidgets('显示当前倍速并可点击', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(TaskbarSettingsButton(
        speed: 1.25,
        onPressed: () => taps++,
      )));
      expect(find.text('1.25x'), findsOneWidget);
      final size = tester.getSize(find.byKey(const Key('taskbar-settings')));
      expect(size.width, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(const Key('taskbar-settings')));
      expect(taps, 1);
    });
  });

  group('声音入口', () {
    testWidgets('点击静音回调；长按可调音量', (tester) async {
      var taps = 0;
      var holds = 0;
      await tester.pumpWidget(host(TaskbarSoundButton(
        muted: false,
        volume: 70,
        onTap: () => taps++,
        onLongPressStart: (_) => holds++,
      )));
      final size = tester.getSize(find.byKey(const Key('taskbar-sound')));
      expect(size.width, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(const Key('taskbar-sound')));
      expect(taps, 1);
      await tester.longPress(find.byKey(const Key('taskbar-sound')));
      expect(holds, 1);
    });
  });

  group('显示入口', () {
    testWidgets('移动端：点按=全屏，长按=横竖屏', (tester) async {
      var taps = 0;
      var longs = 0;
      await tester.pumpWidget(host(TaskbarDisplayButton(
        fullscreen: false,
        mobile: true,
        onPressed: () => taps++,
        onLongPress: () => longs++,
      )));
      final size = tester.getSize(find.byKey(const Key('taskbar-display')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(find.byKey(const Key('taskbar-fullscreen')), findsNothing);
      await tester.tap(find.byKey(const Key('taskbar-display')));
      expect(taps, 1);
      await tester.longPress(find.byKey(const Key('taskbar-display')));
      expect(longs, 1);
    });

    testWidgets('桌面端：保留独立全屏按钮，不出现移动端长按入口', (tester) async {
      await tester.pumpWidget(host(TaskbarDisplayButton(
        fullscreen: true,
        mobile: false,
        onPressed: () {},
      )));
      expect(find.byKey(const Key('taskbar-fullscreen')), findsOneWidget);
      expect(find.byKey(const Key('taskbar-display')), findsNothing);
      final icon = tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('taskbar-fullscreen')),
          matching: find.byType(Icon)));
      expect(icon.icon, Icons.fullscreen_exit);
    });
  });
}
