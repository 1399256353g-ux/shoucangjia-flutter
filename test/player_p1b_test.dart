import 'dart:ui' show Color, Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/player_controls.dart';

/// P1b：非全屏长按菜单 + 评论半屏面板（§8/§9，动画 §5）。
void main() {
  group('§8 长按判定', () {
    test('阈值：500ms / 12px', () {
      expect(kStageLongPressMs, 500);
      expect(kStageLongPressMaxMove, 12);
      expect(kStageMenuLabels,
          ['不感兴趣', '保存到本机', '复制文案', '举报']);
    });

    test('恰好 500ms 且位移 ≤12 算长按', () {
      expect(stageLongPressQualifies(holdMs: 500, moved: 12), isTrue);
      expect(stageLongPressQualifies(holdMs: 499, moved: 0), isFalse);
      expect(stageLongPressQualifies(holdMs: 900, moved: 12.1), isFalse);
    });

    test('跟踪器：按住到点触发，且只触发一次', () {
      final t = StageLongPressTracker();
      t.begin(nowMs: 1000, pos: const Offset(50, 300));
      expect(t.shouldFire(1400), isFalse);
      expect(t.shouldFire(1500), isTrue);
      t.fire();
      expect(t.fired, isTrue);
      expect(t.shouldFire(2000), isFalse);
    });

    test('跟踪器：位移超过 12px 取消', () {
      final t = StageLongPressTracker();
      t.begin(nowMs: 1000, pos: const Offset(50, 300));
      expect(t.update(const Offset(50, 311)), isTrue);
      expect(t.update(const Offset(50, 313)), isFalse);
      expect(t.shouldFire(1600), isFalse);
    });

    test('跟踪器：cancel 后不再触发', () {
      final t = StageLongPressTracker();
      t.begin(nowMs: 1000, pos: const Offset(50, 300));
      t.cancel();
      expect(t.tracking, isFalse);
      expect(t.shouldFire(2000), isFalse);
    });
  });

  group('§8 长按可触发区域', () {
    const size = Size(390, 844);

    bool allowed(Offset p, {bool fs = false}) => stageLongPressAllowed(
          position: p,
          stageSize: size,
          topInset: 44,
          bottomInset: 100,
          rightInset: 84,
          fullscreen: fs,
        );

    test('舞台中央可长按', () {
      expect(allowed(const Offset(150, 400)), isTrue);
    });

    test('顶栏 / 底部进度任务栏 / 右侧互动栏被排除', () {
      expect(allowed(const Offset(150, 60)), isFalse);
      expect(allowed(const Offset(150, 800)), isFalse);
      expect(allowed(const Offset(340, 400)), isFalse);
    });

    test('全屏一律不触发', () {
      expect(allowed(const Offset(150, 400), fs: true), isFalse);
    });
  });

  group('§9 评论面板 snap', () {
    test('初始比例 60%', () {
      expect(kCommentPanelInitialFraction, 0.6);
      expect(kCommentPanelFullFraction, 1.0);
      expect(kOverlayAnimMs, 200);
      expect(kStageScrimColor, const Color(0x66000000));
    });

    test('慢速松手按最近档位吸附', () {
      expect(commentPanelSnap(fraction: 0.1, velocity: 0), 0.0);
      expect(commentPanelSnap(fraction: 0.45, velocity: 0), 0.6);
      expect(commentPanelSnap(fraction: 0.7, velocity: 0), 0.6);
      expect(commentPanelSnap(fraction: 0.92, velocity: 0), 1.0);
    });

    test('上滑快速甩到全屏，下滑快速关闭', () {
      expect(commentPanelSnap(fraction: 0.6, velocity: -900), 1.0);
      expect(commentPanelSnap(fraction: 0.4, velocity: 900), 0.0);
      expect(commentPanelSnap(fraction: 0.95, velocity: 900), 0.6);
    });

    test('高度按屏高换算并夹取', () {
      expect(commentPanelHeight(fraction: 0.6, screenHeight: 800), 480);
      expect(commentPanelHeight(fraction: 1.2, screenHeight: 800), 800);
      expect(commentPanelHeight(fraction: -1, screenHeight: 800), 0);
    });
  });

  group('§8 保存到本机', () {
    test('移动端不支持、桌面支持', () {
      expect(mediaDownloadSupported(android: true, ios: false), isFalse);
      expect(mediaDownloadSupported(android: false, ios: true), isFalse);
      expect(mediaDownloadSupported(android: false, ios: false), isTrue);
    });

    test('扩展名推断与安全文件名', () {
      expect(mediaSaveExtension(url: 'http://h/a/b.mp4'), '.mp4');
      expect(mediaSaveExtension(url: 'http://h/a/b.MOV'), '.mov');
      expect(mediaSaveExtension(url: 'http://h/a/b'), '.mp4');
      expect(mediaSaveExtension(url: 'http://h/a/b', video: false), '.jpg');
      final name = mediaSaveFileName(base: 'a/b:c*?', url: 'http://h/x.mp4');
      expect(name, 'abc.mp4');
      expect(mediaSaveFileName(base: '  ', url: 'http://h/x.mp4'),
          startsWith('dizi_'));
    });
  });
}
