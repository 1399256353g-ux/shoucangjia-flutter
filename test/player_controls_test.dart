import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_controls.dart';

void main() {
  _m3DesktopTests();
  group('screenModeOf / toggledMode', () {
    test('竖屏尺寸判定为 portrait（含正方形）', () {
      expect(screenModeOf(const Size(390, 844)), ScreenMode.portrait);
      expect(screenModeOf(const Size(500, 500)), ScreenMode.portrait);
    });

    test('横屏尺寸判定为 landscape', () {
      expect(screenModeOf(const Size(844, 390)), ScreenMode.landscape);
    });

    test('切换在竖屏与横屏之间往返', () {
      expect(toggledMode(ScreenMode.portrait), ScreenMode.landscape);
      expect(toggledMode(ScreenMode.landscape), ScreenMode.portrait);
      expect(
        toggledMode(toggledMode(ScreenMode.portrait)),
        ScreenMode.portrait,
      );
    });
  });

  group('orientationsFor', () {
    test('竖屏只允许 portraitUp', () {
      expect(orientationsFor(ScreenMode.portrait),
          const [DeviceOrientation.portraitUp]);
    });

    test('横屏允许左右两个方向（M2：两侧都能用）', () {
      expect(orientationsFor(ScreenMode.landscape), const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    });
  });

  group('showRotateButton', () {
    test('Android/iOS 显示横竖屏按钮', () {
      expect(showRotateButton(isAndroid: true, isIOS: false), isTrue);
      expect(showRotateButton(isAndroid: false, isIOS: true), isTrue);
    });

    test('Windows/桌面不显示（M3 交互不变）', () {
      expect(showRotateButton(isAndroid: false, isIOS: false), isFalse);
    });
  });

  group('TaskbarPlayButton', () {
    Future<void> pump(WidgetTester tester, {required bool paused}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskbarPlayButton(paused: paused, onPressed: () {}),
        ),
      ));
    }

    testWidgets('播放中显示暂停图标与「暂停」提示', (tester) async {
      await pump(tester, paused: false);
      final icon = tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('taskbar-play')),
          matching: find.byType(Icon)));
      expect(icon.icon, Icons.pause);
      expect(find.byTooltip('暂停'), findsOneWidget);
    });

    testWidgets('暂停时显示播放图标与「播放」提示（状态同步）', (tester) async {
      await pump(tester, paused: true);
      final icon = tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('taskbar-play')),
          matching: find.byType(Icon)));
      expect(icon.icon, Icons.play_arrow);
      expect(find.byTooltip('播放'), findsOneWidget);
    });

    testWidgets('点击触发回调', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskbarPlayButton(paused: false, onPressed: () => taps++),
        ),
      ));
      await tester.tap(find.byKey(const Key('taskbar-play')));
      expect(taps, 1);
    });
  });

  group('TaskbarRotateButton', () {
    Future<void> pump(WidgetTester tester, ScreenMode mode) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TaskbarRotateButton(mode: mode, onPressed: () {}),
        ),
      ));
    }

    testWidgets('竖屏时提示「横屏」并显示横屏图标', (tester) async {
      await pump(tester, ScreenMode.portrait);
      expect(find.byTooltip('横屏'), findsOneWidget);
      final icon = tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('taskbar-rotate')),
          matching: find.byType(Icon)));
      expect(icon.icon, Icons.screen_lock_landscape);
    });

    testWidgets('横屏时提示「竖屏」并显示竖屏图标', (tester) async {
      await pump(tester, ScreenMode.landscape);
      expect(find.byTooltip('竖屏'), findsOneWidget);
      final icon = tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('taskbar-rotate')),
          matching: find.byType(Icon)));
      expect(icon.icon, Icons.screen_lock_portrait);
    });
  });
}

void _m3DesktopTests() {
  group('M3 Windows/桌面任务栏', () {
    test('桌面端策略：播放/暂停常驻、横竖屏按钮不显示', () {
      final policy = taskbarPolicyFor(isAndroid: false, isIOS: false);
      expect(policy.showPlayPause, isTrue);
      expect(policy.showRotate, isFalse);
    });

    test('移动端策略：任务栏不放播放/暂停（由点击屏幕承担），只保留横竖屏', () {
      for (final p in [
        taskbarPolicyFor(isAndroid: true, isIOS: false),
        taskbarPolicyFor(isAndroid: false, isIOS: true),
      ]) {
        expect(p.showPlayPause, isFalse);
        expect(p.showRotate, isTrue);
      }
    });

    testWidgets('桌面任务栏只有播放/暂停，且点击后图标双向同步', (tester) async {
      final policy = taskbarPolicyFor(isAndroid: false, isIOS: false);
      var paused = false;
      late StateSetter setLocal;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            setLocal = setState;
            return Row(children: [
              TaskbarPlayButton(
                paused: paused,
                onPressed: () => setLocal(() => paused = !paused),
              ),
              if (policy.showRotate)
                const TaskbarRotateButton(
                    mode: ScreenMode.portrait, onPressed: _noop),
            ]);
          }),
        ),
      ));
      // 桌面端不得出现横竖屏按钮。
      expect(find.byKey(const Key('taskbar-rotate')), findsNothing);
      expect(find.byKey(const Key('taskbar-play')), findsOneWidget);
      // 播放中点击 → 暂停图标立即同步。
      await tester.tap(find.byKey(const Key('taskbar-play')));
      await tester.pump();
      var icon = tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('taskbar-play')),
          matching: find.byType(Icon)));
      expect(icon.icon, Icons.play_arrow);
      expect(find.byTooltip('播放'), findsOneWidget);
      // 再次点击 → 恢复暂停图标，验证双向同步。
      await tester.tap(find.byKey(const Key('taskbar-play')));
      await tester.pump();
      icon = tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('taskbar-play')),
          matching: find.byType(Icon)));
      expect(icon.icon, Icons.pause);
      expect(find.byTooltip('暂停'), findsOneWidget);
    });
  });
}

void _noop() {}
