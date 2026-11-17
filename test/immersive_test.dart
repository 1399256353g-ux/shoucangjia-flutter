import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/immersive.dart';

/// P2 §12/§13：非全屏沉浸计时、重置策略与翻页震动去重。
void main() {
  group('§12 沉浸资格', () {
    bool eligible({
      bool fullscreen = false,
      bool uiVisible = true,
      bool pageSwiping = false,
      bool overlayOpen = false,
      bool dragging = false,
      bool seeking = false,
    }) =>
        ImmersivePolicy.eligible(
          fullscreen: fullscreen,
          uiVisible: uiVisible,
          pageSwiping: pageSwiping,
          overlayOpen: overlayOpen,
          dragging: dragging,
          seeking: seeking,
        );

    test('平静的浏览态才允许沉浸', () {
      expect(eligible(), isTrue);
    });

    test('全屏一律不允许（全屏走 M4，不进入沉浸）', () {
      expect(eligible(fullscreen: true), isFalse);
    });

    test('功能区已隐藏 / 翻页 / 面板 / 拖动 / seek 都不允许', () {
      expect(eligible(uiVisible: false), isFalse);
      expect(eligible(pageSwiping: true), isFalse);
      expect(eligible(overlayOpen: true), isFalse);
      expect(eligible(dragging: true), isFalse);
      expect(eligible(seeking: true), isFalse);
    });

    test('不透明度：隐藏为 0，沉浸为 0，正常为 1', () {
      expect(ImmersivePolicy.opacity(uiVisible: false, immersive: false), 0);
      expect(ImmersivePolicy.opacity(uiVisible: true, immersive: true), 0);
      expect(ImmersivePolicy.opacity(uiVisible: true, immersive: false), 1);
    });

    test('淡出时长固定 200ms，其余沿用原时长', () {
      expect(kImmersiveFadeMs, 200);
      expect(kImmersiveIdle, const Duration(seconds: 3));
      expect(ImmersivePolicy.durationMs(immersive: true, fallbackMs: 800), 200);
      expect(
          ImmersivePolicy.durationMs(immersive: false, fallbackMs: 800), 800);
    });
  });

  group('§12 沉浸计时/重置', () {
    test('未到 3 秒不进入，到点且合规才进入一次', () {
      final c = ImmersiveCycle();
      c.schedule(1000);
      expect(c.tick(3999, eligible: true), isFalse);
      expect(c.immersive, isFalse);
      expect(c.tick(4000, eligible: true), isTrue);
      expect(c.immersive, isTrue);
      // 已进入后重复回调不再触发重建
      expect(c.tick(5000, eligible: true), isFalse);
    });

    test('到点但不可沉浸（例如正在翻页）不进入', () {
      final c = ImmersiveCycle();
      c.schedule(0);
      expect(c.tick(3000, eligible: false), isFalse);
      expect(c.immersive, isFalse);
    });

    test('任何交互立即退出沉浸并清掉计时', () {
      final c = ImmersiveCycle();
      c.schedule(0);
      c.tick(3000, eligible: true);
      expect(c.immersive, isTrue);
      c.touch();
      expect(c.immersive, isFalse);
      expect(c.scheduled, isFalse);
      expect(c.tick(9999, eligible: true), isFalse);
    });

    test('重新计时：touch 后 schedule，必须重新等满 3 秒', () {
      final c = ImmersiveCycle();
      c.schedule(0);
      c.tick(3000, eligible: true);
      c.touch();
      c.schedule(3000);
      expect(c.tick(5999, eligible: true), isFalse);
      expect(c.tick(6000, eligible: true), isTrue);
    });

    test('cancel 后不再进入沉浸', () {
      final c = ImmersiveCycle();
      c.schedule(0);
      c.cancel();
      expect(c.scheduled, isFalse);
      expect(c.tick(4000, eligible: true), isFalse);
      expect(c.immersive, isFalse);
    });

    test('未排定时的 tick 永远不进入', () {
      final c = ImmersiveCycle();
      expect(c.tick(999999, eligible: true), isFalse);
    });
  });

  group('§13 翻页震动去重', () {
    test('同一目标只放行一次，换目标再放行', () {
      final g = SwitchHapticGate();
      expect(g.allow(3), isTrue);
      expect(g.allow(3), isFalse);
      expect(g.allow(4), isTrue);
      expect(g.allow(3), isTrue);
    });

    test('reset 后可重新放行', () {
      final g = SwitchHapticGate();
      expect(g.allow(1), isTrue);
      expect(g.allow(1), isFalse);
      g.reset();
      expect(g.allow(1), isTrue);
    });

    test('只有移动端发震动', () {
      expect(hapticAllowedFor(isAndroid: true, isIOS: false), isTrue);
      expect(hapticAllowedFor(isAndroid: false, isIOS: true), isTrue);
      expect(hapticAllowedFor(isAndroid: false, isIOS: false), isFalse);
    });
  });
}
